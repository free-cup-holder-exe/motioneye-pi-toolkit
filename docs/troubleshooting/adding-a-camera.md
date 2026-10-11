# Adding a camera fails, hangs or accepts a wrong password

## Symptoms

When you add a **Network Camera** or **Simple MJPEG Camera** in motionEye:

- The dialog keeps waiting and never shows an error (`http://` cameras).
- Right after adding a working MJPEG camera, the log shows `Exception in callback test_mjpeg_url.<locals>.on_response()`.
- Adding an `rtsp://` camera takes about 2 minutes and then says "failed to connect to rtsp netcam". The log shows `on_connect() missing 1 required positional argument: 'f'`.
- An `rtsp://` camera is found with any password, listed as "(unknown) RTSP/TCP Camera", and then only shows a grey picture.

## Why it happens

motionEye checks a camera's URL before it adds the camera. In 0.43 and 0.44 that check has bugs that hide the real problem:

| Symptom | Cause | Fixed by |
|---|---|---|
| dialog keeps waiting | the `http://` check does not handle connection errors, so it never answers. The browser gives up after 5 minutes. | [#3443](https://github.com/motioneye-project/motioneye/pull/3443) |
| traceback after a working camera | the camera was found from its headers, but the check keeps reading the endless stream until its 10 s timeout, and that timeout is not handled. Harmless. Raising `remote_request_timeout` only makes it read longer. | [#3443](https://github.com/motioneye-project/motioneye/pull/3443) |
| RTSP takes 2 minutes | the 10 s timeout crashes, so the dialog waits until the operating system gives up the connection | [#3444](https://github.com/motioneye-project/motioneye/pull/3444) |
| any RTSP password accepted | for cameras with a Basic login the password is never sent, so it is never checked. motion then fails to log in. Digest logins are not checked at all. | [#3445](https://github.com/motioneye-project/motioneye/pull/3445) (Basic only) |

All three are open pull requests (see [upstream fixes](../upstream-fixes.md)). Underneath, the camera itself is usually unreachable, not HTTP, or the password is wrong. The checks below find out which.

On motionEye 0.43, a password with special characters such as `#` also broke motion's connection to the camera. 0.44.0 fixed that ([#3296](https://github.com/motioneye-project/motioneye/pull/3296)).

## Check

Run these on the computer that runs motionEye, so you test the same network path. Replace the URL with your camera's. If the camera needs a login, add `-u 'USER:PASSWORD'`.

**`http://` camera (MJPEG or JPEG):**

```sh
curl -sS -o /dev/null --max-time 3 -w 'HTTP %{http_code}, %{content_type}\n' 'http://CAMERA:PORT/PATH'
```

| You see | Meaning |
|---|---|
| `HTTP 200, multipart/x-mixed-replace; ...`, then `curl: (28) Operation timed out` | A working MJPEG stream. The timeout is normal: the stream never ends. |
| `HTTP 200, image/jpeg` | A camera that sends single pictures. motionEye can use that too. |
| `HTTP 401` | Wrong user name or password. |
| `HTTP 404` | Wrong path. |
| `curl: (7) Failed to connect ...` | Nothing listens there: the camera is off, the IP or port is wrong, or a firewall blocks it. |
| `curl: (6) Could not resolve host` | The host name is mistyped, or DNS does not know it. |
| `curl: (28) Connection timed out` | The host does not answer at all. |
| `curl: (1) Received HTTP/0.9 when not allowed` | The camera does not speak HTTP, for example `rpicam-vid --listen -o tcp://`. See the [MJPEG bridge guide](../howto/csi-camera-mjpeg-bridge.md). |

**`rtsp://` camera:**

```sh
curl -sS -o /dev/null --max-time 5 -w 'RTSP %{http_code}\n' -u 'USER:PASSWORD' 'rtsp://CAMERA:554/PATH'
```

| You see | Meaning |
|---|---|
| `RTSP 200` | The camera answers and accepts the login. |
| `RTSP 401` | Wrong user name or password. For a camera with a Digest login, add `--digest` and try again. |
| `curl: (7) Failed to connect ...` | Nothing listens there. |
| `curl: (28) Connection timed out` | The host does not answer. |

## Fix

Fix what the check shows: switch the camera on, correct the address, port, path or password, or put a real HTTP server in front of a stream that is not HTTP. Then add the camera again.

## Verify

- The camera shows a live picture in motionEye within a few seconds of adding it.
- The motion log has no `Unauthorized` or `401` lines for that camera.

## Limits

- `curl` checks the same URL motionEye uses, but not the stream format. motion can still fail on a camera that `curl` reaches, for example with an unusual codec.
- The RTSP check above sends an `OPTIONS` request, like motionEye. Some cameras only ask for a login on the next request (`DESCRIBE`), so `RTSP 200` does not prove the password is right on every camera.
