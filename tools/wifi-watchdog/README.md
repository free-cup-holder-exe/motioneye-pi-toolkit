# wifi-watchdog

Recovers a Pi whose Wi-Fi silently stops passing traffic: the interface stays up, nothing is logged, but the gateway no longer answers and the camera drops off the network until someone pulls the plug. See [Wi-Fi drops](../../docs/troubleshooting/wifi-drops.md) for the symptom and the other fixes to try first.

Every minute it pings the default gateway of `wlan0`. Then:

1. after 3 misses in a row, it bounces the interface through NetworkManager (`nmcli device disconnect`, then `connect`);
2. if the gateway is still unreachable 3 runs after the bounce, it reboots the Pi, at most 2 times in any 24 hours (after that it logs once and waits).

A reachable gateway clears its state, so a one-off lost ping does nothing. The timer first runs 5 minutes after boot, so a reboot cannot turn into a reboot loop. Every action is logged with `logger -t wifi-watchdog`; a healthy box logs nothing.

| File | Goes to |
|---|---|
| `wifi-watchdog` | `/usr/local/sbin/wifi-watchdog` (mode 755) |
| `wifi-watchdog.service` | `/etc/systemd/system/` |
| `wifi-watchdog.timer` | `/etc/systemd/system/` |

## Install

In one go, from this folder (it does exactly the steps below, and is safe to run again):

```sh
sudo ./install.sh
```

`./install.sh --dry-run` only prints what it would do. By hand:

```sh
sudo install -m 755 wifi-watchdog /usr/local/sbin/wifi-watchdog
sudo install -m 644 wifi-watchdog.service wifi-watchdog.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wifi-watchdog.timer
```

Another interface or other limits: add `Environment=IF=wlan1 FAIL_MAX=5 REBOOT_MAX=1` to the `[Service]` section of `wifi-watchdog.service`.

## Test it first

A dry run with an interface that does not exist walks through the whole sequence without bouncing or rebooting anything:

```sh
T=$(mktemp -d)
for i in 1 2 3 4 5 6; do DRYRUN=1 IF=wlan9 STATE_DIR=$T NOW=$((1700000000 + i*60)) bash wifi-watchdog; done
rm -r $T
```

Expected: three `unreachable` lines, `bouncing wlan9`, three more `unreachable` lines, then `rebooting`. A real run on a healthy box prints nothing and exits 0: `sudo wifi-watchdog; echo $?`.

## Check it works

```sh
systemctl list-timers wifi-watchdog.timer      # fires every minute
sudo journalctl -t wifi-watchdog               # empty while the link is fine
ls /var/lib/wifi-watchdog                      # empty while the link is fine
```

## Undo

`sudo ./install.sh --uninstall` stops the timer and removes the three files and its state folder.

## Notes

- It bounces the interface, not the radio. On a box with a sticky client problem (see the Wi-Fi doc) the bounce also makes NetworkManager pick the access point again.
- Pair it with [`cam-watchdog`](../cam-watchdog) if the camera also goes dark: the two don't overlap. This one watches the network, that one watches the picture.
- cam-c runs it since 2026-10-16 after a silent wedge that needed a power cycle. cam-a still runs an older cron variant that turns the radio off and on; the two behave the same.
