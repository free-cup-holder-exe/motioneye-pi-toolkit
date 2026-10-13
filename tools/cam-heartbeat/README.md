# cam-heartbeat

One journal line per minute with temperature, throttling flags, load and available memory:

```
cam-heartbeat: temp=46.7C throttled=0x0 load=0.52 0.34 0.34 memavail=3166MB
```

Useful when a camera "goes dead": if heartbeats continue, the OS was alive and the problem is the network or the camera; the last heartbeat before a reboot shows the conditions at that moment.

```sh
sudo install -m 755 cam-heartbeat /usr/local/sbin/cam-heartbeat
(sudo crontab -l 2>/dev/null; echo '* * * * * /usr/local/sbin/cam-heartbeat') | sudo crontab -
journalctl -t cam-heartbeat -n 3                                   # after a minute or two
journalctl -t cam-heartbeat --since "15:55" --until "16:10"         # around a problem today
journalctl -t cam-heartbeat -b -1 -n 5                              # the last minutes of the previous boot
```

It needs a persistent journal, otherwise everything before a reboot is lost: see [`../journald`](../journald).

`throttled` is the `vcgencmd get_throttled` bitmask: `0x0` is clean; bit 0 (`0x1`) means under-voltage right now, bit 16 (`0x10000`) means under-voltage happened since boot.

Background: [docs/howto/heartbeat.md](../../docs/howto/heartbeat.md), [docs/troubleshooting/wifi-drops.md](../../docs/troubleshooting/wifi-drops.md).
