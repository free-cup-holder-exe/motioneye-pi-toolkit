#!/bin/bash
# Read-only health check for a motionEye camera Pi. Changes nothing, prints no secrets.
# On the Pi:   sudo bash health-check.sh ['YYYY-MM-DD HH:MM']        (default: the last 24 h)
# Over ssh:    ssh admin@cam 'sudo bash -s -- "2026-10-07 21:00"' < health-check.sh
if [ "$(id -u)" != 0 ]; then echo "run with sudo (it reads the journal and the media folders)"; exit 1; fi
SINCE="${1:-$(date -d '-24 hours' '+%F %T')}"
PY=python3
if [ -x /opt/motioneye/bin/python ]; then PY=/opt/motioneye/bin/python; fi
J() { journalctl --since "$SINCE" --no-pager -q -o cat "$@"; }

echo "##### $(hostname) $(date '+%F %T') $(uptime -p) load=$(cut -d' ' -f1-3 /proc/loadavg) $(vcgencmd measure_temp 2>/dev/null) throttled=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)"
echo "motionEye $($PY -c 'import motioneye; print(motioneye.VERSION)' 2>&1 | tail -1) web=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8765/) active=$(systemctl is-active motioneye) since=$(systemctl show motioneye -p ActiveEnterTimestamp --value | cut -c5-20) motion_procs=$(pgrep -c -x motion) disk=$(df -h / | awk 'NR==2{print $5}') mem_avail=$(free -m | awk '/Mem:/{print $7}')MB"
echo "csp header: $(curl -s -D - -o /dev/null --max-time 5 http://127.0.0.1:8765/ | tr -d '\r' | grep -ic '^content-security-policy')"
echo "boots since $SINCE: $(journalctl --list-boots --no-pager 2>/dev/null | awk -v s="$SINCE" 'NR>1 && $4" "$5 >= s' | wc -l) | motion starts: $(J -u motioneye | grep -c 'motion_init: Error capturing first image')"
echo "motionEye errors/warnings (digits folded):"
J -u motioneye | grep -iE 'error|warning|traceback|exception' | sed -E 's/[0-9]{2}:[0-9]{2}:[0-9]{2}//; s/[0-9]+/N/g' | sort | uniq -c | sort -rn | head -6 | cut -c1-190
echo "alerts: mail[$(J -t moteye-mail | grep -oE 'result=[a-z-]+|pics=[0-9]+' | sort | uniq -c | tr '\n' ' ')] tg[$(J -t moteye-tg | grep -oE 'result=[a-z-]+|pics=[0-9]+' | sort | uniq -c | tr '\n' ' ')]"
echo "alert errors: $(J -t moteye-mail -t moteye-tg | grep -c 'error=')"
echo "bridge: stalls=$(J -u picam-mjpeg 2>/dev/null | grep -c 'camera stalled') no_first_frame=$(J -u picam-mjpeg 2>/dev/null | grep -c 'no first frame') active=$(systemctl is-active picam-mjpeg 2>/dev/null) | watchdog actions: $(J -t cam-watchdog | wc -l)"
echo "media since $SINCE: movies=$(find /var/lib/motioneye -name '*.mp4' -newermt "$SINCE" 2>/dev/null | wc -l) pictures=$(find /var/lib/motioneye -name '*.jpg' -newermt "$SINCE" 2>/dev/null | wc -l)"
echo "kernel warnings since $SINCE: $(journalctl -k --since "$SINCE" --no-pager -q -o cat | grep -ciE 'under-voltage|brcmf|error|fail')"
