# journald: keep logs across reboots

Raspberry Pi OS ships `/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf` with `Storage=volatile`. Drop-in files override `/etc/systemd/journald.conf`, so editing that file is not enough: every reboot still wipes the log, including the minutes before a crash.

This drop-in sorts after the shipped one and wins:

Install in one go, from this folder (it does exactly the steps below, and is safe to run again):

```sh
sudo ./install.sh
```

`./install.sh --dry-run` only prints what it would do. By hand:

```sh
sudo install -d /etc/systemd/journald.conf.d
sudo install -m 644 99-persistent.conf /etc/systemd/journald.conf.d/99-persistent.conf
sudo systemctl restart systemd-journald
journalctl --list-boots | tail -3      # after the next reboot you should see more than one boot
ls /var/log/journal                    # exists once the journal is persistent
```

`SystemMaxUse=200M` caps the space it uses; on a very small or busy card, lower it.

Undo: `sudo ./install.sh --uninstall`, or by hand: `sudo rm /etc/systemd/journald.conf.d/99-persistent.conf && sudo systemctl restart systemd-journald`.

Guide: [docs/howto/persistent-journal.md](../../docs/howto/persistent-journal.md).
