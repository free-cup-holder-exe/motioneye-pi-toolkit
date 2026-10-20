#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Turn Wi-Fi power save off at boot: the steps from README.md, in one go.
#   sudo ./install.sh | sudo ./install.sh --uninstall | ./install.sh --dry-run
set -eu
cd "$(dirname "$0")"
. ../../scripts/install-lib.sh

if [ "$MODE" = uninstall ]; then
    if systemctl list-unit-files wifi-powersave-off.service >/dev/null 2>&1; then
        run systemctl disable --now wifi-powersave-off
    fi
    remove_files /etc/systemd/system/wifi-powersave-off.service
    run systemctl daemon-reload
    say "removed; power save comes back at the next boot"
    exit 0
fi

run install -m 644 wifi-powersave-off.service /etc/systemd/system/
run systemctl daemon-reload
run systemctl enable --now wifi-powersave-off
if [ -z "$DRY" ]; then
    say "service: $(systemctl is-enabled wifi-powersave-off 2>/dev/null)/$(systemctl is-active wifi-powersave-off 2>/dev/null) (oneshot: 'inactive' after it ran is normal, 'failed' is not)"
    if command -v iw >/dev/null 2>&1; then
        say "wlan0 power save now: $(iw dev wlan0 get power_save 2>/dev/null | cut -d: -f2 | tr -d ' ')"
    fi
fi
say "done"
