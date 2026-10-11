# Fixes contributed upstream

Sixteen fixes to [motionEye](https://github.com/motioneye-project/motioneye)
came out of running this setup. Most started as a problem seen on these
cameras. Some (#3416, #3443, #3444, #3445) started from other users' reports.

**Status:** 13 are merged into motionEye's `dev` branch and planned for the
next release, **0.45.0**. The three about adding cameras are open pull
requests. None of them are in 0.44.0.

## Notifications

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3413](https://github.com/motioneye-project/motioneye/pull/3413) | An alert is still sent when listing its pictures times out, just without the pictures. Before, the alert was silently dropped. | 2026-09-09 |
| [#3425](https://github.com/motioneye-project/motioneye/pull/3425) | Telegram alerts only look at pictures in the alert's time span, like email alerts. A big day folder no longer makes them time out and arrive without pictures. | 2026-09-30 |
| [#3428](https://github.com/motioneye-project/motioneye/pull/3428) | Telegram alert pictures arrive oldest first, the same order as email. | 2026-10-01 |
| [#3426](https://github.com/motioneye-project/motioneye/pull/3426) | The SMTP password and Telegram bot token are no longer on motion's command line, so they stay out of the process list and out of `motion.log` at debug level. They are kept in the camera's config file instead. | 2026-10-05 |

## Configuration, passwords and the camera list

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3433](https://github.com/motioneye-project/motioneye/pull/3433) | motionEye no longer sends set passwords to the browser or API; the UI shows `*****` for them. Home Assistant and other API clients that save a config back unchanged no longer overwrite a password with `*****`. | 2026-10-05 |
| [#3434](https://github.com/motioneye-project/motioneye/pull/3434) | A webhook command that can't be parsed (for example a URL with a `'` in it) no longer breaks the camera list for every camera. It shows as a custom command, and a warning names the camera and setting. | 2026-10-05 |
| [#3421](https://github.com/motioneye-project/motioneye/pull/3421) | One offline camera behind a remote motionEye no longer breaks the whole camera list. It shows as "Connection failed" and the other cameras load. | 2026-10-01 |

## Adding cameras

| PR | What changes for you | Status |
|---|---|---|
| [#3443](https://github.com/motioneye-project/motioneye/pull/3443) | Adding an `http://` network camera or simple MJPEG camera that can't be used (offline, mistyped host, no answer, or a stream that is not HTTP) shows the reason within seconds. Before, the dialog kept waiting for minutes. A working camera no longer leaves an `Exception in callback ... on_response()` traceback in the log, and a failed check is logged. motionEye's log lines for the check leave out the URL's query, which some cameras use for their login. | open, approved |
| [#3444](https://github.com/motioneye-project/motioneye/pull/3444) | Adding an `rtsp://` camera that does not answer reports "timeout connecting to rtsp netcam" after 10 s, instead of "failed to connect" after about 2 minutes with a `TypeError` in the log. A camera that answers 401 without naming its login type gets an answer after 1 s instead of none. | open |
| [#3445](https://github.com/motioneye-project/motioneye/pull/3445) | Adding an `rtsp://` camera with a Basic login checks the password again: a wrong one gives "authentication failed". Before, the camera was listed as found and then showed a grey picture. This worked in 0.42.1 and broke in the Python 3 port. Digest logins are still not checked. | open |

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

## Performance

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3414](https://github.com/motioneye-project/motioneye/pull/3414) | Email alerts list only the pictures in the alert's time window, not the whole day folder. On a Pi 4 with 57,093 files the listing went from 63.3 s to 1.5 s, well inside the default 10 s timeout. | 2026-09-10 |

This does not make huge folders free. On a Pi Zero 2 W with about 77,000
files the windowed listing still took 10.6 s. On small boards, keep media
retention short.

## Python 3.14

| PR | What changes for you | Merged into dev |
|---|---|---|
| [#3416](https://github.com/motioneye-project/motioneye/pull/3416) | On Python 3.14, cleanup deletes old media again, zip downloads use the right media folder, and background processes keep their log lines. See [the investigation](investigations/python-3.14-forkserver.md). | 2026-09-14 |

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
- **#3445 (if it is merged by then):** Adding an RTSP camera with a Basic
  login and a wrong password now fails with "authentication failed".
  Cameras you already added are not affected.

## Getting them before 0.45.0

The 13 merged ones are on `dev` today; the three open ones are not yet. To
run `dev` before the release, see the
[canary testing guide](howto/canary-testing-dev.md). Start with one camera
you can afford to lose for a while, and keep a way back to the release you
run now.
