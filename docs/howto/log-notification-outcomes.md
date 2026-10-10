# Log the outcome of every motionEye alert

## What it does

motionEye sends email and Telegram alerts by running `meyectl.py sendmail` and `meyectl.py sendtelegram` from motion's `on_event_start` command. The senders run as children of motion. Their output does not reach the journal; at most it lands in motion's own log file, which starts empty each time motion starts. So a failed alert leaves no trace you can find the next day.

In our setup, alerts stopped every afternoon for weeks before anyone could prove why. The picture lookup timed out as the day's folder grew, and nothing was logged.

`tools/motioneye-notify/motioneye-notify` fixes the visibility gap. It wraps each sender command, waits for it, and writes one line to syslog per attempt:

```
moteye-mail: result=sent rc=0 secs=14 pics=4
```

| Field | Meaning |
|---|---|
| `result` | `sent`, `listing-timeout` (the sender gave up waiting for motionEye's picture listing), `crash-nonetype` (the old crash after a failed listing, fixed upstream in #3413), `send-failed` (mail server or Telegram not reached or refused), `unknown` (anything else). |
| `rc` | The sender's exit code. |
| `secs` | How long the send took. The sender first waits for the time span on purpose (10 s by default), so 14-20 s on a Pi 4 is normal. |
| `pics` | Pictures in the same +/- time span window the sender uses. A count only: no names, no content. `-` means it could not count. |

The tag is `moteye-mail` for email and `moteye-tg` for Telegram.

On failures only, it writes one more line: `error=...`. This holds the sender's error text and the exception at the end of its traceback. Quoted values, email addresses, URLs, tokens, IP addresses, host names and long numbers are replaced with placeholders such as `<v>`, `<addr>` and `<token>`. The line is cut at 300 characters.

### What pics should be

With `picture_output off`, the periodic snapshots are the pictures that get attached. Pictures per alert = (2 x time span) / snapshot interval. With snapshots every 5 s and a 10 s span, that is 4. `pics=0` or `pics=1` means alerts arrive without the pictures you expect, even though they still say `result=sent`. The count looks in `/var/lib/motioneye/<camera>/<day>` folders. If your media lives elsewhere, `pics` is always `-`.

### Security notes

- On motionEye 0.44 and older, the Telegram bot token and the SMTP password are arguments on the `on_event_start` command line. They are visible in `ps` to local users. (dev, the coming 0.45, moves them into config keys: #3426.) The wrapper sees these arguments, so it never logs raw output. It logs a classification, plus the redacted error line on failures.
- **Never add `-d` to the sender commands.** In debug mode `sendtelegram` prints its parsed arguments, bot token included, in full (issue #3422). For the same reason, do not raise motionEye's `log_level` to debug while secrets are on the command line.
- Never print the `on_event_start` line when you share output. Use `grep -c` to count instead.
- The redaction is pattern matching, not a guarantee. Read an `error=` line before you paste it anywhere public.

### Why the heal script exists

motionEye writes a new `on_event_start` line every time notification settings are saved, in the web UI or through Home Assistant. The new line has no wrapper, so logging stops without a sound. An upgrade can rewrite it too: on first start, dev (0.45) converts the line to a short form (`... sendmail %t MOMENT`) and moves secrets into `# @` keys. The wrapper understands both forms. In the short form it reads the time span from `# @email_notifications_picture_time_span` or `# @telegram_notifications_picture_time_span` in the camera's config.

`tools/motioneye-notify/motioneye-notify-heal` scans `/etc/motioneye/camera-*.conf`. It finds sender commands (`meyectl.py sendmail`, `meyectl.py sendtelegram`) that lack the wrapper and puts it back in front. If it changed a file, it writes it atomically with the same owner and mode, logs `moteye-heal: rewired notify wrapper in: camera-1.conf` and restarts motionEye. It prints `REWIRED: ...` or `NOCHANGE`. It never prints file contents and never replaces the wrapper script itself.

We run it from root's crontab every night at 02:17, after the nightly update. We also run it by hand after every motionEye upgrade, after saving notification settings, and as part of a canary deploy.

## Requirements

- motionEye with email and/or Telegram notifications turned on.
- The wrapper must live at `/usr/local/sbin/motioneye-notify`. The heal script uses that exact path.
- A persistent journal, so results survive a reboot: [Keep the journal across reboots](persistent-journal.md).

## Install

Copy the repo's `tools` folder to the Pi, then:

```sh
sudo install -m 755 -o root -g root tools/motioneye-notify/motioneye-notify /usr/local/sbin/motioneye-notify
sudo install -m 755 -o root -g root tools/motioneye-notify/motioneye-notify-heal /usr/local/sbin/motioneye-notify-heal
for f in /etc/motioneye/camera-*.conf; do sudo cp -p "$f" "$f.bak-notifylog"; done
sudo /usr/local/sbin/motioneye-notify-heal
```

The last command wraps the existing commands and restarts motionEye. Then schedule it with `sudo crontab -e` and this line:

```
17 2 * * * /usr/local/sbin/motioneye-notify-heal >/dev/null
```

## Check it works

Count the wrapped commands (one or two per camera with notifications on; this prints counts only):

```sh
sudo grep -c motioneye-notify /etc/motioneye/camera-*.conf
```

Fire a test event. This sends a real alert. Wait about a minute after any motionEye restart first: one test event sent 15 s after a restart produced no alert at all, because motion was still starting.

```sh
P=$(sudo awk '$1=="webcontrol_port" {print $2}' /etc/motioneye/motion.conf)
curl -s "http://127.0.0.1:$P/1/action/eventstart" >/dev/null; sleep 12
curl -s "http://127.0.0.1:$P/1/action/eventend" >/dev/null
sleep 30; sudo journalctl -t moteye-mail -t moteye-tg --since "-5 min" --no-pager
```

### Reading the results

```sh
sudo journalctl -t moteye-mail -t moteye-tg --since today
sudo journalctl -t moteye-mail -t moteye-tg --since today -o cat | grep -oE 'result=[a-z-]+|pics=[0-9-]+' | sort | uniq -c
sudo journalctl -t moteye-mail -t moteye-tg --since "-2 days" | grep error=
sudo journalctl -t moteye-heal
```

Always use `sudo`. Without it, `journalctl` may answer "No entries", which looks like a broken pipeline. A wrong tag gives the same answer. If alerts fail, see [Alerts not arriving](../troubleshooting/alerts-not-arriving.md).

## Undo

Remove the wrapper from the config before you delete it. A command that still points at a missing wrapper breaks that alert.

1. Remove the cron line (`sudo crontab -e`), so the heal script does not wrap things again.
2. Open each camera's notification settings in the web UI and save. motionEye writes a new line without the wrapper. (Or restore the `.bak-notifylog` copies and restart motionEye, if you have not changed any settings since.)
3. Check that `sudo grep -c motioneye-notify /etc/motioneye/camera-*.conf` shows 0 for every file.
4. `sudo rm /usr/local/sbin/motioneye-notify /usr/local/sbin/motioneye-notify-heal`
