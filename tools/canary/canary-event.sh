#!/bin/bash
# motioneye-pi-toolkit: https://github.com/free-cup-holder-exe/motioneye-pi-toolkit
# SPDX-License-Identifier: MIT
# canary-event.sh: fire a test event on a camera and show whether the alerts went out.
# Waits until motion has captured a fresh snapshot first: an event fired before the first frame
# after a restart never runs the event commands, which looks like a broken build and isn't.
# Needs motioneye-notify (../motioneye-notify) for the result lines; without it only the error
# count at the end means anything.
# On the Pi:   sudo bash canary-event.sh [camera number, default 1]
# Over ssh:    ssh admin@cam 'sudo bash -s -- 1' < canary-event.sh
if [ "$(id -u)" != 0 ]; then echo "run with sudo (it reads the journal and the media folders)"; exit 1; fi
CAM=${1:-1}
P=$(awk '$1=="webcontrol_port" {print $2}' /etc/motioneye/motion.conf)
[ -n "$P" ] || { echo "no webcontrol_port in /etc/motioneye/motion.conf (is this a local camera?)"; exit 1; }
echo "##### $(hostname) $(date '+%F %T') motionEye $(python3 -c 'import motioneye; print(motioneye.VERSION)' 2>/dev/null)"
echo "connection: $(curl -s --max-time 5 "http://127.0.0.1:$P/$CAM/detection/connection" | sed 's/<[^>]*>//g' | tr -s ' \n' ' ' | cut -c1-90)"
echo "detection: $(curl -s --max-time 5 "http://127.0.0.1:$P/$CAM/detection/status" | sed 's/<[^>]*>//g' | tr -s ' \n' ' ' | cut -c1-60)"
for i in $(seq 1 18); do
    n=$(find /var/lib/motioneye -name '*.jpg' -newermt '-30 sec' 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] && break
    sleep 5
done
echo "fresh snapshots in the last 30 s: $n (after ~$((i*5))s)"
[ "$n" -gt 0 ] || echo "WARNING: no fresh snapshot; motion may not be capturing yet, the event may do nothing"
T0=$(date '+%F %T')
curl -s --max-time 5 "http://127.0.0.1:$P/$CAM/action/eventstart" >/dev/null; sleep 12
curl -s --max-time 5 "http://127.0.0.1:$P/$CAM/action/eventend" >/dev/null
echo "event fired at $T0; waiting for the senders"
for i in $(seq 1 18); do
    sleep 10
    n=$(journalctl -t moteye-mail -t moteye-tg --since "$T0" --no-pager -q | wc -l)
    [ "$n" -ge 2 ] && break
done
journalctl -t moteye-mail -t moteye-tg --since "$T0" --no-pager -q -o short-iso | cut -c1-160
echo "sender errors since the event: $(journalctl -u motioneye --since "$T0" --no-pager -q -o cat | grep -iE 'unexpected arguments|traceback|error' | grep -vc 'first image')"
