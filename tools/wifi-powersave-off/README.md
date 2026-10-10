# wifi-powersave-off

Turns Wi-Fi power save off at every boot. The on-board Broadcom Wi-Fi (`brcmfmac`) on Raspberry Pis has power save on by default; with it on, some cameras here lost their network silently.

```sh
sudo install -m 644 wifi-powersave-off.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wifi-powersave-off
iw dev wlan0 get power_save          # Power save: off
```

It assumes the interface is `wlan0` (check with `iw dev`).

Be realistic about what it does: it helped, but it was not enough on its own for the camera with the weakest signal; moving that one to a different band was. See [docs/troubleshooting/wifi-drops.md](../../docs/troubleshooting/wifi-drops.md).

Undo: `sudo systemctl disable --now wifi-powersave-off` (power save comes back at the next boot).
