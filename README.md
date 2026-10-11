# motioneye-pi-toolkit

Tools and field notes for running [motionEye](https://github.com/motioneye-project/motioneye) on Raspberry Pi cameras, mostly with ribbon (CSI) camera modules, from a small home setup of five Pis: three Pi 4s and a Pi Zero 2 W with ribbon cameras, and a Pi Zero W with a USB webcam.

Everything here was built to fix a real problem on those cameras and is still running on them. The notes say what worked, what did not, and what is still unknown.

## Getting started (new to Linux?)

You need a Raspberry Pi running Raspberry Pi OS with motionEye already working, and a computer on the same network.

1. **Connect to the Pi.** On Windows open PowerShell, on a Mac or Linux open a terminal, and type `ssh <user>@<pi-address>`, for example `ssh admin@192.0.2.10`. Everything below runs on the Pi. Commands that start with `sudo` run as the administrator and may ask for your password.

2. **Download the toolkit.** No git needed:

   ```sh
   cd ~
   wget -O motioneye-pi-toolkit.tar.gz https://github.com/free-cup-holder-exe/motioneye-pi-toolkit/archive/refs/heads/main.tar.gz
   tar -xzf motioneye-pi-toolkit.tar.gz
   cd motioneye-pi-toolkit-main
   ```

   The install commands in the tool pages assume you are in this folder.

3. **Install one tool at a time, in this order,** and check each one works before the next:
   1. [Keep logs across reboots](tools/journald): without it, everything from before a crash is lost.
   2. [Heartbeat](tools/cam-heartbeat): one line a minute that proves the Pi was alive.
   3. [Health check](tools/health-check): run it to see where your camera stands. It changes nothing.
   4. [Alert logging](tools/motioneye-notify): if you use email or Telegram alerts.
   5. Only for ribbon (CSI) cameras: the [MJPEG bridge](tools/picam-mjpeg), then the [dark-camera watchdog](tools/cam-watchdog).

   The other two are for specific problems, so read their page first: [Wi-Fi power save](tools/wifi-powersave-off) and [canary builds](tools/canary).

4. **If something goes wrong,** every tool page ends with an **Undo** section. To read the logs: `sudo journalctl -e` shows the latest system log, and `sudo journalctl -u motioneye -e` shows motionEye's.

A few words you will meet: `sudo` runs a command as the administrator, `systemctl` starts, stops and enables services, `journalctl` reads the logs, and `crontab` holds scheduled jobs.

## Tools

| Tool | What it does |
|---|---|
| [`tools/picam-mjpeg`](tools/picam-mjpeg) | Serves a CSI camera as an MJPEG stream (libcamera ISP + hardware JPEG) for motionEye to use as a network camera; exits for a restart when the camera stalls |
| [`tools/cam-watchdog`](tools/cam-watchdog) | If the picture stays dark: restarts the bridge, then reboots (max 3 per day) |
| [`tools/motioneye-notify`](tools/motioneye-notify) | Logs the outcome of every email/Telegram alert (and a redacted reason on failure); a heal script re-adds it after motionEye rewrites the command |
| [`tools/cam-heartbeat`](tools/cam-heartbeat) | One journal line a minute: temperature, throttling, load, free memory |
| [`tools/journald`](tools/journald) | Keeps the journal across reboots on Raspberry Pi OS |
| [`tools/wifi-powersave-off`](tools/wifi-powersave-off) | Turns Wi-Fi power save off at boot |
| [`tools/health-check`](tools/health-check) | Read-only status report for one camera |
| [`tools/canary`](tools/canary) | Installs a motionEye build from the dev branch on one camera, with a backup |

## Docs

Troubleshooting, by symptom:

- [Camera picture freezes or goes dark](docs/troubleshooting/camera-goes-dark.md)
- [Alerts not arriving](docs/troubleshooting/alerts-not-arriving.md)
- [Alerts arrive without pictures](docs/troubleshooting/alerts-missing-pictures.md)
- [Disk filling up](docs/troubleshooting/disk-filling-up.md)
- [Random reboots](docs/troubleshooting/random-reboots.md)
- [Camera unreachable but the Pi is alive (Wi-Fi)](docs/troubleshooting/wifi-drops.md)
- [Adding a camera fails, hangs or accepts a wrong password](docs/troubleshooting/adding-a-camera.md)

How-to:

- [CSI camera through an MJPEG bridge](docs/howto/csi-camera-mjpeg-bridge.md)
- [Log what happens to every alert](docs/howto/log-notification-outcomes.md)
- [Keep logs across reboots](docs/howto/persistent-journal.md)
- [A one-minute heartbeat](docs/howto/heartbeat.md)
- [Safe nightly updates](docs/howto/nightly-updates.md)
- [Test motionEye's dev branch on one camera](docs/howto/canary-testing-dev.md)
- [Health checks](docs/howto/health-checks.md)

Investigations:

- [Software vs hardware H.264 encoding on a Pi Zero 2 W](docs/investigations/pi-zero-2w-software-encoding.md)
- [Python 3.14 and the cleanup that deleted nothing](docs/investigations/python-3.14-forkserver.md)

[Fixes contributed to motionEye from this setup](docs/upstream-fixes.md): all 16 merged into the dev branch for 0.45.0.

## Tested with

Raspberry Pi OS 13 (Trixie), Python 3.13, motion 4.7.x, motionEye 0.44.0 and the 0.45.0 development builds, Picamera2 from the Raspberry Pi OS packages, OV5647 and IMX219 camera modules, and a Logitech C615 USB webcam.

## Before you use anything

- Try it on one camera first. The scripts assume motionEye's defaults: config in `/etc/motioneye`, media in `/var/lib/motioneye`, web UI on port 8765, an admin user with `sudo`.
- Camera names (`cam-a` … `cam-e`), addresses (`192.0.2.x`) and host names (`example.com`) in the docs are placeholders.
- No warranty; see [LICENSE](LICENSE) (MIT).

## Contributing to this repo

Before committing, run `scripts/scrub-check.sh` (or install it as a pre-commit hook with `scripts/install-hooks.sh`). It refuses private IPs, MAC and email addresses, tokens and anything on your own private denylist, which you keep outside the repo (`~/.config/motioneye-pi-toolkit/denylist.txt`).
