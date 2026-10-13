# Email or Telegram alerts go missing

## Symptoms

- motion records events (movies or pictures are saved), but some alerts never arrive, by email, Telegram or both.
- Nothing in the motionEye log says why.
- Patterns seen here:
  - Alerts stop every afternoon and work again the next morning.
  - One camera loses a few alerts in a short window while the other cameras are fine.
  - During a Wi-Fi outage, alerts failed for about 21 hours before anyone noticed.

## Why it happens

motionEye sends alerts by running `meyectl.py sendmail` and `meyectl.py sendtelegram` from motion's `on_event_start` command. Each sender waits for the picture time span, lists the still pictures from around the event, and sends.

### Why a failure leaves no trace

The senders print what happened, but it does not reach the journal. A 7-day search of the journal here found none of their messages. On motionEye 0.44.0 their output goes to `motion.log`, which starts empty every time motion starts. On current dev, motion's own output goes to `/dev/null` when syslog is available (as on a normal Raspberry Pi OS install), and the senders inherit that. The number of attached pictures is only logged at debug level. On 0.44.0, debug logging also writes the SMTP password and the Telegram bot token into the logs, so do not turn it on.

To make every attempt visible, wrap the senders with [`tools/motioneye-notify/`](../../tools/motioneye-notify/). It logs one line per attempt. Details: [Log notification outcomes](../howto/log-notification-outcomes.md).

### Causes seen here

1. **The Pi lost its network for a while.** Both channels fail for the same event, after a long wait (74-196 s here). See [Wi-Fi drops](./wifi-drops.md).
2. **The picture listing was too slow.** motionEye 0.44.0 lists the whole day's picture folder for every alert. With a snapshot every 5 s, that folder grows by about 720 files an hour. Around midday the listing took longer than its limit (`list_media_timeout_email` and `list_media_timeout_telegram` in `/etc/motioneye/motioneye.conf`, 10 s by default). The sender then crashed because the listing returned no result, and no alert went out. A new day folder at midnight made the mornings work again. On a Pi 4 with 57,093 files, listing the whole folder took 63 s. Listing only the event window took 1.5 s.
3. **DNS lookups failing on one camera.** For a moment the mail server's name could not be looked up, so the email failed quickly while the Telegram message a few seconds later got through. See the cam-a example below.

### Upstream fixes (in motionEye dev, 0.45.0a1; not in 0.44.0)

- [#3413](https://github.com/motioneye-project/motioneye/pull/3413): send the alert even when the picture listing fails. A slow listing then costs the pictures, not the whole alert.
- [#3426](https://github.com/motioneye-project/motioneye/pull/3426): keep notification secrets off the command line. The SMTP password and the Telegram token move into the camera config, and motionEye rewrites `on_event_start` into a short form at first start. The wrapper understands both forms. Run the heal script after the upgrade (see Fix).
- Related: [#3414](https://github.com/motioneye-project/motioneye/pull/3414) and [#3425](https://github.com/motioneye-project/motioneye/pull/3425) make email and Telegram list only the pictures inside the time window. That makes cause 2 much less likely.

## Check

Use `sudo` with `journalctl`. Without it you may get "No entries", which looks like nothing happened. To look back past a reboot you need a [persistent journal](../howto/persistent-journal.md).

1. Is the wrapper in place? This prints counts only. Do not print the `on_event_start` line itself: on 0.44.0 it holds the SMTP password and the Telegram token.

```sh
sudo grep -c motioneye-notify /etc/motioneye/camera-*.conf
```

2. All results today, a 7-day summary, and failures only:

```sh
sudo journalctl -t moteye-mail -t moteye-tg --since today --no-pager
for t in moteye-mail moteye-tg; do echo "$t: $(sudo journalctl -t $t --since -7d -q -o cat | grep -oE 'result=[a-z-]+' | sort | uniq -c | tr '\n' ' ')"; done
sudo journalctl -t moteye-mail -t moteye-tg --since -7d -q -o short-iso | grep -v 'result=sent'
```

A normal line looks like `result=sent rc=0 secs=14 pics=4`.

| result | Meaning | Usually points to |
|---|---|---|
| `sent` | the sender reported success | - |
| `send-failed` | "failed to send" or "Connection refused" | network, mail server, Telegram, or the sender |
| `listing-timeout` | the picture listing ran out of time | slow listing (cause 2) |
| `crash-nonetype` | the sender crashed on a missing listing result (0.44.0) | slow listing (cause 2) |
| `unknown` | none of the above matched | read the `error=` line |

`secs` includes the sender's deliberate wait of one time span. With a 10 s span, 13-26 s was normal on the Pi 4s here, and 37-49 s on the Pi Zero 2 W. Each failure also gets one redacted `error=` line. An example from a test:

```
error=failed to send mail: [Errno 110] Connection timed out|TimeoutError: [Errno 110] Connection timed out
```

3. Tell network, mail server and code apart:

- **Both channels failed for the same event, after a long wait:** this Pi could not reach the outside. Look at the network log for those minutes (change the times):

```sh
S="2026-10-08 15:00"; U="2026-10-08 17:30"
sudo journalctl -k --since "$S" --until "$U" -q | grep -iE 'brcmf|fail'
sudo journalctl -u NetworkManager --since "$S" --until "$U" -q | grep -iE 'state change|disconnect|deauth'
```

- **Mail failed quickly, but Telegram for the same event got through:** the link was up, but read the `error=` line before you blame the mail path. `Temporary failure in name resolution` means the DNS lookup of the mail server failed: a network-side problem on this camera. Otherwise suspect the mail server, this camera's mail settings, or its sender code.
- **`listing-timeout` or `crash-nonetype`:** not the network. See cause 2.
- **Then compare with another camera that uses the same mail server.** Run this on both Pis for the same window:

```sh
sudo journalctl -t moteye-mail -t moteye-tg --since "$S" --until "$U" -q -o short-iso | awk '{print substr($1,12,8), $3, $4, $6}'
```

If the other camera sent fine in the same minutes, through the same server and port, the server was up. The problem is on the failing camera.

### Example: cam-a, one afternoon in October 2026

- cam-a lost 7 sends in just over two hours: 5 emails and 2 Telegram messages.
- Three were quick mail-only failures (24-34 s). Telegram for the same event was sent right after.
- Two events failed on both channels after long waits (74-196 s).
- cam-d uses the same mail server and port. It sent every alert in those same minutes.
- So the mail server was fine, and the cause was on cam-a. It was either its Wi-Fi (the weakest in this setup) or its newer sender code: cam-a runs a motionEye dev build, cam-d runs 0.44.0. The kernel log showed only Wi-Fi scan errors, and NetworkManager logged no disconnects.
- The wrapper did not log error text yet, so the `error=` line was added. The next day's three failures on cam-a answered it:
  - `failed to send mail: Server not connected` (`smtplib.SMTPServerDisconnected`) after 74 s
  - `failed to send telegram: (92, ...)` (`pycurl.error` 92, a broken HTTP/2 stream) after 208 s
  - `failed to send mail: [Errno -3] Temporary failure in name resolution` (`socket.gaierror`) after 24 s
- So the quick mail-only failures were DNS lookups of the mail server failing, and the long ones were connections dropping: cam-a's network, not the sender code.

An earlier case on cam-a was clearer. Two events failed on both channels after 74-82 s, while cam-d sent fine in the same minutes. No network lines were logged at all, which fits cam-a's known silent Wi-Fi drops.

## Fix

1. Install the wrapper and the heal script. Copy the repo's `tools` folder to the Pi, then:

```sh
sudo install -m 755 -o root -g root tools/motioneye-notify/motioneye-notify /usr/local/sbin/motioneye-notify
sudo install -m 755 -o root -g root tools/motioneye-notify/motioneye-notify-heal /usr/local/sbin/motioneye-notify-heal
sudo /usr/local/sbin/motioneye-notify-heal    # prints REWIRED (and restarts motionEye) or NOCHANGE
```

2. Keep it wrapped. motionEye writes a new `on_event_start` line, without the wrapper, every time notification settings are saved. The upgrade to dev (#3426) rewrites it once more at first start. Run the heal script after each save or upgrade, and nightly from root's crontab (`sudo crontab -e`):

```
17 2 * * * /usr/local/sbin/motioneye-notify-heal >/dev/null
```

   The heal script restarts motionEye when it changes something, so run it at a quiet time.

3. On 0.44.0, if you see `listing-timeout` or `crash-nonetype`, raise the listing limits. Raising them to 120 s ended the afternoon outage here.

```sh
sudo cp -p /etc/motioneye/motioneye.conf /etc/motioneye/motioneye.conf.bak-$(date +%Y%m%d-%H%M%S)
sudo sed -i -E 's/^(list_media_timeout_(email|telegram)) .*/\1 120/' /etc/motioneye/motioneye.conf
sudo grep -E '^list_media_timeout_(email|telegram) ' /etc/motioneye/motioneye.conf    # add the two lines if missing
sudo systemctl restart motioneye
```

   With window listing (as in #3414 and #3425), a Pi 4 here listed in about 1.5 s. A Pi Zero 2 W with about 77,000 pictures still took 10.6 s warm and 24.6 s cold, so cam-d keeps the 120 s limit. Keeping pictures for fewer days also makes the listing faster; see [Alerts missing pictures](./alerts-missing-pictures.md).

4. For network causes, see [Wi-Fi drops](./wifi-drops.md).

## Verify

Fire a test event. This sends a real alert. Wait about a minute after any motionEye restart first: here, a test event 15 s after a restart produced no alert at all, because motion was still starting.

```sh
P=$(sudo awk '$1=="webcontrol_port" {print $2}' /etc/motioneye/motion.conf)
curl -s "http://127.0.0.1:$P/1/action/eventstart" >/dev/null; sleep 12
curl -s "http://127.0.0.1:$P/1/action/eventend" >/dev/null
sleep 60; sudo journalctl -t moteye-mail -t moteye-tg --since -3min --no-pager
```

Expect one `result=sent` line per channel. After you save notification settings and the heal script has run, `sudo grep -c motioneye-notify /etc/motioneye/camera-*.conf` should show the old counts again, and `sudo journalctl -t moteye-heal` shows what it rewired.

## Limits and open questions

- The wrapper only sees senders that actually ran. If motion never ran the command (for example right after a restart), there is no line at all. Compare the number of events with the number of result lines.
- `result=sent` means the sender reported success. What happens after that (mail filters, the phone) is outside its view.
- The classification matches the senders' English messages ("email sent", "failed to send"). If upstream changes the wording, results may show up as `unknown`.
- The `error=` redaction is pattern matching. Read the line before you share it.
- Nothing here warns you when alerts fail. Check the summary now and then.
- Why cam-a's DNS lookups and connections fail now and then is not known yet. Its Wi-Fi is the weakest in this setup; see [Wi-Fi drops](./wifi-drops.md).
- #3413 and #3426 are in motionEye dev (0.45.0a1). They are not in 0.44.0.
