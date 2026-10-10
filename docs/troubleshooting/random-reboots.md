# Random reboots

cam-e, a Raspberry Pi Zero W (Rev 1.1, one armv6 core, 426 MB RAM), reboots on its own about
8 to 12 times a day and has done so for months. **The root cause is still unknown.** This page
gives the method, the evidence so far, and the theories we got wrong.

cam-e is the odd one out in this fleet. It uses a USB webcam (Logitech C615, UVC, 800x448 at
3 fps, read directly by motion) instead of a CSI ribbon camera. That matters for the open theories.

Commands assume Raspberry Pi OS (Trixie) and an admin account with sudo.

## Symptoms

- `uptime` is short whenever you look. The median time between resets was about 25 minutes in
  July and about an hour in September. The longest run we saw by late September was about 11.5 hours.
- Gaps of a minute or two in stills and alerts. motionEye needs about 30 s to answer after a boot
  on this board.
- About one 0-byte JPEG per crash (motion writes straight to the final file name).
- With the default volatile journal, nothing from before the current boot survives.

## Why it happens

Unknown. What the evidence says so far:

- **No shutdown sequence.** Every boot ends in the middle of normal logging, with no shutdown lines
  from systemd. It is a hard reset or a loss of power, not a software reboot.
- **The board looks healthy right up to the end.** The last heartbeat before each death shows normal
  temperature, no throttle flags, low load and plenty of free memory.
- **It started on day one**, before any of our software changes.

### Ruled out, with the evidence

| Theory | Evidence against it |
|---|---|
| Brownout (a voltage sag the board survives) | During a July storm of 19 resets in one day, all 1,804 heartbeats in the journal read `throttled=0x0`. The under-voltage bit stays set until the next boot, so any sag the board lived through would show. |
| Wi-Fi SDIO hangs tripping the watchdog | Turning Wi-Fi power save off (`tools/wifi-powersave-off/`) changed nothing: 19 resets the day before, 18 on a day after. The `brcmf` errors did not come before the resets; some boots ran for hours after them. cam-e has **zero** SDIO "halting operation" events in its logs. The 664 such events we had counted belonged to cam-b, a different box. We had mixed up the two machines and read too much into a unit's description text. |
| Out of memory | 0 OOM kills. 250-262 MB available (of 426 MB) at every death. Swap (zram, in RAM, not on the SD card) unused. |
| I/O or cron load | Load 0.16-0.77 at death. Media tree only 9,114 files / 4.4 GB. iowait 0-3% in normal running. No hung-task, soft-lockup or RCU-stall messages, ever. |
| SD card wear | A 2020 Samsung card with 111 GB lifetime writes. `Filesystem state: clean`. 0 ext4 errors, 0 mmc errors, 0 I/O errors. |

Not ruled out: **a sudden total power loss**, or a sag that resets the board within the same minute.
`throttled=0x0` cannot rule those out, because the flags are lost with the power. See the open theories below.

## Check

### 1. Make the journal persistent first

Raspberry Pi OS ships `/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf` with
`Storage=volatile`. Drop-ins override `/etc/systemd/journald.conf`, so editing that file does
nothing. Add a later drop-in instead. Full steps: [../howto/persistent-journal.md](../howto/persistent-journal.md).

```sh
journalctl --header | grep 'File path'    # must show /var/log/journal, not /run/log/journal
```

With about 10 boots a day, a 200 MB cap held only about two days of journal on cam-e.

### 2. Count reboots with the ext4 mount count

The mount count goes up by one on every boot, clean or not, and it survives journal rotation.

```sh
sudo tune2fs -l "$(findmnt -n -o SOURCE /)" |
  grep -E '^(Mount count|Last checked|Filesystem state|Lifetime writes)'
```

It counts mounts since the last filesystem check (`Last checked`). Note it down with the date and
time; the difference between two readings is the number of boots. Subtract the reboots you did
yourself. `last` is not installed on Trixie.

### 3. List the boots

```sh
sudo journalctl --list-boots --no-pager | tail -15
sudo journalctl --list-boots --no-pager | awk 'NR>1 {print $4}' | sort | uniq -c   # boots per day
```

Query by boot index (`-b -1`), not by clock time. The Zero W has no real-time clock, so a new boot
can start with a clock earlier than the end of the boot before, until NTP catches up.
`journalctl -b -1 --since <time>` can then return nothing without any error.

### 4. Did the previous boot shut down?

```sh
sudo journalctl -b -1 -n 8 --no-pager -o short-iso
sudo journalctl -b -1 _PID=1 --no-pager -q -o cat | grep -cE 'Reached target.*(Shutdown|Reboot)|Stopping motioneye'
```

`0` means no shutdown sequence. Filter on `_PID=1`: lines like `Reached target shutdown.target`
from `systemd[<other pid>]` are a user session manager exiting (for example at midnight), not the
system shutting down.

Not useful as evidence on these boards: `/sys/class/watchdog/watchdog0/bootstatus` reads 0 on every
box, even after a clean reboot. `vcgencmd get_rsts` reads 20 on cam-e, but on the Pi 4s it gave the
same value after clean and abrupt reboots. ext4 orphan cleanup at boot is no sign either: with the
`orphan_file` feature it showed up after every boot on our Pi 4s.

### 5. Read the heartbeat at the moment of death

`tools/cam-heartbeat/` logs one line a minute: temperature, throttle flags, load and available
memory. Setup: [../howto/heartbeat.md](../howto/heartbeat.md).

```sh
sudo journalctl -t cam-heartbeat -b -1 -n 10 --no-pager -o short-iso
# example line: temp=45.6C throttled=0x0 load=0.31 0.42 0.47 memavail=256MB
```

Look for a trend into the end: rising temperature, a throttle bit, a load spike, falling memory.
SSH sessions push the load up on the Zero W (15-minute load 3.4 while we probed, 1.8 when idle),
so judge load from quiet periods.

### 6. Throttle flags and kernel messages

```sh
sudo vcgencmd get_throttled
sudo journalctl -k -b -1 --no-pager -o short-iso |
  grep -iE 'under-?voltage|oom|killed process|mmc|i/o error|ext4-fs error|soft lockup|hung task|rcu|brcmf|usb .*reset' | tail -20
systemctl show -p RuntimeWatchdogUSec
```

| Bit | Meaning |
|---|---|
| `0x1` / `0x10000` | under-voltage now / has occurred since boot |
| `0x2` / `0x20000` | ARM frequency capped now / has occurred |
| `0x4` / `0x40000` | throttled now / has occurred |
| `0x8` / `0x80000` | soft temperature limit now / has occurred |

For comparison, cam-c has read `0x50000` (under-voltage and throttling since boot) and logged
`hwmon: Undervoltage detected!` during a boot. cam-d read `0x60000` (capped and throttled, no
under-voltage): that is heat, not power.

## Fix

There is no fix yet. What we do in the meantime:

- **Keep the hardware watchdog on** (`RuntimeWatchdogUSec=1min` on cam-e). It turns a hang into a
  reboot. Without it, a hung camera stays dead.
- **Repair the side damage.** Frequent hard resets break things:
  - A reset at 01:02 interrupted the nightly `apt` run. It left `man-db` half-configured (`iF`) and
    `libc-bin` triggers pending, and nightly updates then failed quietly. Find and repair it:

    ```sh
    dpkg -l | awk 'NR>5 && $1!="ii" && $1!="rc"'   # anything listed is unfinished
    sudo dpkg --audit
    sudo dpkg --configure -a                       # took 45 s on cam-e
    ```

    If a package shows an `R` (reinstall required) flag, `dpkg --configure -a` can finish with no
    output and fix nothing. Use `sudo apt-get --fix-broken install` instead. Check the state again
    afterwards. On a board like this, have the nightly update job run `dpkg --configure -a` first.
  - Both NetworkManager YAML files in `/etc/netplan` (`90-NM-*.yaml`) were cut to 0 bytes by a
    reset during a write. The Wi-Fi profile vanished and the camera never joined the network, even
    with the access point at full signal. `nmcli dev wifi list` showed the network, but
    `nmcli -f NAME,AUTOCONNECT,AUTOCONNECT-PRIORITY con show` had no profile for it. A new profile
    from `sudo nmcli dev wifi connect "<SSID>" password "<password>"` (stored as a native
    NetworkManager keyfile) fixed it. When a Pi will not join, check for a profile before you blame
    range or the password.
- **Save the clock often.** Install `fake-hwclock`. On Trixie it is `fake-hwclock-load.service` plus
  `fake-hwclock-save.timer`; the old `fake-hwclock.service` is masked on purpose. We also save it
  every minute from cron, so a crash loses at most a minute.

## Verify

- Read the mount count once a day and work out resets per day. Compare at least three days per setting.
- `sudo dpkg --audit` prints nothing, and the nightly update finishes.
- `nmcli con show` lists the home Wi-Fi profile.

## Limits and open questions

**Root cause: still unknown.** All numbers come from this one board.

Measured rates (mount count and journal):

| Period | Snapshot interval | Resets per day |
|---|---|---|
| 17 Jun to 14 Sep (89 days, mount count 1052) | 5 s until 9 Sep, then 30 s | 11.8 |
| mid-Sep to 4 Oct | 30 s | about 8 |
| 4 Oct to 8 Oct | 10 s | about 10 (daily counts 7 to 13) |
| from 9 Oct, about 3 days | 30 s again (A/B test) | in progress |

The 9 Sep and 4 Oct interval changes were made for other reasons (file count, alert pictures);
the 9 Oct change is the A/B test. A link between snapshot interval and resets is possible but not
proven. The 11.8/day figure is an average over the whole period, so we can't tell when the rate
dropped. The interval change (9 Sep) and a kernel and firmware upgrade (13 Sep) both came just
before the slower period. The mount count also includes a few reboots we did ourselves.

Open theories:

- **Power delivery.** One micro-USB input feeds the board (about 150 mA), Wi-Fi transmit peaks and
  a webcam that asks for 500 mA. Under-voltage has been seen on other boards in this setup, so power
  problems do happen here.
- **A USB or UVC lock-up.** The Zero W handles USB in software on its single core. A total lock-up
  would explain the empty logs, because journald cannot write during one. July kernel logs held 252
  USB lines, including periodic `usb 1-1: reset`.

The watchdog fires within a minute and the heartbeat runs once a minute, so in the journal a
lock-up and a power cut look the same. Tests not yet run: stop motion for about 8 hours (at about
10 resets a day, expect 3 or 4). No resets would point at the USB/camera path; resets would point
at power or the board. A powered USB hub, which takes the webcam's load off the Pi, is the cheap
hardware test.

Before blaming hardware for any single abrupt reboot, ask whether someone power-cycled the box.
