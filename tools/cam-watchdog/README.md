# cam-watchdog

Recovers a CSI camera whose picture stays dark, for setups that use [`../picam-mjpeg`](../picam-mjpeg).

Every minute it reads the bridge's journal for the current boot. If the last thing the bridge logged is a failure (`camera stalled` or `no first frame`) and no `first frame captured` followed:

1. after 3 minutes dark, it force-kills and restarts `picam-mjpeg`;
2. if the picture is still dark 3 minutes after that, it reboots the Pi, at most 3 times in any 24 hours (after that it logs once and waits).

It does nothing while the bridge is stopped on purpose (`systemctl stop picam-mjpeg`), and the timer first runs 10 minutes after boot, so a reboot cannot turn into a loop. Every action is logged with the tag `cam-watchdog`.

| File | Goes to |
|---|---|
| `cam-watchdog` | `/usr/local/sbin/cam-watchdog` |
| `cam-watchdog.service`, `cam-watchdog.timer` | `/etc/systemd/system/` |

Install in one go, from this folder (it does exactly the steps below, and is safe to run again):

```sh
sudo ./install.sh
```

`./install.sh --dry-run` only prints what it would do. By hand:

```sh
sudo install -m 755 cam-watchdog /usr/local/sbin/cam-watchdog
sudo install -m 644 cam-watchdog.service cam-watchdog.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cam-watchdog.timer
systemctl list-timers cam-watchdog.timer
journalctl -t cam-watchdog          # its actions, if any
```

Dry run against a fake log, without acting (the state goes to a scratch folder):

```sh
now=$(date +%s)
printf '%s\n' "$((now-300)) cam python3[1]: ERROR:root:camera stalled >20s, exiting for systemd restart" > /tmp/events
DRYRUN=1 EVENTS_FILE=/tmp/events STATE_DIR=/tmp/cw-state bash cam-watchdog
# -> dark 300s since ...: killing and restarting picam-mjpeg
```

Settings: `DARK_MAX` (seconds, default 180) and `REBOOT_MAX` (default 3), via `sudo systemctl edit cam-watchdog.service` (`Environment=DARK_MAX=240`).

Undo: `sudo ./install.sh --uninstall`, or by hand: `sudo systemctl disable --now cam-watchdog.timer`.

Why both steps: the bridge normally exits by itself within 20 s of a stall and is back about 10 s later. In one case it logged the stall but the process was held for 24 minutes, most likely inside the camera driver. A kill may not free a process stuck there, so the reboot is the fallback. Background: [docs/troubleshooting/camera-goes-dark.md](../../docs/troubleshooting/camera-goes-dark.md).
