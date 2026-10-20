#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Dark-camera watchdog for the MJPEG bridge: the steps from README.md, in one go.
#   sudo ./install.sh | sudo ./install.sh --uninstall | ./install.sh --dry-run
set -eu
cd "$(dirname "$0")"
. ../../scripts/install-lib.sh

if [ "$MODE" = uninstall ]; then
    if systemctl list-unit-files cam-watchdog.timer >/dev/null 2>&1; then
        run systemctl disable --now cam-watchdog.timer
    fi
    remove_files /etc/systemd/system/cam-watchdog.timer /etc/systemd/system/cam-watchdog.service /usr/local/sbin/cam-watchdog
    run systemctl daemon-reload
    say "removed"
    exit 0
fi

if ! systemctl list-unit-files picam-mjpeg.service 2>/dev/null | grep -q picam-mjpeg; then
    say "note: picam-mjpeg is not installed; this watchdog only watches that bridge (see ../picam-mjpeg)"
fi
run install -m 755 cam-watchdog /usr/local/sbin/cam-watchdog
run install -m 644 cam-watchdog.service cam-watchdog.timer /etc/systemd/system/
run systemctl daemon-reload
run systemctl enable --now cam-watchdog.timer
if [ -z "$DRY" ]; then
    say "timer: $(systemctl is-enabled cam-watchdog.timer 2>/dev/null)/$(systemctl is-active cam-watchdog.timer 2>/dev/null); first run 10 minutes after boot, then every minute"
fi
say "done; it logs only when it acts: journalctl -t cam-watchdog"
