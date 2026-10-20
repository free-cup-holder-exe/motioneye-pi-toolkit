#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# Log the outcome of every email and Telegram alert: the steps from README.md, in one go.
#   sudo ./install.sh | sudo ./install.sh --uninstall | ./install.sh --dry-run
set -eu
cd "$(dirname "$0")"
. ../../scripts/install-lib.sh

LINE='17 2 * * * /usr/local/sbin/motioneye-notify-heal'

if [ "$MODE" = uninstall ]; then
    cron_remove /usr/local/sbin/motioneye-notify-heal
    if [ -x /usr/local/sbin/motioneye-notify-heal ]; then
        # put motionEye's own commands back before the wrapper goes away, or alerts stop
        run /usr/local/sbin/motioneye-notify-heal --remove
    fi
    remove_files /usr/local/sbin/motioneye-notify /usr/local/sbin/motioneye-notify-heal
    say "removed; alerts go out as before, without the result lines"
    exit 0
fi

run install -m 755 motioneye-notify motioneye-notify-heal /usr/local/sbin/
run /usr/local/sbin/motioneye-notify-heal
cron_add "$LINE"
if [ -z "$DRY" ]; then
    say "cameras wired: $(grep -l '/usr/local/sbin/motioneye-notify' /etc/motioneye/camera-*.conf 2>/dev/null | wc -l) (0 is fine if no email or Telegram alert is enabled yet)"
fi
say "done; read the results with: journalctl -t moteye-mail -t moteye-tg --since today"
