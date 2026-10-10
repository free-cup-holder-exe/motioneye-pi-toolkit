#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Install a motionEye wheel (e.g. built from the dev branch) on one camera, with a backup first.
# Copy the wheel to /tmp on the Pi, then run this ON the Pi:
#   scp motioneye-0.45.0a1.dev2026100701-py3-none-any.whl admin@cam:/tmp/
#   ssh admin@cam 'sudo bash -s' < canary-deploy.sh
# Rollback: restore package.tgz and etc-motioneye.tgz from the backup folder it prints
# (see docs/howto/canary-testing-dev.md).
if [ "$(id -u)" != 0 ]; then echo "run with sudo"; exit 1; fi
PY=python3
BSP=--break-system-packages
if [ -x /opt/motioneye/bin/python ]; then PY=/opt/motioneye/bin/python; BSP=; fi
TS=$(date +%Y%m%d-%H%M%S)
B=/root/canary-backup-$TS
web() {
    for i in $(seq 1 45); do
        c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:8765/)
        if [ "$c" = 200 ]; then break; fi
        sleep 2
    done
    echo "web=$c after ~$((i * 2))s motioneye=$(systemctl is-active motioneye) motion_procs=$(pgrep -c -x motion)"
}

echo "##### $(hostname) $(date '+%F %T')"
W=$(ls /tmp/motioneye-*.whl 2>/dev/null | head -1)
if [ ! -s "$W" ]; then echo "ABORT: no motioneye-*.whl in /tmp"; exit 1; fi
SP=$($PY -c 'import motioneye, os; print(os.path.dirname(os.path.dirname(motioneye.__file__)))')
echo "before: motionEye $($PY -c 'import motioneye; print(motioneye.VERSION)') in $SP"

DI=$(cd "$SP" && ls -d motioneye-*.dist-info 2>/dev/null | tr '\n' ' ')
mkdir -p "$B"
tar -czf "$B/package.tgz" -C "$SP" motioneye $DI
tar -czf "$B/etc-motioneye.tgz" -C /etc motioneye
if [ ! -s "$B/package.tgz" ] || [ ! -s "$B/etc-motioneye.tgz" ]; then echo "ABORT: backup failed"; exit 1; fi
echo "backup: $B ($(du -sh "$B" | cut -f1)), dist-info: $DI"

echo "wheel: $(basename "$W") sha256=$(sha256sum "$W" | cut -c1-12)"
systemctl stop motioneye
$PY -m pip install --no-deps $BSP "$W" 2>&1 | tail -1
systemctl start motioneye
web
echo "after: motionEye $($PY -c 'import motioneye; print(motioneye.VERSION)')"

if [ -x /usr/local/sbin/motioneye-notify-heal ]; then
    echo "heal: $(/usr/local/sbin/motioneye-notify-heal)"
    web
fi
H=$(curl -s --max-time 5 http://127.0.0.1:8765/)
echo "UI: main.js?v=$(echo "$H" | grep -oE 'main.js\?v=[^"]*' | head -1 | cut -d= -f2) inline <script> tags=$(echo "$H" | grep -c '<script>')"
echo "warnings since the restart:"
journalctl -u motioneye --since "-3min" --no-pager -q -o cat | grep -iE 'error|warning|could not' | tail -5 | cut -c1-200
rm -f "$W"
