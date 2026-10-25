# Feed a CSI camera to motionEye through an MJPEG bridge

## What it does

`tools/picam-mjpeg/picam_mjpeg.py` is a small Python server. It opens the ribbon (CSI) camera with Picamera2, encodes each frame to JPEG and serves the frames as an MJPEG stream at `http://127.0.0.1:8080/stream.mjpg`. motionEye adds that stream as a network camera. motion then reads it and does motion detection as usual.

`tools/picam-mjpeg/picam-mjpeg.service` runs the server under systemd.

### Do you need a bridge at all? Try the shim first

On current Raspberry Pi OS the CSI camera is driven by libcamera, and motion 4.7 can read it through the
`libcamerify` shim: start motion (or the whole of motionEye) under `libcamerify`, point the camera at
`/dev/video0`, and libcamera hands motion a processed YUV picture through the Pi's image signal processor.
Measured on a Pi 4 (Trixie, kernel 6.18, motion 4.7.1, IMX219, 2 fps): motion under the shim uses 5-8 % of
one core, libcamera's work included. The bridge path on the same box uses about 17-20 % (the bridge 5-7 %
plus motion 11-15 % decoding the MJPEG), so for one local motionEye the shim is simpler and cheaper.

Two rules for the shim path:

- **Use a width that is a multiple of 32** (1600x1200, 1280x960, 640x480). With 1640x1232 motion pads the
  rows to the 1664-byte stride and shows the padding as a green stripe down the right edge. We lived with
  that stripe for months before finding the cause.
- **Wrap the whole motionEye service**, not just motion, so the camera detection sees the shim too:
  `ExecStart=/usr/bin/libcamerify /usr/local/bin/meyectl startserver -c /etc/motioneye/motioneye.conf`
  in the unit (`sudo systemctl edit --full motioneye`). Our cameras have run that way since July.

Pointing motion at `/dev/video0` *without* the shim is what does not work: that path skips the image
processor and gives raw Bayer data, which motion only partly supports (a plaid texture, no white balance).

### When the bridge still earns its place

- The camera stays open while motion restarts; through the shim every motion restart reopens it.
- More than one reader: a browser, another machine or a recorder can read the stream while motion does.
- The JPEG is made by the Pi's hardware encoder, which matters on a Pi Zero 2 W.

### Why not rpicam-vid | ffmpeg | v4l2loopback?

That chain works, but ffmpeg converts the pixels in software. On a Pi Zero 2 W it used about 2.5 of the 4 cores. The bridge uses Picamera2's `MJPEGEncoder`, which runs on the Pi's hardware JPEG encoder. On the same Zero 2 W the bridge uses about 13% of one core.

### Why not rpicam-vid --listen -o tcp://?

`rpicam-vid --codec mjpeg --listen -o tcp://0.0.0.0:8080` looks like a ready-made network stream, but motion and motionEye cannot use it. We tested it with motion 4.7.1 and rpicam-apps 1.13 (see motionEye issue [#3288](https://github.com/motioneye-project/motioneye/issues/3288)):

- **It is not HTTP.** rpicam-vid sends bare JPEG frames without an HTTP response, so motionEye's "add network camera" check cannot accept it, and `mjpeg://` URLs fail in motion ("Failed to read first camera header").
- **It serves one client, once.** rpicam-vid accepts a single connection and quits when that client disconnects (`failed to send data on socket`). motion always opens the stream, reads a frame, closes it and opens it again, so by its second connection rpicam-vid is gone and motion shows its grey "no picture" image.

Restarting rpicam-vid in a loop makes motion's `http://` and `tcp://` URLs work, but then only one client can watch, every motion restart restarts the camera, and motionEye still cannot add the camera. The bridge speaks real HTTP, serves any number of clients and keeps the camera open.

### Built-in safety

- **No first frame:** if the camera delivers nothing within 30 s of start, the bridge logs `no first frame within 30s, exiting for systemd restart` and exits. Before this was added, one bridge waited about 20 hours for a frame after a sensor error.
- **Stall:** a watchdog thread checks every 10 s. If no new frame arrived for more than 20 s, it logs `camera stalled >20s, exiting for systemd restart` and exits. Without it, a camera that stopped delivering ("Camera frontend has timed out" from libcamera) left the server alive, serving one frozen frame. One camera sat like that for about 20 hours.
- **Restart:** the unit has `Restart=on-failure` and `RestartSec=3`, so systemd starts the bridge again 3 s after either exit.
- **Dead clients:** each client connection times out after 15 s. Without this, motion's reconnects left hundreds of half-closed sockets behind until Python could not start new threads and the feed died (after about two days on a Zero 2 W).
- **Local only:** by default the server listens on 127.0.0.1, not on the network. To feed motionEye on another computer, see [motionEye on another machine](#motioneye-on-another-machine).

Known limit: once, the bridge logged "camera stalled ... exiting" and then hung for about 24 minutes before it actually exited (most likely stuck in the camera driver). systemd cannot restart a process that has not exited. Pair the bridge with `tools/cam-watchdog`, which kills and restarts the bridge after 3 minutes without a picture and reboots if that does not help (at most 3 reboots per 24 hours). See [Camera picture freezes or goes dark](../troubleshooting/camera-goes-dark.md).

### What we did not test

motion has its own libcamera support. We did not test it. All our CSI cameras run this bridge.

Autofocus cameras such as the Camera Module 3: the bridge switches autofocus to continuous (`PICAM_AF`, see below), like `rpicam-vid` does by default. We have no Camera Module 3, so we have only checked that cameras without autofocus are not affected.

## Requirements

- A Raspberry Pi with a CSI camera, on Raspberry Pi OS (Trixie).
- motionEye installed, with motion 4.7.x.
- `python3-picamera2` from apt. The bridge runs with the system Python (`/usr/bin/python3`), not with motionEye's Python.
- Port 8080 free on the Pi (or pick another port, see below).
- Nothing else holding the camera. Only one process can use the sensor at a time.

## Install

On the Pi, two commands install it; the script fetches the toolkit by itself:

```sh
wget https://raw.githubusercontent.com/free-cup-holder-exe/motioneye-pi-toolkit/main/install.sh
sudo bash install.sh picam-mjpeg
```

It is safe to run again, `sudo bash install.sh --uninstall picam-mjpeg` undoes it, and `bash install.sh --dry-run picam-mjpeg` only prints the steps. If you have the toolkit folder already, `sudo ./install.sh picam-mjpeg` from that folder does the same. By hand, what the installer does:

```sh
sudo apt install python3-picamera2
sudo install -m 755 -o root -g root tools/picam-mjpeg/picam_mjpeg.py /usr/local/bin/picam_mjpeg.py
sudo install -m 644 -o root -g root tools/picam-mjpeg/picam-mjpeg.service /etc/systemd/system/picam-mjpeg.service
```

Set the size, frame rate and port in a systemd drop-in. The script's built-in defaults (1280x960, 5 fps, 127.0.0.1:8080, continuous autofocus where the camera has it) are at the top of the file.

```sh
sudo mkdir -p /etc/systemd/system/picam-mjpeg.service.d
printf '[Service]\nEnvironment=PICAM_WIDTH=1632 PICAM_HEIGHT=1232 PICAM_FPS=5 PICAM_PORT=8080\n' \
  | sudo tee /etc/systemd/system/picam-mjpeg.service.d/local.conf
sudo systemctl daemon-reload
sudo systemctl enable --now picam-mjpeg
```

Pick the size by sensor. Resolution decides the field of view:

| Sensor | Camera Module | Size we use | Notes |
|---|---|---|---|
| IMX219 | v2 | 1632x1232 @ 5 fps | Binned full-sensor mode. 1632, not the native 1640, so nothing pads the width (costs 0.5% of the view). |
| OV5647 | v1 | 1280x960 @ 5 fps | Binned full-sensor mode. |

Avoid 1920x1080 on these sensors. It is a centre crop and loses about a third of the picture.

In our setup cam-a and cam-c (IMX219) run 1632x1232, and cam-b and cam-d (OV5647) run 1280x960.

Then add the camera in motionEye. In the web UI, add a camera of type **Network Camera** with the URL `http://127.0.0.1:8080/stream.mjpg` and no user name or password. motionEye stores it as `netcam_url http://127.0.0.1:8080/stream.mjpg` in `/etc/motioneye/camera-N.conf`, and motion reads it as a network camera. If you changed `PICAM_PORT`, use that port in the URL.

If you used the raw `/dev/video0` device or a loopback service before, remove that camera and disable the old service. `libcamerify` in motionEye's unit is not needed with the bridge.

## motionEye on another machine

The bridge can also feed motionEye on a different computer, for example a camera-only Pi feeding motionEye on a Pi 4. Add `PICAM_BIND=0.0.0.0` to the drop-in's `Environment=` line, then `sudo systemctl daemon-reload` and `sudo systemctl restart picam-mjpeg`. In that motionEye, add a **Network Camera** with the URL `http://<camera-pi-address>:8080/stream.mjpg`.

The stream has no password. Anyone who can reach port 8080 on the camera Pi can watch it, so only do this on a network you trust, or allow the port only from the motionEye machine with a firewall rule. Several clients can watch at once (motion plus a browser, for example).

motion decodes every frame it receives, so keep the frame rate modest; 5 to 10 fps is plenty for motion detection.

## Check it works

```sh
systemctl is-active picam-mjpeg
sudo journalctl -u picam-mjpeg -n 5 --no-pager
```

The log should end with `first frame captured; streaming on http://127.0.0.1:8080/stream.mjpg`. This usually takes 3 to 7 seconds. Just before it, `autofocus: ...` says whether the camera has autofocus and how it is set.

Check that frames flow (more than 10000 bytes means yes):

```sh
timeout 4 curl -s --max-time 3 http://127.0.0.1:8080/stream.mjpg | head -c 30000 | wc -c
```

Check that motion is connected (allow about 10 s after a restart):

```sh
P=$(sudo awk '$1=="webcontrol_port" {print $2}' /etc/motioneye/motion.conf)
curl -s "http://127.0.0.1:$P/1/detection/connection"
```

Look for `Connection OK`. If you take still images, the best proof is new files on disk:

```sh
sudo find /var/lib/motioneye -name '*.jpg' -newermt '-90 seconds' | wc -l
```

Leaked client connections should stay near 0:

```sh
ss -tn | grep -c 'CLOSE-WAIT.*:8080'
```

Normal log noise you can ignore:

- `motion_init: Error capturing first image` once per motion start. motion probes before its network-camera thread has fetched the first frame. Detection works.
- One kernel line `bcm2835-codec: Failed setting ctrl 00990a67` when the encoder starts.
- `rpicam-hello` says "No cameras available" while the bridge is running. Stop the bridge before using the rpicam tools.

If motion logs "Unable to find stream info" right after many restarts on a small Pi, let the box settle for a minute, then restart motionEye once.

## Undo

```sh
sudo systemctl disable --now cam-watchdog.timer 2>/dev/null   # if you installed it
sudo systemctl disable --now picam-mjpeg
sudo rm -r /etc/systemd/system/picam-mjpeg.service.d
sudo rm /etc/systemd/system/picam-mjpeg.service /usr/local/bin/picam_mjpeg.py
sudo systemctl daemon-reload
```

Then remove or change the network camera in motionEye.
