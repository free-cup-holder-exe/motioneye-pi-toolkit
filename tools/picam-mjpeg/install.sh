#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# MJPEG bridge for a CSI (ribbon) camera: the steps from README.md, in one go.
#   sudo ./install.sh | sudo ./install.sh --uninstall | ./install.sh --dry-run
set -eu
cd "$(dirname "$0")"
. ../../scripts/install-lib.sh

if [ "$MODE" = uninstall ]; then
    if systemctl list-unit-files picam-mjpeg.service >/dev/null 2>&1; then
        run systemctl disable --now picam-mjpeg
    fi
    remove_files /etc/systemd/system/picam-mjpeg.service /usr/local/bin/picam_mjpeg.py
    run systemctl daemon-reload
    say "removed (the python3-picamera2 package stays; apt remove it yourself if you want)"
    say "remove the camera that used http://127.0.0.1:8080/stream.mjpg in motionEye too"
    exit 0
fi

if dpkg -s python3-picamera2 >/dev/null 2>&1; then
    say "python3-picamera2 is installed"
else
    run apt-get install -y python3-picamera2
fi
run install -m 755 picam_mjpeg.py /usr/local/bin/picam_mjpeg.py
run install -m 644 picam-mjpeg.service /etc/systemd/system/picam-mjpeg.service
run systemctl daemon-reload
run systemctl enable --now picam-mjpeg
if [ -z "$DRY" ]; then
    sleep 5
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8080/stream.mjpg || true)
    if [ "$code" = 200 ]; then
        say "stream answers 200 at http://127.0.0.1:8080/stream.mjpg"
    else
        say "no stream yet (got '$code'); give it a minute, then: journalctl -u picam-mjpeg -e"
    fi
fi
say "done; now add the camera in motionEye as a network camera: http://127.0.0.1:8080/stream.mjpg"
