#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Wi-Fi watchdog: the steps from README.md, in one go.
#   sudo ./install.sh | sudo ./install.sh --uninstall | ./install.sh --dry-run
set -eu
cd "$(dirname "$0")"
. ../../scripts/install-lib.sh

if [ "$MODE" = uninstall ]; then
    if systemctl list-unit-files wifi-watchdog.timer >/dev/null 2>&1; then
        run systemctl disable --now wifi-watchdog.timer
    fi
    remove_files /etc/systemd/system/wifi-watchdog.timer /etc/systemd/system/wifi-watchdog.service /usr/local/sbin/wifi-watchdog
    if [ -d /var/lib/wifi-watchdog ]; then
        run rm -r /var/lib/wifi-watchdog
    fi
    run systemctl daemon-reload
    say "removed"
    exit 0
fi

run install -m 755 wifi-watchdog /usr/local/sbin/wifi-watchdog
run install -m 644 wifi-watchdog.service wifi-watchdog.timer /etc/systemd/system/
run systemctl daemon-reload
run systemctl enable --now wifi-watchdog.timer
if [ -z "$DRY" ]; then
    say "timer: $(systemctl is-enabled wifi-watchdog.timer 2>/dev/null)/$(systemctl is-active wifi-watchdog.timer 2>/dev/null); first run 5 minutes after boot, then every minute"
fi
say "done; it logs only when it acts: journalctl -t wifi-watchdog"
