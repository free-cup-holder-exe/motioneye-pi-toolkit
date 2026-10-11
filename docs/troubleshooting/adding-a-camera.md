# Adding a camera fails, hangs or accepts a wrong password

## Symptoms

When you add a **Network Camera** or **Simple MJPEG Camera** in motionEye:

- The dialog keeps waiting for minutes, then shows only a generic error (`http://` cameras).
- Right after adding a working MJPEG camera, the log shows `Exception in callback test_mjpeg_url.<locals>.on_response()`.
- Adding an `rtsp://` camera takes about 2 minutes and then says "failed to connect to rtsp netcam". The log shows `on_connect() missing 1 required positional argument: 'f'`.
- An `rtsp://` camera is found with any password, listed as "(unknown) RTSP/TCP Camera", and then only shows a grey picture.

## Why it happens

motionEye checks a camera's URL before it adds the camera. In 0.43 and 0.44 that check has bugs that hide the real problem:

| Symptom | Cause | Fixed by |
|---|---|---|
| dialog keeps waiting | the `http://` check does not handle connection errors, so it never answers. After 5 minutes the browser gives up and shows "An error occurred". | [#3443](https://github.com/motioneye-project/motioneye/pull/3443) |
| traceback after a working camera | the camera was found from its headers, but the check keeps reading the endless stream until its 10 s timeout, and that timeout is not handled. Harmless. Raising `remote_request_timeout` only makes it read longer. | [#3443](https://github.com/motioneye-project/motioneye/pull/3443) |
| RTSP takes 2 minutes | the 10 s timeout crashes, so the dialog waits until the operating system gives up the connection | [#3444](https://github.com/motioneye-project/motioneye/pull/3444) |
| any RTSP password accepted | for cameras with a Basic login the password is never sent, so it is never checked. motion then fails to log in. Digest logins are not checked at all. | [#3445](https://github.com/motioneye-project/motioneye/pull/3445) (Basic only, and only for cameras that ask for the login on the first request) |

All three are merged into motionEye's `dev` branch for 0.45.0 (see [upstream fixes](../upstream-fixes.md)). Underneath, the camera itself is usually unreachable, not HTTP, or the password is wrong. The checks below find out which.

On motionEye 0.43, a password with special characters such as `#` also broke motion's connection to the camera. 0.44.0 fixed that ([#3296](https://github.com/motioneye-project/motioneye/pull/3296)). For a camera added under 0.43, enter its password again after upgrading, so 0.44 stores it in the fixed form.

## Check

Run these on the computer that runs motionEye, so you test the same network path. Replace the URL with your camera's. If the camera needs a login, add `--anyauth -u 'USER:PASSWORD'`; curl then picks Basic or Digest itself.

**`http://` camera (MJPEG or JPEG):**

```sh
curl -sS -o /dev/null --max-time 3 -w 'HTTP %{http_code}, %{content_type}\n' 'http://CAMERA:PORT/PATH'
```

| You see | Meaning |
|---|---|
| `curl: (28) Operation timed out ...`, then `HTTP 200, multipart/x-mixed-replace; ...` | A working MJPEG stream. The timeout is normal: the stream never ends. |
| `HTTP 200, image/jpeg` | A camera that sends single pictures. Add it as a Network Camera; the Simple MJPEG Camera type does not accept it. |
| `HTTP 401` | Wrong user name or password. |
| `HTTP 404` | Wrong path. |
| `curl: (7) Failed to connect ...` | Nothing listens there: the camera is off, the IP or port is wrong, or a firewall blocks it. |
| `curl: (6) Could not resolve host` | The host name is mistyped, or DNS does not know it. |
| `curl: (28) Connection timed out` | The host does not answer at all. |
| `curl: (1) Received HTTP/0.9 when not allowed` | The camera does not speak HTTP, for example `rpicam-vid --listen -o tcp://`. See the [MJPEG bridge guide](../howto/csi-camera-mjpeg-bridge.md). |

**`rtsp://` camera:**

```sh
curl -sS -o /dev/null --max-time 5 -w 'RTSP %{http_code}\n' --anyauth -u 'USER:PASSWORD' 'rtsp://CAMERA:554/PATH'
```

| You see | Meaning |
|---|---|
| `RTSP 200` | The camera answers. Many cameras don't ask for a login on this request, so it doesn't prove the password is right. |
| `RTSP 401` | Wrong user name or password. |
| `curl: (7) Failed to connect ...` | Nothing listens there. |
| `curl: (28) Connection timed out` | The host does not answer. |

## Fix

Fix what the check shows: switch the camera on, correct the address, port, path or password, or put a real HTTP server in front of a stream that is not HTTP. Then add the camera again.

## Verify

- The camera shows a live picture in motionEye within a few seconds of adding it.
- The motion log has no `Unauthorized` or `401` lines for that camera.

## Limits

- `curl` checks whether the camera answers, not the stream format. motion can still fail on a camera that `curl` reaches, for example with an unusual codec.
- For `rtsp://`, curl asks with `OPTIONS *`, not with the camera's path, so it checks the host, port and login, but not the path. motionEye's own check sends the full URL.
- Some cameras only ask for a login on a later request (`DESCRIBE`). For those, neither this check nor motionEye's own check can tell a wrong password; only the grey picture and the `401` lines in motion's log show it.
