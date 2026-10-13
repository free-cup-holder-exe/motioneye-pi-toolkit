# Camera picture freezes or goes dark

This page is for CSI (ribbon) cameras that motion reads through the libcamera-to-MJPEG bridge in [`tools/picam-mjpeg/`](../../tools/picam-mjpeg/). In this setup that means all four cameras, cam-a to cam-d. For how the bridge works, see [CSI camera MJPEG bridge](../howto/csi-camera-mjpeg-bridge.md).

## Symptoms

- The live view stops changing, or shows no picture.
- No motion events and no alerts while it lasts.
- Snapshots may still be saved. motion burns the time into each picture, so every file is different even when the scene is frozen. New files on disk do not prove that the sensor is alive.
- The bridge's journal (`journalctl -u picam-mjpeg`) shows one of these lines:
  - `camera stalled >20s, exiting for systemd restart`
  - `no first frame within 30s, exiting for systemd restart`
  - `Camera frontend has timed out` (from libcamera)

## Why it happens

Sometimes libcamera stops delivering frames. The bridge is a small Python HTTP server. When frames stop, the process stays alive and keeps serving the last frame. systemd only restarts a service that exits, so nothing happens.

Two cases from this setup, from before the bridge had its checks:

- cam-d (Pi Zero 2 W, OV5647): libcamera logged `Camera frontend has timed out`. The bridge served one frozen frame for about 20 hours until someone noticed.
- cam-b (Pi 4, OV5647): after a sensor I2C error the bridge restarted. Then it waited for its first frame with no time limit. It hung for about 20 hours.

The bridge now handles both cases. It exits with `os._exit(1)` so that systemd restarts it:

- A thread checks every 10 s. If no new frame has arrived for 20 s, it logs `camera stalled` and exits. So a stall is noticed 20-30 s after the last frame.
- At start, if no first frame arrives within 30 s, it logs `no first frame` and exits.
- The unit has `Restart=on-failure` and `RestartSec=3`. Here the first frame usually arrived 3-7 s after a restart.

Most stalls recover this way in under a minute. A few do not. On 2026-10-07, cam-d logged `camera stalled`, but the process took about 24.5 minutes to actually exit. The bridge already uses `os._exit`, which skips all Python cleanup. So the process was most likely stuck in the camera driver, inside the kernel. A process stuck there may not react to SIGKILL either. Before that, cam-d had a few exits that hung for 8 to 46 minutes while the process used a full CPU core.

### How often

These counts are from cam-d only, late September to early October 2026.

- About 2 stalls a day on normal days. On one busy day with 287 movies it had 10.
- The stalls seemed to cluster when motion started or finished a movie with the hardware H.264 encoder (`h264_v4l2m2m`). As a test, cam-d was switched to the software encoder on 2026-10-04. Over the next four and a half days it had 9 stalls (still about 2 a day) and two long dark gaps (267 s and 1,478 s). So switching the encoder did not change the stall rate. Those days were quiet, so there is no busy-day comparison. Details: [Pi Zero 2 W software encoding](../investigations/pi-zero-2w-software-encoding.md).

## Check

These checks read the journal. To look back past a reboot you need a persistent journal: see [Keep the journal across reboots](../howto/persistent-journal.md).

1. Bridge state and recent stall lines:

```sh
systemctl status picam-mjpeg --no-pager
sudo journalctl -u picam-mjpeg --since -1d --no-pager | grep -E 'stalled|no first frame|first frame captured|frontend has timed out'
```

2. Stalls per day, last 7 days:

```sh
for d in 6 5 4 3 2 1 0; do
  day=$(date -d "-$d day" +%F)
  log=$(sudo journalctl -u picam-mjpeg --since "$day 00:00" --until "$day 23:59:59" --no-pager -q -o cat)
  echo "$day stalled=$(grep -c 'camera stalled' <<<"$log") no-first-frame=$(grep -c 'no first frame' <<<"$log")"
done
```

3. Dark gaps. A gap runs from a `camera stalled` line to the next `first frame captured` line. This lists gaps over 60 s (change `60` to `0` to see all of them). No output means no long gaps. The real dark time is 20-30 s longer, because the stall line is written that long after the last frame.

```sh
sudo journalctl -u picam-mjpeg --since -7d --no-pager -q -o short-unix \
  | awk '/camera stalled/ {s=$1} /first frame captured/ && s {g=$1-s; if (g>60) printf "%s dark %ds\n", strftime("%F %T", s), g; s=0}'
```

4. Is motion getting frames from the bridge?

```sh
P=$(sudo awk '$1=="webcontrol_port" {print $2}' /etc/motioneye/motion.conf)
curl -s "http://127.0.0.1:$P/1/detection/connection"    # look for "Connection OK"
sudo find /var/lib/motioneye -name '*.jpg' -newermt '-90 seconds' | wc -l
```

5. What the watchdog did, if you installed it (see Fix):

```sh
sudo journalctl -t cam-watchdog --since -7d --no-pager
```

6. Heat and power flags. `0x0` means no throttling and no under-voltage since boot.

```sh
sudo vcgencmd get_throttled; vcgencmd measure_temp
```

## Fix

1. Run the current bridge from [`tools/picam-mjpeg/`](../../tools/picam-mjpeg/). It has the stall check and the first-frame timeout. Make sure systemd restarts it:

```sh
systemctl cat picam-mjpeg | grep -E '^Restart'    # expect Restart=on-failure and RestartSec=3
```

2. Add [`tools/cam-watchdog/`](../../tools/cam-watchdog/) for the exits that hang. It runs every minute from a systemd timer, starting 10 minutes after boot. It reads the bridge's journal for the current boot. "Dark" means a `camera stalled` or `no first frame` line with no `first frame captured` line after it. Then:
   - After 180 s dark: kill the bridge with SIGKILL, wait 5 s, start it again.
   - Still dark 180 s after that: reboot the Pi.
   - At most 3 reboots in any rolling 24 hours. After that it logs `limit reached` once and does nothing more.
   - A bridge you stopped on purpose (`systemctl stop picam-mjpeg`) is left alone.
   - State is kept in `/var/lib/cam-watchdog`. It logs with the tag `cam-watchdog`.

   Copy the repo's `tools` folder to the Pi, then run the commands below. The dry run reads the real journal but changes nothing. No output means the picture is fine right now.

```sh
sudo install -m 755 -o root -g root tools/cam-watchdog/cam-watchdog /usr/local/sbin/cam-watchdog
sudo install -m 644 -o root -g root tools/cam-watchdog/cam-watchdog.service tools/cam-watchdog/cam-watchdog.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo env DRYRUN=1 STATE_DIR=/tmp/cw-test /usr/local/sbin/cam-watchdog; sudo rm -rf /tmp/cw-test
sudo systemctl enable --now cam-watchdog.timer
```

   To change the limits, run `sudo systemctl edit cam-watchdog.service` and add `[Service]` with `Environment=DARK_MAX=300 REBOOT_MAX=2` (seconds dark, reboots per 24 h). To turn it off: `sudo systemctl disable --now cam-watchdog.timer`.

   With the defaults, the worst case is about 6-7 minutes dark plus the reboot, instead of the 24.5 minutes above. That is worked out from the timings, not measured.

3. Go easy on a Pi Zero 2 W while you debug. On cam-d, one stall came during a burst of more than 20 SSH sessions, and may have been caused by them.

## Verify

- After a stall, `first frame captured` should follow the stall line within seconds. The timer should show a next run:

```sh
sudo journalctl -u picam-mjpeg -n 20 --no-pager
systemctl list-timers cam-watchdog.timer --no-pager
```

- Run the dark-gap command again after a few days. With the watchdog, gaps should stay under about 7 minutes. A gap that ends in a reboot spans two boots.
- One `motion_init: Error capturing first image` per motion start is normal here. motion starts before the bridge has a frame, and recovers on its own.
- If the Pi reboots and you do not know why, check `sudo journalctl -t cam-watchdog` first. See also [Log a heartbeat every minute](../howto/heartbeat.md).

## Limits and open questions

- Why libcamera stalls here is not known. The encoder test suggests the hardware H.264 encoder is not the cause on its own. During the July stall, cam-d's throttle flags showed past thermal throttling. Later checks showed no throttling (`0x0`, about 56 °C). Heat is neither ruled in nor ruled out.
- The 24.5-minute exit is only "most likely" stuck in the camera driver. That was not confirmed. If SIGKILL does not work in that state, only the reboot step helps.
- cam-watchdog was added after that case and runs on cam-d. At the time of writing it has little field time, so there is no data yet on how often it acts.
- cam-watchdog only knows what the bridge logs. If the bridge froze so badly that its own check could not log, cam-watchdog would not act.
- After 3 reboots in 24 hours it gives up. The camera then stays dark until someone looks.
- It does nothing in the first 10 minutes after boot. During that time the bridge's first-frame timeout and systemd's restarts are the only recovery.
- All stall numbers come from one camera (cam-d) over a few weeks.
