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

- cam-e (Pi Zero W) took a snapshot every 30 s, to cut the number of files on a slow board. Over 7 days it sent 225 alerts: 74 with no picture and 151 with one.
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

cam-e went from 30 s to 10 s on 2026-10-04. Change it in the UI (the camera's Still Images section), or on the command line:

```sh
C=/etc/motioneye/camera-1.conf
sudo cp -p $C $C.bak-$(date +%Y%m%d-%H%M%S)
sudo sed -i 's/^snapshot_interval 30$/snapshot_interval 10/' $C
sudo grep '^snapshot_interval' $C
sudo systemctl restart motioneye
```

A Pi Zero W can take about 30 s to serve the web UI again after the restart.

Result on cam-e in the first 24 hours: 85 alerts, 81 with 2 pictures, 4 with 1, none with 0. Before the change, a third of its alerts had no picture.

Cost:

- Three times as many stills: 8,640 a day instead of 2,880. That means more disk use, and bigger day folders, so a slower picture listing on slow boards.
- cam-e's load stayed about the same (about 0.9).
- cam-e's reboot rate looked higher after the change: about 10.5 a day, against about 8 a day before. But its rate swings between 7 and 13 a day, so this is not proven. A test back at 30 s started on 2026-10-09 and was still running at the time of writing. See [Random reboots](./random-reboots.md).

If the number of files is the problem, keep pictures for fewer days instead of taking fewer pictures. cam-d's picture retention (`@preserve_pictures`) went from 7 days to 3. That does not change the pictures per alert.

### Option B: wider time span

Keep the snapshot interval and widen the window. With 30 s snapshots, ±15 s should avoid alerts with no picture, and ±30 s gives about two. Email and Telegram each have their own time span in the camera's notification settings.

Cost: the pictures are further from the moment of motion, and every alert is sent later. The sender waits one time span before it lists the pictures, so ±30 s means each alert leaves about 30 s after the event. This option was not tested here.

### Not recommended

`picture_output first` or `on`. See the trap above.

## Verify

- After some real events, run the `pics=` summary again, starting from the time of the change (for example `--since "2026-10-04 12:45"`). At a 10 s interval and ±10 s, expect mostly `pics=2`.
- Check with the `find` command above that stills are saved every 10 s.
- Open an alert and check that you can see the movement.

## Limits and open questions

- `pics=` is counted by the wrapper from files on disk in the window. It is not read from the sender, so it does not prove the pictures were attached. If the listing timed out, the alert can have fewer pictures than `pics=` says.
- The count looks in `/var/lib/motioneye/*/<day>` for all cameras on the Pi. With more than one local camera, the counts are mixed. With a different media path it always shows `-`.
- The formula assumes interval snapshots only. Where the event falls between two snapshots can change the count by one (cam-e at 10 s: 81 of 85 alerts had 2, 4 had 1).
- The link between 10 s snapshots and cam-e's reboots is not proven.
- Option B was not tested here.
- The numbers come from cam-e over a few days and from cam-d over one day.
