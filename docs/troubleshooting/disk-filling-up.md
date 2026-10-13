# Disk filling up

Snapshots pile up on the SD card until it is full, and then motionEye and the OS start to fail.
In this fleet that happened in July 2026, with 4K snapshots every 5 seconds on 32 GB cards.

Commands assume Raspberry Pi OS (Trixie) and an admin account with sudo.

## Symptoms

- `df -h /` shows the root filesystem at or near 100%.
- New JPEGs in `/var/lib/motioneye` are 0 bytes. motionEye keeps creating files, but they are empty.
- Other services fail. After one fill, `man-db.service` was left failed and `systemctl --failed` was not empty.
- The journal fills with errors. Ours logged 8,000 to 15,000 a day in that period (some came
  from another fault at the same time).
- Timelapses built from the stills stop early. One truncated frame can end an ffmpeg concat run,
  and ffmpeg can still exit 0, so you get a short video and no error.

## Why it happens

The numbers add up fast:

- One still every 5 s is 86,400 / 5 = **17,280 stills per camera per day**.
- At 4K that came to **12 to 22 GB per day** on cam-a and cam-c, so roughly 0.7 to 1.3 MB per still.
- Both had 32 GB cards (`df` shows about 29 GB). Once the OS is on the card, that is one or two days of stills.

Why 4K at all? On the IMX219 and OV5647 sensors, 1920x1080 is a centre crop of the sensor and
loses about a third of the field of view. 4K was picked to get the whole view back. The binned
sensor modes also give the whole view, at a fraction of the size:

| Sensor | Full-view mode we use | Note |
|---|---|---|
| IMX219 (Camera Module v2) | 1632x1232 | native 1640 wide; 1632 is 16/32-aligned, costs 0.5% of the view |
| OV5647 (Camera Module v1) | 1280x960 | binned mode, full view |

Nothing deleted the old stills either. The cameras relied on a home-made nightly cleanup script
instead of motionEye's own retention, and that script was not pruning the media folder: one camera
had a typo in the folder name, and on two others the delete line was commented out.

motionEye has its own retention: **Preserve Pictures** and **Preserve Movies**, per camera. They are
stored in `/etc/motioneye/camera-N.conf` as comment-style lines:

```
# @preserve_pictures 7
# @preserve_movies 7
```

Watch the `# @` prefix. `grep '^@preserve'` finds nothing, which makes it look as if everything is
kept forever. motionEye's cleanup runs every 12 hours (`cleanup_interval 43200`) and when the
service starts, so disk use can run up to half a day past the limit.

## Check

```sh
# free space where the media lives
df -h / /var/lib/motioneye

# stills per day folder, and size per day folder
sudo find /var/lib/motioneye -name '*.jpg' -printf '%h\n' | sort | uniq -c
sudo sh -c 'du -sh /var/lib/motioneye/*/*'

# average still size over the last hour
sudo find /var/lib/motioneye -name '*.jpg' -mmin -60 -printf '%s\n' |
  awk '{s+=$1; n++} END {if (n) printf "%d stills, average %.0f KB\n", n, s/n/1024}'

# the settings that drive it (note the "# @" prefix)
sudo grep -E '^snapshot_interval|^picture_output|^# @preserve_(pictures|movies)' /etc/motioneye/camera-*.conf

# damage from an earlier fill
sudo find /var/lib/motioneye -name '*.jpg' -size 0 | wc -l
systemctl --failed
```

### The retention math

```
stills per day    = 86400 / snapshot_interval
GB per day        = stills per day x average still size   (plus movies)
days you can keep = (free space - margin) / GB per day
```

Leave a margin. The cleanup only runs every 12 hours, movies need room too, and the OS needs
space for updates and logs.

Real figures from this fleet:

| Camera | Resolution | Interval | Kept | Result |
|---|---|---|---|---|
| cam-a, cam-c | 4K | 5 s | no working cleanup | 12-22 GB/day, card full in a day or two |
| cam-d | 1280x960 | 5 s | 7 days | about 77,000 stills, about 13 GB of disk in use |

For 4K at 5 s, keeping 7 days would need 84 to 154 GB for stills alone. When cam-d went from
7 days to 3, its file count fell from 77,443 to 44,751 and disk use from 13 GB to 9.0 GB in the
first 12 hours.

## Fix

1. **Drop the resolution** to a full-view binned mode (table above) wherever your stream is produced.
   Do not switch to 1920x1080 to save space; on these sensors it zooms in.
2. **Set Preserve Pictures and Preserve Movies** in each camera's settings in motionEye, using the
   math above. Do not depend on an outside cleanup script. If you keep one, check that it really deletes.
3. **Think twice before raising `snapshot_interval`.** When `picture_output` is off, the periodic
   snapshots are the pictures attached to email and Telegram alerts. motionEye attaches the stills
   within plus or minus `timespan` seconds of the event (10 s on our cameras):

   ```
   pictures per alert = (2 x timespan) / snapshot_interval
   ```

   At 5 s that is 4 pictures. Over 7 days in October 2026, 987 of 992 email alerts from our four
   cameras had exactly 4 pictures, and none had 0 or 1. We once moved a camera to 30 s to cut the
   file count, and its alerts dropped to 1 picture, so we changed it back. Fewer days kept does not
   affect alerts; a longer interval does.
4. **Start the cleanup now** instead of waiting up to 12 hours: `sudo systemctl restart motioneye`.
   On a slow board the first big cleanup takes a while. On cam-d (Pi Zero 2 W) it deleted about
   16 files a second, so about 35 minutes for 35,000 files. Load rose to about 1.9 and swap use from
   90 to 197 MB, but the web UI stayed responsive. A warning at shutdown that the cleanup process
   did not finish in time is harmless on these boards.
5. **Clean up after a fill.** Free the space first, then `sudo systemctl reset-failed` and restart
   anything that failed. Remove or skip the 0-byte JPEGs; they break timelapse tools.

## Verify

- The next day, each camera has no more day folders than the days you keep (plus today).
- `df -h /` stays level from one day to the next.
- The 0-byte JPEG count stays at 0. One new empty file per unclean reboot is a different problem:
  the board crashed or lost power. To find when, see [heartbeat.md](../howto/heartbeat.md).
- After changing the interval, count new stills. Expect 60 / interval per minute (12 at 5 s):

  ```sh
  sudo find /var/lib/motioneye -name '*.jpg' -newermt '-60 sec' | wc -l
  ```

## Limits and open questions

- Retention is set in days, not gigabytes. A busier scene or a higher resolution can still fill the
  disk inside the window. Measure still size over a whole day, and again after any change.
- The per-still sizes here come from a few cameras over a few days. Yours will differ.
- The number of files matters as well as their size. On motionEye 0.44.0 the picture lookup for
  alerts lists all of a camera's media files. On cam-a (Pi 4, about 57,000 files) that took 63 s,
  far past the default 10 s timeout, and the alert was dropped. With the time-window fix (#3414)
  it took 1.5 s on cam-a, but still 10.6 s warm and 24.6 s cold on cam-d (Pi Zero 2 W, about
  77,000 stills). So keep fewer files on small boards. The fixes (#3413, #3414, #3425) are merged
  in upstream `dev` but were not in a release as of early October 2026. Workaround on 0.44.0: set
  `list_media_timeout_email 120` and `list_media_timeout_telegram 120` in
  `/etc/motioneye/motioneye.conf`. Background: https://github.com/motioneye-project/motioneye/issues/3412
