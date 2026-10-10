#!/usr/bin/python3
"""MJPEG HTTP server for a Raspberry Pi CSI camera, used by motionEye as a network camera.

Picamera2 captures through libcamera's ISP (lens shading, white balance, exact frame
size) and the hardware JPEG encoder compresses each frame, so the Pi's CPU stays free.
motionEye reads http://127.0.0.1:8080/stream.mjpg.

Settings (environment variables, e.g. from a systemd drop-in):
  PICAM_WIDTH, PICAM_HEIGHT  frame size (default 1280x960)
  PICAM_FPS                  frame rate (default 5)
  PICAM_BIND, PICAM_PORT     listen address (default 127.0.0.1:8080)

The process exits, so systemd restarts it, when no first frame arrives within 30 s or
when frames stop for more than 20 s: a stalled camera otherwise keeps serving the last
frozen frame forever. tools/cam-watchdog keys on the log lines below; keep them as is.
"""
import io
import logging
import os
import threading
from time import monotonic as _monotonic
import socketserver
from http import server
from threading import Condition

from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput

WIDTH = int(os.environ.get("PICAM_WIDTH", 1280))
HEIGHT = int(os.environ.get("PICAM_HEIGHT", 960))
FPS = float(os.environ.get("PICAM_FPS", 5))
BIND = (os.environ.get("PICAM_BIND", "127.0.0.1"), int(os.environ.get("PICAM_PORT", 8080)))


class StreamingOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.last = _monotonic()
        self.condition = Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.last = _monotonic()
            self.condition.notify_all()


class StreamingHandler(server.BaseHTTPRequestHandler):
    # dead clients must never park a thread forever
    timeout = 15

    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path != "/stream.mjpg":
            self.send_error(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Age", "0")
        self.send_header("Cache-Control", "no-cache, private")
        self.send_header("Pragma", "no-cache")
        self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=FRAME")
        self.end_headers()
        sent = None
        try:
            while True:
                with output.condition:
                    if output.frame is None or output.frame is sent:
                        output.condition.wait(timeout=15)
                    frame = output.frame
                if frame is None:
                    continue
                sent = frame
                self.wfile.write(b"--FRAME\r\n")
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(frame)))
                self.end_headers()
                self.wfile.write(frame)
                self.wfile.write(b"\r\n")
        except (OSError, ValueError):
            pass


class StreamingServer(socketserver.ThreadingMixIn, server.HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


logging.basicConfig(level=logging.INFO)
picam2 = Picamera2()
picam2.configure(
    picam2.create_video_configuration(
        main={"size": (WIDTH, HEIGHT)},
        controls={"FrameRate": FPS},
    )
)
output = StreamingOutput()
picam2.start_recording(MJPEGEncoder(), FileOutput(output))

with output.condition:
    # a sensor that never delivers must not hang us here forever
    # (the stall check below only starts after the first frame)
    if not output.condition.wait_for(lambda: output.frame is not None, timeout=30):
        logging.error("no first frame within 30s, exiting for systemd restart")
        os._exit(1)


# if the camera stalls (libcamera frontend timeout), frames stop arriving but the
# HTTP server keeps serving a frozen frame: exit so systemd restarts us
def _watchdog():
    from time import sleep

    while True:
        sleep(10)
        if _monotonic() - output.last > 20:
            logging.error("camera stalled >20s, exiting for systemd restart")
            os._exit(1)


threading.Thread(target=_watchdog, daemon=True).start()
logging.info("first frame captured; streaming on http://%s:%d/stream.mjpg", *BIND)
try:
    StreamingServer(BIND, StreamingHandler).serve_forever()
finally:
    picam2.stop_recording()
