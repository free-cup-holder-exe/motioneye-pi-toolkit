# health-check

A read-only status report for one camera Pi: versions, web UI, services, disk and memory, reboots, motionEye warnings, alert results, bridge stalls, watchdog actions, media counts and kernel warnings since a given time. It changes nothing.

```sh
sudo bash health-check.sh                         # last 24 hours
sudo bash health-check.sh '2026-10-07 21:00'      # since a time
# from a PC, for every camera:
for cam in cam-a cam-b cam-c; do ssh admin@$cam 'sudo bash -s -- "2026-10-07 21:00"' < health-check.sh; done
```

Example (one camera, healthy):

```
##### cam-a 2026-10-08 23:51:03 up 1 week, 2 days load=0.12 0.22 0.29 temp=46.2'C throttled=0x0
motionEye 0.45.0a1 web=200 active=active since=2026-10-08 01:05 motion_procs=1 disk=57% mem_avail=3256MB
csp header: 1
boots since 2026-10-07 21:26: 0 | motion starts: 3
motionEye errors/warnings (digits folded):
      3 [N:mlN:cam-a] [ERR] [ALL] motion_init: Error capturing first image
alerts: mail[     46 pics=4      46 result=sent ] tg[     46 pics=4      46 result=sent ]
alert errors: 0
bridge: stalls=0 no_first_frame=0 active=active | watchdog actions: 0
media since 2026-10-07 21:26: movies=46 pictures=19003
kernel warnings since 2026-10-07 21:26: 2
```

What is normal:

- `motion_init: Error capturing first image` once per motion start, when motion reads the MJPEG bridge: the stream is not up yet at that instant.
- `motion starts` of 1 per day from a nightly update that restarts motionEye.
- `csp header: 1` only on motionEye builds that send a Content-Security-Policy (dev / 0.45.0 and later); `0` on 0.44.x.
- A few `brcmf ... scan error (-52)` kernel lines: harmless background Wi-Fi scan errors.

What to look at: any `boots` you did not expect, `web` other than 200, `motion_procs` other than 1, `send-failed` alerts (then `journalctl -t moteye-mail -t moteye-tg | grep error=`), stalls, and watchdog actions.

The alert lines need [`../motioneye-notify`](../motioneye-notify); the bridge and watchdog lines need [`../picam-mjpeg`](../picam-mjpeg) and [`../cam-watchdog`](../cam-watchdog). Missing pieces just show 0.

Guide: [docs/howto/health-checks.md](../../docs/howto/health-checks.md).
