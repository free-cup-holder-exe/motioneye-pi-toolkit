# Fixes contributed upstream

Thirty-five changes to [motionEye](https://github.com/motioneye-project/motioneye)
came out of running this setup. Most started as a problem seen on these
cameras. Some (#3416, #3443, #3444, #3445) started from other users' reports.

**Status of all 35:** merged into motionEye's `dev` branch and planned for
the next release, **0.45.0**. None of them are in 0.44.0. Three more are
still open; see [Open](#open).

## Notifications

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3413](https://github.com/motioneye-project/motioneye/pull/3413) | An alert is still sent when listing its pictures times out, just without the pictures. Before, the alert was silently dropped. | 2026-09-09 |
| [#3425](https://github.com/motioneye-project/motioneye/pull/3425) | Telegram alerts only look at pictures in the alert's time span, like email alerts. A big day folder no longer makes them time out and arrive without pictures. | 2026-09-30 |
| [#3428](https://github.com/motioneye-project/motioneye/pull/3428) | Telegram alert pictures arrive oldest first, the same order as email. | 2026-10-01 |
| [#3426](https://github.com/motioneye-project/motioneye/pull/3426) | The SMTP password and Telegram bot token are no longer on motion's command line, so they stay out of the process list and out of `motion.log` at debug level. They are kept in the camera's config file instead. | 2026-10-05 |
| [#3457](https://github.com/motioneye-project/motioneye/pull/3457) | A Telegram alert that Telegram rejects (wrong chat id or token) is logged as failed, and the test button in the UI says so. Before, both said sent. A request that gets no data for 60 s is given up instead of hanging. | 2026-10-15 |
| [#3479](https://github.com/motioneye-project/motioneye/pull/3479) | Email alerts sent with "Use TLS" check the mail server's certificate, host name included. Before, any certificate was accepted. For a relay with a self-signed certificate, or one entered by IP address, turn off the new "Verify certificate" switch under "Use TLS". | 2026-10-27 |
| [#3511](https://github.com/motioneye-project/motioneye/pull/3511) | After a failed Telegram request, the next ones use a new connection, and one failed picture no longer stops the others. A picture that was already sent is not sent again, so a lost reply no longer posts it twice. | 2026-11-01 |

## Configuration, passwords and the camera list

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3433](https://github.com/motioneye-project/motioneye/pull/3433) | motionEye no longer sends set passwords to the browser or API; the UI shows `*****` for them. Home Assistant and other API clients that save a config back unchanged no longer overwrite a password with `*****`. | 2026-10-05 |
| [#3434](https://github.com/motioneye-project/motioneye/pull/3434) | A webhook command that can't be parsed (for example a URL with a `'` in it) no longer breaks the camera list for every camera. It shows as a custom command, and a warning names the camera and setting. | 2026-10-05 |
| [#3421](https://github.com/motioneye-project/motioneye/pull/3421) | One offline camera behind a remote motionEye no longer breaks the whole camera list. It shows as "Connection failed" and the other cameras load. | 2026-10-01 |
| [#3458](https://github.com/motioneye-project/motioneye/pull/3458) | Extra `netcam_params` entries added through Extra Options (for example motion's `decoder` for hardware decoding) survive a save. Before, motionEye kept only its own keepalive, tolerant-check and RTSP-transport settings and dropped the rest. | 2026-10-15 |
| [#3459](https://github.com/motioneye-project/motioneye/pull/3459) | An error a remote motionEye reports inside a 200 answer (a failed notification test, a delete, a save behind two hubs) shows as an error on the hub. Before, the hub reported success, and a failed movie download through two hubs was cached as if it were the movie. | 2026-10-16 |
| [#3480](https://github.com/motioneye-project/motioneye/pull/3480) | A hub no longer saves a remote camera's "Connection failed" placeholder as that camera's settings. Home Assistant posts it back when it loads, which left the camera disabled on the hub after the remote was reachable again. | 2026-10-27 |
| [#3481](https://github.com/motioneye-project/motioneye/pull/3481) | A hub running 0.44 can save a remote camera that runs the new version. On dev, the whole save failed with an internal server error, because the 0.44 form lacks three upload settings added since. | 2026-10-27 |
| [#3501](https://github.com/motioneye-project/motioneye/pull/3501) | Each camera file records the motionEye version that saved it, so a step of an upgrade runs once for that camera instead of on every start. | 2026-10-31 |

## Certificates and uploads

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3472](https://github.com/motioneye-project/motioneye/pull/3472) | The FTP upload service gets a "Use TLS (FTPS)" switch, off by default, with a "Verify certificate" switch for a server with a self-signed certificate. | 2026-10-25 |
| [#3473](https://github.com/motioneye-project/motioneye/pull/3473) | The upload service's Test button no longer ends its success message with "[object Object]". | 2026-10-25 |
| [#3476](https://github.com/motioneye-project/motioneye/pull/3476) | The global `validate_certs` option is gone: every HTTPS connection checks the certificate. A remote motionEye camera gets its own "Verify certificate" switch, for a remote with a self-signed certificate. | 2026-10-26 |
| [#3477](https://github.com/motioneye-project/motioneye/pull/3477) | WebDAV and S3 uploads to an `https://` endpoint, and each webhook, get their own "Verify certificate" switch. | 2026-10-27 |

## Testing

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3486](https://github.com/motioneye-project/motioneye/pull/3486) | Tests pin the 130 camera settings a hub running 0.44 sends, so a newer remote keeps accepting them. | 2026-10-29 |
| [#3493](https://github.com/motioneye-project/motioneye/pull/3493) | Every pull request now runs a hub and a remote of different motionEye versions together, in both directions. | 2026-10-30 |

## Adding cameras

| PR | What changes for you | Status |
|---|---|---|
| [#3443](https://github.com/motioneye-project/motioneye/pull/3443) | Adding an `http://` network camera or simple MJPEG camera that can't be used (offline, mistyped host, no answer, or a stream that is not HTTP) shows the reason within seconds. Before, the dialog kept waiting for minutes. A working camera no longer leaves an `Exception in callback ... on_response()` traceback in the log, and a failed check is logged. motionEye's log lines for the check leave out the URL's query, which some cameras use for their login. | merged into dev 2026-10-11 |
| [#3444](https://github.com/motioneye-project/motioneye/pull/3444) | Adding an `rtsp://` camera that does not answer reports "timeout connecting to rtsp netcam" after 10 s, instead of "failed to connect" after about 2 minutes with a `TypeError` in the log. A camera that answers 401 without naming its login type gets an answer after 1 s instead of none. | merged into dev 2026-10-11 |
| [#3445](https://github.com/motioneye-project/motioneye/pull/3445) | Adding an `rtsp://` camera with a Basic login checks the password again: a wrong one gives "authentication failed". Before, the camera was listed as found and then showed a grey picture. This worked in 0.42.1 and broke in the Python 3 port. It only helps cameras that ask for the login on the first request (`OPTIONS`); for cameras that only ask later, a wrong password still passes. Digest logins are still not checked. | merged into dev 2026-10-11 |

Until these ship, [Adding a camera fails, hangs or accepts a wrong password](troubleshooting/adding-a-camera.md) shows how to check a camera yourself.

## Web UI and security headers

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3431](https://github.com/motioneye-project/motioneye/pull/3431) | The UI no longer shows raw Esperanto in Chrome or Edge behind a reverse proxy that sends `Permissions-Policy: sync-xhr=()`. The translations are now built into the page. | 2026-10-03 |
| [#3435](https://github.com/motioneye-project/motioneye/pull/3435) | The UI now works under a strict Content-Security-Policy, which motionEye now sends. If you use custom templates or static files (`template_path`/`static_path`), update them together with the new release. | 2026-10-07 |

## Logging and startup

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3427](https://github.com/motioneye-project/motioneye/pull/3427) | A typo in `log_level` no longer turns on debug logging, which also made motion log its whole configuration and every event command. motionEye keeps the current level and logs `unknown log level`. | 2026-10-04 |
| [#3436](https://github.com/motioneye-project/motioneye/pull/3436) | Messages from the config migration at startup now reach the normal log, including `motioneye.log` with `log_to_file`. Before, the info line was dropped and warnings went only to stderr. | 2026-10-05 |
| [#3456](https://github.com/motioneye-project/motioneye/pull/3456) | Errors from the alert commands (`sendmail`, `sendtelegram`, webhooks) reach the journal, tagged `meyectl`, on systems with syslog. On dev they went nowhere unless `log_to_file` was on; in 0.44.0 they were in `motion.log`. | 2026-10-15 |
| [#3452](https://github.com/motioneye-project/motioneye/pull/3452) | Stopping the service stops it at once. On dev, the stop signal was only noticed at the next timer, often the 10 s motion checker, which then restarted motion in the middle of the shutdown. A `systemctl stop` now takes as long as motion's own exit, about 4-6 s on a Pi 4. | 2026-10-18 |

## Performance

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3414](https://github.com/motioneye-project/motioneye/pull/3414) | Email alerts list only the pictures in the alert's time window, not the whole day folder. On a Pi 4 with 57,093 files the listing went from 63.3 s to 1.5 s, well inside the default 10 s timeout. | 2026-09-10 |
| [#3454](https://github.com/motioneye-project/motioneye/pull/3454) | The 12-hourly cleanup of old media checks each folder once instead of after every file it deletes. With 5 s snapshots a day folder holds 17,280 stills, and the old way grew with the square of that. | 2026-10-15 |
| [#3460](https://github.com/motioneye-project/motioneye/pull/3460) | The camera list asks all remote cameras at the same time. Each remote that didn't answer used to add its full timeout (10 s by default): five remotes with three unreachable took 30 s and now take 10 s. | 2026-10-15 |

This does not make huge folders free. On a Pi Zero 2 W with about 77,000
files the windowed listing still took 10.6 s. On small boards, keep media
retention short.

## Python 3.14

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3416](https://github.com/motioneye-project/motioneye/pull/3416) | On Python 3.14, cleanup deletes old media again, zip downloads use the right media folder, and background processes keep their log lines. See [the investigation](investigations/python-3.14-forkserver.md). | 2026-09-14 |

## Dependencies

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3516](https://github.com/motioneye-project/motioneye/pull/3516) | motionEye uses Tornado's own HTTP client instead of curl's, so it no longer needs `pycurl` for its own requests. The add-camera test answers a digest login itself and reports a redirect instead of following it. A hub opens a new connection for every request to a remote camera, a few ms more per frame on a LAN. | 2026-11-10 |

## Before you upgrade to 0.45.0

Notes from the PR descriptions:

- **#3426:** Stop motionEye before you upgrade and start it afterwards.
  Otherwise email and Telegram alerts fail until motionEye is restarted.
  motionEye moves your existing settings when it starts. A wrapper script in
  front of motionEye's own `sendmail` or `sendtelegram` command is dropped,
  as a save in the web UI already does. Hand-written calls of
  `meyectl sendmail` or `meyectl sendtelegram` with other arguments must be
  updated by hand. After a downgrade, re-enter the email and Telegram
  settings in the web UI.
- **#3435:** Custom `template_path`/`static_path` trees copied from an older
  version will have their inline script and style blocked. Update
  `main.html`, `main.js` and the CSS together. If your reverse proxy adds its
  own Content-Security-Policy header, browsers apply both.
- **#3433:** A password can no longer be cleared through the API. The web UI
  never allowed that either.
- **#3445:** Adding an RTSP camera with a Basic
  login and a wrong password now fails with "authentication failed".
  Cameras you already added are not affected.
- **#3456:** On a system with syslog, errors from the alert commands are in
  the journal under the `meyectl` tag (`journalctl -t meyectl`), not in
  `motion.log`.
- **#3457:** A Telegram setup that never worked now says so: the test button
  reports the failure instead of "sent". Check the chat id and token.
- **#3476, #3477, #3479:** Certificates are checked everywhere now, and a
  `validate_certs` line in `motioneye.conf` is ignored with a warning. For a
  self-signed certificate, or a server entered by IP address, turn off
  "Verify certificate" for that remote camera, upload service, webhook, or
  for email under "Use TLS". Email with "Use TLS" did not check certificates
  at all before, so a relay that worked on 0.44 can stop until you do.
- **#3501:** After going back to 0.44, email and Telegram show as off and
  must be entered again, as #3426 says. Upgrading again moves them back.
- **#3516:** `pycurl` is now used for SFTP uploads only and `boto3` for S3
  uploads only, and since #3535 neither is installed with motionEye. An
  upgrade keeps what is already installed. On a new install that uses those
  uploads, add them with `pip install 'motioneye[s3,sftp]'`; without them
  the upload test says what to install.

## Getting them before 0.45.0

All 35 are on `dev` today. To
run `dev` before the release, see the
[canary testing guide](howto/canary-testing-dev.md). Start with one camera
you can afford to lose for a while, and keep a way back to the release you
run now.

## Open

| PR | What changes for you | Status |
|---|---|---|
| [#3538](https://github.com/motioneye-project/motioneye/pull/3538) | At most two media listings run at a time (`list_media_max_parallel`), and the others wait their turn. Before, every request for a media list started its own copy of the server process, so a client that asked for many cameras at once could run a small board or a container out of memory. | open since 2026-11-09 |
| [#3539](https://github.com/motioneye-project/motioneye/pull/3539) | The media list is read while the listing runs, instead of being checked twice a second. On a Pi 4, a day folder of about 17,000 pictures lists in about 1.3 s instead of 18 s. | open since 2026-11-10 |
| [#3540](https://github.com/motioneye-project/motioneye/pull/3540) | Telegram alerts get a "Send the text first" switch, off by default: the text goes out as soon as motion is detected, and the pictures follow as replies once their time span is over. | open since 2026-11-10 |
