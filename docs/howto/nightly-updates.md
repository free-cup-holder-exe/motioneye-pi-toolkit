# Update motionEye and the OS every night, safely

## What it does

A small script, run from root's crontab at night. It:

1. finishes any package setup that an earlier crash left half-done,
2. upgrades the OS packages,
3. stops motionEye, upgrades it from PyPI, and starts it again,
4. waits for the web UI to answer and counts the motion processes,
5. logs one summary line to the journal.

Below is a generic example. Read the notes before you adapt it.

## Requirements

- Raspberry Pi OS (Trixie, Python 3.13) with motionEye installed from PyPI.
- motionEye's web UI on port 8765 (the default).
- Knowing which install flavour you have.

### Two install flavours: never mix them

| Flavour | Where motionEye lives | Upgrade (as root) |
|---|---|---|
| System Python | `/usr/local/lib/python3.13/dist-packages`, `meyectl` in `/usr/local/bin` | `python3 -m pip install --upgrade --break-system-packages motioneye` |
| venv | `/opt/motioneye` | `/opt/motioneye/bin/pip install --upgrade motioneye` |

Check with `systemctl cat motioneye | grep ExecStart`. If it runs `/opt/motioneye/bin/meyectl`, you have the venv. In our setup all four cameras, cam-a to cam-d, use system Python. None uses the venv.

System Python needs `--break-system-packages` because Trixie marks it as externally managed. Never copy an update script from one flavour to the other. The system-Python line on a venv box installs a second, unused copy. The running service never updates, and nothing tells you.

Do not use `--pre` in an unattended job. It pulls pre-releases. Our first scripts had it.

### Do not start motion yourself

motionEye starts its own motion. The distro `motion.service` should stay disabled. One of our old scripts ran `systemctl start motioneye motion`. That brought the disabled daemon back every night, a second motion process competing with motionEye's own. The example checks that exactly one runs.

## Install

Save this as `/usr/local/sbin/nightly-update`. Keep the `PIP`/`PY` pair for your flavour.

```bash
#!/bin/bash
# nightly-update: OS packages, then motionEye from PyPI. Run as root from cron.
log() { logger -t nightly-update "$*"; }
export DEBIAN_FRONTEND=noninteractive

# Pick ONE pair (see "Two install flavours")
PIP="python3 -m pip install --upgrade --break-system-packages"   # system Python
PY=python3
# PIP="/opt/motioneye/bin/pip install --upgrade"                 # venv
# PY=/opt/motioneye/bin/python

# 1. finish anything a crash left half-configured
dpkg --configure -a >/dev/null 2>&1 || log "dpkg --configure -a failed"

# 2. OS packages (keep local config files when a package ships a new one)
if apt-get -q update >/dev/null 2>&1 &&
   apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
     upgrade >/dev/null 2>&1; then
    log "apt upgrade ok"
else
    log "apt upgrade FAILED"
fi

# 3. motionEye: stop, upgrade, start
OLD=$($PY -c 'import motioneye; print(motioneye.VERSION)' 2>/dev/null)
systemctl stop motioneye
$PIP motioneye >/dev/null 2>&1 || log "pip upgrade FAILED"
systemctl start motioneye
NEW=$($PY -c 'import motioneye; print(motioneye.VERSION)' 2>/dev/null)

# 4. wait up to about a minute for the web UI, then count motion processes
CODE=000
for i in $(seq 1 30); do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:8765/)
    [ "$CODE" = 200 ] && break
    sleep 2
done
log "motionEye $OLD -> $NEW web=$CODE motion_procs=$(pgrep -c -x motion)"

# 5. optional: re-wrap alert commands if motionEye rewrote them
[ -x /usr/local/sbin/motioneye-notify-heal ] && /usr/local/sbin/motioneye-notify-heal >/dev/null
```

```sh
sudo chmod 755 /usr/local/sbin/nightly-update
sudo crontab -e      # add:  0 1 * * * /usr/local/sbin/nightly-update
```

Step 5 belongs to [alert logging](log-notification-outcomes.md). Leave it in; it does nothing if that is not installed.

### Notes

- **Stagger and stage.** Do not update every camera in the same minute. One night a single Wi-Fi package update took three of our cameras offline at once, and then they could not download the fixed package. Update one camera first (see [Canary testing](canary-testing-dev.md)), or at least spread the times.
- **Kernels.** `apt-get upgrade` holds back new kernel packages; `full-upgrade` installs them. We do kernel updates by hand, one camera at a time.
- **Clock.** A Pi has no real-time clock. After time offline its clock can be wrong, and apt then rejects the repository files as "not valid yet". Make sure the time is synced before apt runs.
- **By hand over ssh,** run long apt jobs detached (`setsid nohup ...`) so a dropped session does not kill them. An interrupted download is harmless. An interrupted unpack or configure is not.

### Dev and canary builds

A build with a version like `0.45.0a1.dev2026100701` is a pre-release in PEP 440 terms. `pip install --upgrade` without `--pre` leaves it in place. pip only replaces it once a final release newer than it (for example 0.45.0) is on PyPI. That is what lets a canary camera keep its test build through the nightly job.

### If a crash leaves dpkg half-configured

If the Pi crashes or loses power during the nightly apt run, dpkg can be left half-configured. Every later apt run then fails, every night, quietly. Check:

```sh
sudo dpkg --audit
dpkg -l | awk 'NR>5 && $1!="ii" && $1!="rc"'
```

Both should print nothing. To fix:

```sh
sudo dpkg --configure -a
```

Then check again. Do not assume it worked. If packages are still listed (for example with a reinstall-required flag), run `sudo apt-get --fix-broken install`. The example script runs `dpkg --configure -a` first for this reason.

### If logrotate fails every day

If `/var/log/motion` is group-writable (mode 775), logrotate refuses to work and `logrotate.service` fails every day. Nothing gets rotated. Fix:

```sh
stat -c '%a %U:%G' /var/log/motion
sudo chmod 755 /var/log/motion
sudo systemctl reset-failed logrotate.service
sudo systemctl start logrotate.service
systemctl show -p Result --value logrotate.service    # expect: success
```

## Check it works

Run it once by hand, then read the summary:

```sh
sudo /usr/local/sbin/nightly-update
sudo journalctl -t nightly-update --since today --no-pager
```

Expect `web=200 motion_procs=1`. On a slow board motionEye takes longer to come up. On our Pi Zero 2 W (cam-d) it took 15-18 s from start to "server started" in the journal (15 starts over 7 days), against about 4.5-5 s on our Pi 4s. The script polls for about a minute, so a quick probe returning `000` is not a failure.

## Undo

Remove the line with `sudo crontab -e`, then `sudo rm /usr/local/sbin/nightly-update`. Nothing else changes.
