# Alerts arrive with no pictures, or only one

## Symptoms

- Email or Telegram alerts arrive, but with no picture or just one. You cannot see what moved.
- The wrapper from [`tools/motioneye-notify/`](../../tools/motioneye-notify/) logs `result=sent` with `pics=0` or `pics=1`.

## Why it happens

The senders do not take pictures themselves. They attach still pictures that are already on disk and were saved within plus or minus the time span of the event. The default span is 10 s, so the window is 20 s wide. The sender waits one time span before it looks, so pictures saved just after the event can be included.

With the capture mode for interval snapshots (`picture_output off` in `camera-N.conf`), the periodic snapshots are the only still pictures. So:

```
pictures per alert ≈ (2 × time span) ÷ snapshot interval
```

| Snapshot interval | Pictures per alert (±10 s) |
|---|---|
| 5 s | 4 (seen here at about -5, 0, +5 and +10 s from the event) |
| 10 s | about 2 |
| 30 s | 0 or 1 |

Seen here:

- cam-a to cam-d all use interval snapshots (`picture_output off`) every 5 s, with a 10 s time span. Over 7 days (2026-10-06 to 2026-10-13) the wrapper logged 992 email alerts. 987 had exactly 4 pictures, and none had 0 or 1. The Telegram counts were the same within 2 alerts per camera.
- cam-d (Pi Zero 2 W) was once moved from 5 s to 30 s to make the picture listing faster. Its alerts dropped to one picture, and the moving thing was no longer visible. It went back to 5 s the next day. The listing had enough headroom anyway.

### The "one picture per event" trap

The obvious fix is motionEye's capture mode that saves one picture per motion event (`motion-triggered-one`). It does not help:

- That mode writes `picture_output best`. motion saves the "best" picture at the end of the event. That is usually outside the sender's window, so the alert still has no picture.
- `picture_output first` would save a picture inside the window. But motionEye's UI shows any value other than `best` as plain "motion triggered". The next save of the camera settings (from the UI or from Home Assistant) then writes `picture_output on`, which saves every motion frame.
- The senders attach every picture in the window, with no limit. At 3 frames per second and a 10 s event, that is about 30 pictures per alert.

So do not hand-edit `picture_output first` into the config.

### A slow listing can also cost the pictures

On 0.44.0 a slow picture listing loses the whole alert. On motionEye dev ([#3413](https://github.com/motioneye-project/motioneye/pull/3413)) the alert goes out without pictures instead. See [Alerts not arriving](./alerts-not-arriving.md).

## Check

1. Pictures per alert over the last 7 days. `pics=-` means the wrapper could not count.

```sh
for t in moteye-mail moteye-tg; do echo "$t: $(sudo journalctl -t $t --since -7d -q -o cat | grep -oE 'pics=[0-9-]+' | sort | uniq -c | tr '\n' ' ')"; done
```

2. Snapshot interval and capture mode. These lines hold no secrets.

```sh
sudo grep -E '^(snapshot_interval|picture_output) ' /etc/motioneye/camera-1.conf
```

3. The time span. On motionEye dev it is a config key:

```sh
sudo grep -E '^# @(email|telegram)_notifications_picture_time_span ' /etc/motioneye/camera-1.conf
```

   On 0.44.0 it is the last argument of each sender command in `on_event_start`. That line also holds the SMTP password and the Telegram token. Read the time span in the camera's notification settings in the UI instead of printing the line.

4. Are stills saved at the interval you expect?

```sh
sudo find /var/lib/motioneye -name '*.jpg' -newermt '-60 sec' -printf '%TT %f\n' | sort
```

## Fix

### Option A: shorter snapshot interval (used here)

All four cameras here take a snapshot every 5 s. cam-d went back to 5 s after its one day at 30 s. Change it in the UI (the camera's Still Images section), or on the command line:

```sh
C=/etc/motioneye/camera-1.conf
sudo cp -p $C $C.bak-$(date +%Y%m%d-%H%M%S)
sudo sed -i 's/^snapshot_interval 30$/snapshot_interval 5/' $C
sudo grep '^snapshot_interval' $C
sudo systemctl restart motioneye
```

After the restart, motionEye logs `server started` in the journal after about 4.5-5 s on the Pi 4s here (once 7.2 s). On cam-d (Pi Zero 2 W) it took 15-18 s, over 15 starts in 7 days.

Result over 7 days at 5 s (2026-10-06 to 2026-10-13), email alerts, as counted by the wrapper (`pics=`):

| Camera | Alerts | With 4 pictures | Others |
|---|---|---|---|
| cam-a (Pi 4) | 303 | 299 | 2 with 5, 1 with 3, 1 with 2 |
| cam-b (Pi 4) | 81 | 81 | none |
| cam-c (Pi 4) | 45 | 45 | none |
| cam-d (Pi Zero 2 W) | 563 | 562 | 1 with 5 |
| All four | 992 | 987 | 3 with 5, 1 with 3, 1 with 2 |

None had 0 or 1 picture. On its one day at 30 s, cam-d's alerts had one picture.

Cost:

- Six times as many stills as at 30 s: about 17,250 a day per camera here (86,400 ÷ 5 = 17,280), instead of 2,880. That means more disk use, and bigger day folders, so a slower picture listing on slow boards.
- Load at 5 s over 7 days, from the 1-minute load in the [heartbeat](../howto/heartbeat.md) log (one sample a minute): median 0.18-0.34 and 90th percentile 0.60-0.66 on the three Pi 4s, median 0.45 and 90th percentile 0.90 on cam-d (Pi Zero 2 W, 4 cores). Short spikes reached about 9-12 on all four. We have no load numbers at 30 s to compare.

If the number of files is the problem, keep pictures for fewer days instead of taking fewer pictures. cam-d's picture retention (`@preserve_pictures`) went from 7 days to 3. That does not change the pictures per alert.

### Option B: wider time span

Keep the snapshot interval and widen the window. With 30 s snapshots, ±15 s should avoid alerts with no picture, and ±30 s gives about two. Email and Telegram each have their own time span in the camera's notification settings.

Cost: the pictures are further from the moment of motion, and every alert is sent later. The sender waits one time span before it lists the pictures, so ±30 s means each alert leaves about 30 s after the event. This option was not tested here.

### Not recommended

`picture_output first` or `on`. See the trap above.

## Verify

- After some real events, run the `pics=` summary again, starting from the time of the change (for example `--since "2026-10-06 00:00"`). At a 5 s interval and ±10 s, expect mostly `pics=4`.
- Check with the `find` command above that stills are saved every 5 s.
- Open an alert and check that you can see the movement.

## Limits and open questions

- `pics=` is counted by the wrapper from files on disk in the window. It is not read from the sender, so it does not prove the pictures were attached. If the listing timed out, the alert can have fewer pictures than `pics=` says.
- The count looks in `/var/lib/motioneye/*/<day>` for all cameras on the Pi. With more than one local camera, the counts are mixed. With a different media path it always shows `-`.
- The formula assumes interval snapshots only. Where the event falls between two snapshots can change the count by one (at 5 s here: 987 of 992 alerts had 4, 3 had 5, 1 had 3). One cam-a alert had only 2, which the formula does not explain.
- Option B was not tested here.
- The 5 s numbers come from four cameras over 7 days. The 30 s numbers come from cam-d over one day, when its alerts had one picture. The 0 in the 30 s row comes from the formula. The 10 s row in the table comes from the formula, not from a test here.
- The load cost of 5 s against 30 s is not measured. We have load numbers at 5 s only.
