# picam-mjpeg

A small MJPEG HTTP server for a Raspberry Pi CSI (ribbon) camera, so motionEye can use it as a network camera at `http://127.0.0.1:8080/stream.mjpg`.

| File | Goes to |
|---|---|
| `picam_mjpeg.py` | `/usr/local/bin/picam_mjpeg.py` |
| `picam-mjpeg.service` | `/etc/systemd/system/picam-mjpeg.service` |

```sh
sudo apt install python3-picamera2
sudo install -m 755 picam_mjpeg.py /usr/local/bin/picam_mjpeg.py
sudo install -m 644 picam-mjpeg.service /etc/systemd/system/picam-mjpeg.service
sudo systemctl daemon-reload
sudo systemctl enable --now picam-mjpeg
curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://127.0.0.1:8080/stream.mjpg   # 200, then Ctrl-C if it keeps streaming
```

Settings: `PICAM_WIDTH`, `PICAM_HEIGHT`, `PICAM_FPS`, `PICAM_BIND`, `PICAM_PORT` (see the top of the script). Set them with `sudo systemctl edit picam-mjpeg`.

The script exits, and systemd restarts it 3 s later, when no first frame arrives within 30 s or frames stop for more than 20 s. Pair it with [`../cam-watchdog`](../cam-watchdog) for the rare case where that is not enough.

The cameras in this setup run the same script with the frame size written into it; this copy reads it from the environment instead.

Full guide: [docs/howto/csi-camera-mjpeg-bridge.md](../../docs/howto/csi-camera-mjpeg-bridge.md).
