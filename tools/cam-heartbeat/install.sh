#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# One journal line a minute with temperature, throttling, load and free memory.
#   sudo ./install.sh | sudo ./install.sh --uninstall | ./install.sh --dry-run
set -eu
cd "$(dirname "$0")"
. ../../scripts/install-lib.sh

LINE='* * * * * /usr/local/sbin/cam-heartbeat'

if [ "$MODE" = uninstall ]; then
    cron_remove /usr/local/sbin/cam-heartbeat
    remove_files /usr/local/sbin/cam-heartbeat
    say "removed; old heartbeat lines stay in the journal"
    exit 0
fi

run install -m 755 cam-heartbeat /usr/local/sbin/cam-heartbeat
cron_add "$LINE"
if [ -z "$DRY" ]; then
    /usr/local/sbin/cam-heartbeat
    say "first line: $(journalctl -t cam-heartbeat -n 1 --no-pager -q -o cat 2>/dev/null)"
fi
say "done; read them with: journalctl -t cam-heartbeat"
