# Keep the journal across reboots

## What it does

Raspberry Pi OS keeps the systemd journal in RAM by default. After a crash, a power cut or a watchdog reset, everything logged before the reboot is gone. That is exactly the part you need.

We lost the evidence of one camera's hard lock-up this way: the journal was in RAM, and the throttle flags reset on reboot, so the cause could never be found. With a persistent journal (and the [heartbeat](heartbeat.md)), later crashes could be read back line by line.

### The trap

Editing `/etc/systemd/journald.conf` does nothing on Raspberry Pi OS. The OS ships this drop-in:

```
/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf   (Storage=volatile)
```

Drop-in files override the main `journald.conf`. So the fix must be a drop-in too, one that sorts after `40-...`:

```
/etc/systemd/journald.conf.d/99-persistent.conf
```

Its content (`tools/journald/99-persistent.conf`):

```ini
[Journal]
Storage=persistent
SystemMaxUse=200M
```

`SystemMaxUse=200M` caps the journal on disk at 200 MB.

## Requirements

- Raspberry Pi OS (Trixie) with systemd-journald.
- About 200 MB free on the SD card.

## Install

On the Pi, two commands install it; the script fetches the toolkit by itself:

```sh
wget https://raw.githubusercontent.com/free-cup-holder-exe/motioneye-pi-toolkit/main/install.sh
sudo bash install.sh journald
```

It is safe to run again, `sudo bash install.sh --uninstall journald` undoes it, and `bash install.sh --dry-run journald` only prints the steps. If you have the toolkit folder already, `sudo ./install.sh journald` from that folder does the same. By hand, what the installer does:

```sh
sudo mkdir -p /etc/systemd/journald.conf.d
sudo install -m 644 -o root -g root tools/journald/99-persistent.conf /etc/systemd/journald.conf.d/99-persistent.conf
sudo systemctl restart systemd-journald
```

## Check it works

Do not stop at reading the config file back. Check where journald actually writes:

```sh
sudo journalctl --header | grep 'File path'
```

The path must start with `/var/log/journal`. If it shows `/run/log/journal`, the journal is still in RAM.

After the next reboot, list the boots:

```sh
sudo journalctl --list-boots
```

You should see more than one boot. Before the change you only ever see the current one.

### Reading an earlier boot

```sh
sudo journalctl -b -1            # the boot before this one
sudo journalctl -b -1 -n 50      # its last 50 lines: how it ended
sudo journalctl -b -2            # two boots back
```

Use the boot index (`-b -1`), not wall-clock times. A Pi has no real-time clock. Right after boot, before the clock is synced, the new boot's timestamps can read earlier than the last lines of the boot before. Also, `-b -1 --since <time>` returns nothing when that boot had not started yet at that time. That is not proof the Pi was down.

### Is 200 MB enough?

It depends on how chatty the box is. Check how far back you can go with `journalctl --list-boots`. If you need more, raise `SystemMaxUse` in the same drop-in file (not in `journald.conf`) and restart journald.

## Undo

```sh
sudo rm /etc/systemd/journald.conf.d/99-persistent.conf
sudo systemctl restart systemd-journald
```

The journal goes back to RAM. The old files stay in `/var/log/journal`. Delete them with `sudo rm -r /var/log/journal` if you want the space back.

## Related

- [Log a heartbeat every minute](heartbeat.md)
- [Wi-Fi drops](../troubleshooting/wifi-drops.md)
