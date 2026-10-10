# motioneye-notify

motion runs motionEye's email and Telegram senders from the camera's `on_event_start` command and throws away their output, so a failed alert leaves no trace. This wrapper runs the sender, classifies the outcome and logs one line per attempt:

```
moteye-mail: result=sent rc=0 secs=15 pics=4
moteye-tg:   result=send-failed rc=0 secs=82 pics=4
moteye-tg:   error=failed to send telegram: ...|requests.exceptions.ConnectTimeout: ...
```

- `result`: `sent`, `send-failed`, `listing-timeout`, `crash-nonetype` or `unknown`
- `secs`: how long the send took; `pics`: how many pictures were saved inside the sender's time window (a count only)
- `error=` (failures only): the sender's error message and the exception that ended its traceback, with quoted values, addresses, URLs, tokens, IPs, host names and long numbers masked

`motioneye-notify-heal` puts the wrapper back: motionEye rewrites `on_event_start` whenever notification settings are saved, which drops it.

| File | Goes to |
|---|---|
| `motioneye-notify` | `/usr/local/sbin/motioneye-notify` |
| `motioneye-notify-heal` | `/usr/local/sbin/motioneye-notify-heal` |

```sh
sudo install -m 755 motioneye-notify motioneye-notify-heal /usr/local/sbin/
sudo /usr/local/sbin/motioneye-notify-heal      # REWIRED: camera-1.conf ... (restarts motionEye) or NOCHANGE
# run it every night, after any automatic update (root's crontab):
(sudo crontab -l 2>/dev/null; echo '17 2 * * * /usr/local/sbin/motioneye-notify-heal') | sudo crontab -
```

Also run the heal script by hand after you save notification settings in the web UI or upgrade motionEye.

Read the results:

```sh
journalctl -t moteye-mail -t moteye-tg --since today
journalctl -t moteye-mail -t moteye-tg --since today | grep -c result=sent
journalctl -t moteye-mail -t moteye-tg --since today | grep error=
```

Security notes:

- Never add `-d` to the senders: debug mode prints an argparse namespace that contains the Telegram token.
- Before motionEye's notification rework (motioneye-project/motioneye#3426, in dev / 0.45.0), the SMTP password and Telegram token were on the command line itself; the wrapper never logs raw output for that reason, only the redacted line above.
- The heal script never prints file content.

Works with both the old long command form and the short `sendmail %t MOMENT` form from #3426.

Guide: [docs/howto/log-notification-outcomes.md](../../docs/howto/log-notification-outcomes.md). Troubleshooting: [docs/troubleshooting/alerts-not-arriving.md](../../docs/troubleshooting/alerts-not-arriving.md).
