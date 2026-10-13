# Daily health check over ssh

## What it does

`tools/health-check/health-check.sh` is a read-only check. You pipe it to a camera over ssh, and it prints a short block of lines about that camera since a time you choose. It changes nothing, installs nothing and prints no secrets.

It reports the motionEye version, web status, service state, motion process count, disk use, free memory, whether the page sends a Content-Security-Policy header, boots since the start time, motionEye warnings, alert results per channel, alert errors, bridge stalls, watchdog actions, new media and kernel warnings.

## Requirements

- ssh to the camera as an admin user with sudo.
- sudo that does not ask for a password in a non-interactive ssh command. If yours asks, copy the script to the Pi and run it in an ssh session: `sudo bash health-check.sh "2026-10-07 21:00"`. Run without sudo, the script refuses to start.
- A [persistent journal](persistent-journal.md). Without it, the boot count and older results are lost at each reboot.
- Optional: [alert logging](log-notification-outcomes.md), the [MJPEG bridge](csi-camera-mjpeg-bridge.md), [cam-watchdog](../../tools/cam-watchdog/) and the [heartbeat](heartbeat.md). Lines for parts you do not have read 0 or empty.

## Install

Nothing to install. Run it from your PC, giving the start of the period you want to check (without a time it covers the last 24 hours):

```sh
ssh admin@cam-a 'sudo bash -s -- "2026-10-07 21:00"' < tools/health-check/health-check.sh
```

All cameras in one go:

```sh
for h in cam-a cam-b cam-c cam-d; do
  ssh admin@$h 'sudo bash -s -- "2026-10-07 21:00"' < tools/health-check/health-check.sh
done
```

A good start time is just after your last change (a deploy, a config edit). Then you see only what happened since.

## Check it works

Each camera prints a header line with its host name, the time and its uptime, followed by the lines below. If you get no header, ssh or sudo failed.

## Reading the output

**Header:** host, time, uptime, load, temperature and `throttled`.
- `throttled=0x0` is good. `0x50000` means under-voltage happened since boot (power supply, cable or connector). `0x60000` means it throttled for heat. The flags stay set until reboot. See [heartbeat](heartbeat.md).
- Over 7 days of heartbeats, the 1-minute load had a median of 0.18-0.34 on our Pi 4s and 0.45 on cam-d, a Pi Zero 2 W with 4 cores. Short spikes up to about 9-12 happened on all four. Your own ssh commands raise the load.

**motionEye line:** version, `web=`, `active=`, `since=`, `motion_procs=`, `disk=`, `mem_avail=`.
- `web=200` and `active=active`. `web=000` right after a boot means it is still starting. Over 7 days, motionEye took about 4.5-5 s from start to `server started` in the journal on our Pi 4s (once 7.2 s), and 15-18 s on cam-d, a Pi Zero 2 W. Run the check again before you worry.
- `motion_procs=1`. 0 means motion is not running. 2 means a second motion daemon, usually the distro `motion.service` started by something (see [Nightly updates](nightly-updates.md)).
- `since=` shows when motionEye last started. The nightly update restarts it.
- `disk=` should stay level from day to day once media retention is in effect.
- `mem_avail=` around 150-160 MB is normal on a Pi Zero 2 W.

**csp header:** `1` if the web page sends a Content-Security-Policy header. Builds of dev with #3435 do. 0.44.0 and older do not, so `0` is normal there.

**boots since / motion starts:**
- `boots` should be 0 unless you rebooted. Anything else is a reboot or a power loss. Check the heartbeats: see [heartbeat](heartbeat.md).
- `motion starts` counts motion start-up lines. Expect a few, because the nightly update and any heal or config save restart motionEye. A count that climbs through the day means motion keeps dying.

**motionEye errors/warnings:** grouped and counted, with numbers replaced by `N`.
- Normal: `motion_init: Error capturing first image`, once per motion start with the bridge.
- Harmless: "cleanup process did not finish in time" when motionEye stops on a slow board. `unknown configuration option: <name>` is an old line in `motioneye.conf` that this version no longer knows; remove the line to silence it.
- The redacted `error=` lines from alert logging show up here too, because the senders run inside motionEye's service.
- Anything with `Traceback`, or a message you have not seen before: look closer with `sudo journalctl -u motioneye --since "<start>"`.

**alerts:** `mail[...] tg[...]`, the counts of each `result=` and `pics=` value per channel.
- Every result should be `sent`. With snapshots every 5 s and a 10 s time span, `pics=4` is normal.
- Empty brackets are normal if nothing moved, or if alert logging is not installed.
- Any `send-failed`, `listing-timeout` or low `pics`: see [Alerts not arriving](../troubleshooting/alerts-not-arriving.md).

**alert errors:** how many redacted `error=` lines the failures left. Read them with `sudo journalctl -t moteye-mail -t moteye-tg --since "<start>" | grep error=`. For example, `Temporary failure in name resolution` means the camera could not look up the mail server's name.

**bridge:** `stalls=`, `no_first_frame=`, `active=`, and `watchdog actions:`.
- 0, 0 and `active` is ideal. On a Pi Zero 2 W we saw about 2 stalls a day. Most recovered by the automatic restart within a minute. For long dark spells, see [Camera picture freezes or goes dark](../troubleshooting/camera-goes-dark.md).
- A camera without the bridge shows 0, 0 and `inactive`.
- `watchdog actions` counts lines logged by cam-watchdog. Above 0 means it restarted the bridge or rebooted the Pi: read them with `sudo journalctl -t cam-watchdog`.

**media since:** new movies and pictures.
- Pictures depend on your snapshot interval: one every 5 s is about 720 an hour per camera. Zero pictures means nothing is being recorded.
- Movies depend on how much moved.

**kernel warnings:** a count of kernel lines that look like trouble (under-voltage, the Wi-Fi driver `brcmf`, "error", "fail").
- A few are normal: one `bcm2835-codec ... Failed setting ctrl 00990a67` when the camera encoder starts, and the odd `brcmf` scan error.
- If the count jumps, read the lines: `sudo journalctl -k --since "<start>" | grep -iE 'under-?voltage|brcmf|error|fail'`. Any under-voltage line points at the power supply, cable or connector.

## Undo

Nothing to undo. The script runs from standard input and leaves no files on the Pi.
