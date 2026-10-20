#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Keep the journal across reboots: the steps from README.md, in one go.
#   sudo ./install.sh | sudo ./install.sh --uninstall | ./install.sh --dry-run
set -eu
cd "$(dirname "$0")"
. ../../scripts/install-lib.sh

if [ "$MODE" = uninstall ]; then
    remove_files /etc/systemd/journald.conf.d/99-persistent.conf
    run systemctl restart systemd-journald
    say "removed; the journal is volatile again after the next reboot"
    exit 0
fi

run install -d /etc/systemd/journald.conf.d
run install -m 644 99-persistent.conf /etc/systemd/journald.conf.d/99-persistent.conf
run systemctl restart systemd-journald
if [ -z "$DRY" ]; then
    say "boots kept so far: $(journalctl --list-boots 2>/dev/null | wc -l) (grows with every reboot from now on)"
fi
say "done"
