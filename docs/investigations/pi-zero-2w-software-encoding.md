# Pi Zero 2 W: software vs hardware H.264 for motion movies

## Question

cam-d's camera feed stalled about twice a day. The stalls seemed to cluster
at the start or end of a motion movie.

Two parts of the system used the Pi's hardware encoders at the same time:

- The MJPEG bridge encodes every camera frame with the hardware JPEG encoder.
- motion encoded event movies with `mp4:h264_v4l2m2m`, the hardware H.264
  encoder.

Was contention for the encoder hardware causing the stalls? And can a
Pi Zero 2 W afford to encode movies in software instead?

## Setup

| | |
|---|---|
| Camera | cam-d |
| Board | Raspberry Pi Zero 2 W, 424 MB RAM (as `free` reports it) |
| Sensor | OV5647 on the ribbon (CSI) port |
| Feed | MJPEG bridge at 1280x960, 5 fps; motion reads it as a network camera |
| Software | Raspberry Pi OS 13 (trixie), Python 3.13.5, motion 4.7.1, motionEye 0.44.0 |
| Recording | Event movies only, with `event_gap 0` and `post_capture 0`, so clips are a few seconds long |

One change, on Oct 4 at 12:26: `movie_codec` went from `mp4:h264_v4l2m2m`
(hardware) to `mp4` (software H.264 with x264). In the web UI that is
**Movies > Movie Format**: "H.264/V4L2M2M (.mp4)" became "H.264 (.mp4)".
motionEye was restarted. Nothing else changed.

How each figure was taken:

- **Stalls**: `camera stalled` lines in the bridge's journal. The bridge logs
  this and exits when no frame has arrived for 20 s; systemd restarts it.
- **Dark gap**: time from a `camera stalled` line to the next
  `first frame captured` line.
- **Movies**: `.mp4` files in that day's folder.
- **motion CPU**: `ps -o %cpu= -C motion`.
- **Memory**: MemAvailable, logged once a minute from `free -m`.
- **Throttling**: `vcgencmd get_throttled`.

## Data

Before the switch (hardware encoder):

| Day | Bridge stalls | Movies | Notes |
|---|---|---|---|
| Sep 29 | 2 | - | |
| Oct 1 | 2 | - | |
| Oct 2 | 2 | - | One may have been caused by heavy SSH probing |
| Oct 3 | 10 | 287 | Busy day |
| Oct 4, to 12:26 | 0 | - | |

Long dark gaps happened before the switch too: hangs of 22 to 46 minutes
on Sep 27 and Sep 29.

After the switch (software encoder):

| Day | Bridge stalls | Movies | Notes |
|---|---|---|---|
| Oct 4, from 12:26 | 2 | 59 (whole day) | Both recovered in under 60 s |
| Oct 5 | 2 | 66 | Both recovered in under 60 s |
| Oct 6 to Oct 8 23:50 | 5 in total | - | Dark gaps of 267 s (Oct 6) and about 25 min (1,478 s, Oct 7) |

The 59 movies on Oct 4 cover the whole day, both sides of the switch.

Load:

| | Hardware (before) | Software (after) |
|---|---|---|
| motion CPU (`ps`) | ~26% | ~26% (25.8% on Oct 6) |
| Memory available | 156 MB just before the switch | 159 MB on Oct 6, 103 MB swap in use, no OOM kills |

Also after the switch:

- No throttling (`get_throttled` 0x0; 55.8 °C at the first check).
- The movies were valid H.264 at 1280x960 (checked with `ffprobe`).
- Clips stayed short: the first five were 2.5 to 4.2 s. A sample of 40
  hardware clips from Oct 3 ran 2.2 to 26.7 s.
- Alerts kept working. All 108 alerts from 12:45 on Oct 4 to the morning
  of Oct 6 had their 4 pictures.

## Result

- **Stall rate: unchanged.** 9 stalls from the switch to Oct 8 23:50, about
  4.5 days. That is about 2 a day, the same as before.
- **Long dark gaps: still there.** Two came after the switch: 267 s on Oct 6
  and about 25 minutes on Oct 7. See
  [The camera goes dark](../troubleshooting/camera-goes-dark.md) for what
  happens in those and what to do about them.
- **Cost of software encoding: nothing we could measure.** motion CPU and
  free memory stayed the same, there was no throttling, and the movies were
  valid.

Conclusion: for short event clips at 1280x960, 5 fps, a Pi Zero 2 W can
encode in software at no visible cost. But encoder contention was not the
cause of the stalls. Changing the movie codec does not fix them.

To try it on your own camera, pick **H.264 (.mp4)** under
**Movies > Movie Format**. Or set `movie_codec mp4` in the camera's
`camera-N.conf` and restart motionEye. Keep a copy of the old line to undo.

## Caveats

- **One camera.** This is one Pi Zero 2 W with one sensor. Other boards and
  sensors may behave differently.
- **Short clips.** Clips here are a few seconds long. Long or continuous
  recordings put much more work on the CPU. Do not assume software encoding
  is free for those.
- **No busy-day comparison yet.** The software days were quiet (59 and 66
  movies). The busiest hardware day had 287 movies and 10 stalls. A busy
  day on software has not happened yet.
- **The CPU figure is a lifetime average.** `ps -o %cpu` divides the
  process's total CPU time by how long it has run. It is not the load at
  that moment, and it hides short peaks while a clip is encoded. It is also
  per core: 26% is about a quarter of one of the four cores. motion was
  restarted at the switch, so the "after" figure covers only the software
  period.
- **Probing can disturb the box.** Many SSH sessions in a short time may have
  triggered one stall on Oct 2. Keep checks on a Pi Zero 2 W light.
- **Raspberry Pi 5.** The Pi 5 has no hardware H.264 encoder, so software
  encoding is the only H.264 choice there. This test says nothing about how
  a Pi 5 copes.
