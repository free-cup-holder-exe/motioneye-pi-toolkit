# Log a heartbeat every minute

## What it does

`tools/cam-heartbeat/cam-heartbeat` writes one line to syslog. Run from root's crontab every minute, it gives you a steady pulse in the journal:

```
cam-heartbeat: temp=48.2C throttled=0x0 load=0.80 0.75 0.70 memavail=3300MB
```

| Field | Where it comes from |
|---|---|
| `temp` | SoC temperature, from `vcgencmd measure_temp`. |
| `throttled` | `vcgencmd get_throttled`: under-voltage and throttling flags. |
| `load` | The 1, 5 and 15 minute load averages. |
| `memavail` | Available memory in MB, from `free -m`. |

### Why

- **It proves the OS was alive.** When a camera "goes down", look at the heartbeats of that boot. If they run every minute right up to the moment someone pulled the power, the OS never died. The problem was the network. A gap means a real crash, hang or power loss.
- **It shows the conditions at the moment of a crash.** Climbing temperature points at heat. A throttled flag points at under-voltage. A load spike or memory running out shows up too.

An example from our cameras: one camera "crashed hard" twice. The journal showed 61 heartbeats in its final hour with no gap, and normal temperature, load and memory, right up to the power cycle. Its Wi-Fi link had stopped passing traffic without logging anything. It was never a crash.

## Requirements

- A persistent journal. Without it, the heartbeats of the boot that crashed are gone: [Keep the journal across reboots](persistent-journal.md).
- `vcgencmd` (part of Raspberry Pi OS).
- Root's crontab. `vcgencmd` needs root (`/dev/vcio` is readable by root only).

## Install

On the Pi, two commands install it; the script fetches the toolkit by itself:

```sh
wget https://raw.githubusercontent.com/free-cup-holder-exe/motioneye-pi-toolkit/main/install.sh
sudo bash install.sh cam-heartbeat
```

It is safe to run again, `sudo bash install.sh --uninstall cam-heartbeat` undoes it, and `bash install.sh --dry-run cam-heartbeat` only prints the steps. If you have the toolkit folder already, `sudo ./install.sh cam-heartbeat` from that folder does the same. By hand, what the installer does:

```sh
sudo install -m 755 -o root -g root tools/cam-heartbeat/cam-heartbeat /usr/local/sbin/cam-heartbeat
sudo crontab -e
```

Add this line:

```
* * * * * /usr/local/sbin/cam-heartbeat
```

That is 1440 short lines a day in the journal.

## Check it works

After two minutes:

```sh
sudo journalctl -t cam-heartbeat -n 3 --no-pager
```

If `temp` and `throttled` are empty, the script is not running as root.

### Reading it

The last 30 minutes before the previous boot ended:

```sh
sudo journalctl -t cam-heartbeat -b -1 --no-pager | tail -30
```

Gaps longer than 90 s in the previous boot:

```sh
sudo journalctl -t cam-heartbeat -b -1 -o short-unix --no-pager \
  | awk '{t = int($1)} p && t - p > 90 {print "gap of " (t - p) " s before: " $0} {p = t}'
```

Minutes in the last week when a throttle flag was set:

```sh
sudo journalctl -t cam-heartbeat --since -7d -o cat | grep -v 'throttled=0x0' | head
```

What we have seen in `throttled`:

| Value | Meaning | Likely cause |
|---|---|---|
| `0x0` | Nothing since boot. | |
| `0x50000` | Under-voltage has occurred, and throttling has occurred. | Power supply, cable or connector. |
| `0x60000` | Frequency capped and throttling occurred, no under-voltage. | Heat (we saw it on a Pi Zero 2 W near 80 C). |

These flags stay set until the next reboot, so one under-voltage dip at boot stays visible all day. They are also lost when the power goes. So `throttled=0x0` does not rule out a sudden total power cut: a loose connector, or a supply that cuts out instead of sagging, leaves no trace at all.

Other readings:

- `memavail` around 150-160 MB is normal on a Pi Zero 2 W (424 MB usable) running motionEye.
- On cam-d, a Pi Zero 2 W with 4 cores, the 1-minute load over 7 days had a median of 0.45. Nine minutes in ten it was 0.90 or less. On our Pi 4s the median was 0.18-0.34, and nine minutes in ten it was 0.66 or less. All four had short spikes up to about 9-12.
- Your own ssh session raises the load. Wait about 90 s idle before you trust a load reading.

## Undo

Remove the line with `sudo crontab -e`, then:

```sh
sudo rm /usr/local/sbin/cam-heartbeat
```

## Related

- [Wi-Fi drops](../troubleshooting/wifi-drops.md)
- [Camera picture freezes or goes dark](../troubleshooting/camera-goes-dark.md)
