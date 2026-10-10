# Wi-Fi drops

A camera stops answering ping, SSH and the web UI, sometimes for hours, while the Pi itself keeps
running. This fleet hit three different causes. The fixes differ, so find out which one you have.

Commands assume Raspberry Pi OS (Trixie) and an admin account with sudo.

## Symptoms

- The camera's tile in motionEye goes offline. Ping and SSH fail until someone power-cycles the Pi.
  After the power cycle everything works, so it looks like a crash.
- A milder form: the camera answers, but slowly (pings up to about 1,200 ms). Tiles on the hub
  time out and look offline even though SSH works.
- Alerts from that camera fail to send.
- If the camera that serves your dashboard (the hub, cam-a here) loses Wi-Fi, every camera looks offline.

## Why it happens

### 1. The silent brcmfmac wedge

The Wi-Fi (brcmfmac driver) stops passing traffic. `wlan0` still reports up. Usually nothing is
logged: no disconnect, no deauthentication, nothing in the last hour. cam-a (Pi 4) did this in
mid-July and on 5, 10 and 13 August. By August that was about every three days, mostly in the evening.

The persistent journal proved the OS was alive. In the last hour before one power cycle there were
61 heartbeats in a row with no gap, cron jobs ran, the temperature was 48°C, load 0.80, 3.3 GB free.
The July event could not be diagnosed, because the journal was still volatile. The ext4 orphan
cleanup at the next boot came from the power cycle, not from a crash.

The common factor was signal. cam-a had the weakest link in the fleet: -66 dBm, later -70 to
-72 dBm, on the 5 GHz SSID. The other cameras sat between -36 and -57 dBm. Once the last kernel
lines were SDIO errors (`brcmf_proto_bcdc_msg failed w/status -110`), and that time the board
rebooted itself later that evening. Other times there was nothing at all.

### 2. Sticky clients and two access points

AP 1 (the main router, both bands) and AP 2 (a second AP near cam-d) both broadcast the 2.4 GHz
SSID. A Wi-Fi client picks an AP when it connects and does not move on its own. After a power cut
every box reconnects at once, and not always to the nearest AP. cam-d joined the far AP at -64 dBm
while the near one was at full signal: pings up to 1,200 ms and hub tiles timing out. cam-a did the
same after a later power cut (-63 dBm on the far AP, against -54 on the near one).

### 3. A board-specific SDIO fault (cam-b)

cam-b's kernel logged 664 SDIO "halting operation" events over its life; the other boards logged
none. It lost Wi-Fi once, in September. We put that down as a one-off; it logged none across the two
reboots of the September kernel and firmware upgrade. We once blamed these events for cam-e's
reboots, wrongly: they were cam-b's (see [random-reboots.md](./random-reboots.md)).

## Check

Was the OS alive? Run this after the box is back:

```sh
sudo journalctl -t cam-heartbeat -b -1 -o short-iso | tail -30
sudo journalctl -k -b -1 --no-pager | grep -i brcmf | tail
```

One heartbeat a minute right up to the power cycle means the network failed, not the Pi. A gap
means a real crash: see [random-reboots.md](./random-reboots.md). The heartbeat comes from
`tools/cam-heartbeat/` ([../howto/heartbeat.md](../howto/heartbeat.md)) and needs a
[persistent journal](../howto/persistent-journal.md).

Which AP, which band, how strong:

```sh
sudo /usr/sbin/iw dev wlan0 link     # BSSID = which AP; freq 24xx = 2.4 GHz, 5xxx = 5 GHz; signal
sudo nmcli dev wifi rescan; nmcli -f IN-USE,SSID,BSSID,CHAN,SIGNAL dev wifi list
nmcli -f NAME,AUTOCONNECT,AUTOCONNECT-PRIORITY con show
sudo /usr/sbin/iw dev wlan0 get power_save
/usr/sbin/iw phy | grep -E '^\s*Band'  # bands the radio supports
```

- Use `sudo` and the full path for `iw`. Without them (for example in a non-interactive SSH
  command) it can print nothing, which looks like a pass.
- A Pi Zero W shows only Band 1. It is 2.4 GHz only and cannot join a 5 GHz SSID.
- Write down each camera's normal AP and signal while it is healthy. Compare after every power cut.
- Probe from another machine on the same LAN. Pings from our admin PC were not a reliable sign of
  whether a Pi was up. A camera that is "offline" in the hub but answers SSH is usually slow, not down.
- If a Pi never joins at all, check that a profile exists before you blame range or the password
  (see [random-reboots.md](./random-reboots.md)).

## Fix

### 1. Turn Wi-Fi power save off (every board)

Every Pi 4 in the fleet had power save on. `tools/wifi-powersave-off/` turns it off at every boot.
Set it in each NetworkManager profile too (`2` means disable):

```sh
sudo nmcli con modify "<profile>" 802-11-wireless.powersave 2
```

This was **not enough for cam-a**. It wedged twice more with power save confirmed off.

### 2. Get a better signal: move to the 2.4 GHz SSID (what fixed cam-a)

cam-a only had a profile for the 5 GHz SSID. Our router uses a separate SSID for each band, so
locking that profile to 2.4 GHz (`802-11-wireless.band bg`) fails with "network could not be
found": that SSID does not exist on 2.4 GHz. Add a profile for the 2.4 GHz SSID instead, and keep
the 5 GHz one as a low-priority fallback:

```sh
sudo nmcli con add type wifi ifname wlan0 con-name wifi24 ssid "<2.4 GHz SSID>" \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "<passphrase>" \
  802-11-wireless.powersave 2 connection.autoconnect-priority 20
sudo nmcli con modify "<5 GHz profile>" connection.autoconnect-priority 0
```

- Store the plain passphrase, not a 64-hex pre-hashed key. Hashed keys broke on this network once
  the APs offered WPA3 (a separate story).
- Switching networks over SSH cuts your session. Run the switch detached (`setsid` or `nohup`) and
  set up an automatic revert first. Ours brought the box back when the band-lock attempt failed.
- The new network may hand out a different address. Use a DHCP reservation on the router, or a
  static address outside the DHCP pool. A static address inside the pool can collide with a lease.

Result for cam-a: 2,442 MHz at -50 dBm, about 20 dB better. In the next 9 days there were no
wedges: 114 single lost pings, never 3 in a row.

Wired Ethernet is the sure fix if you can run a cable. The Pi 4 has the port; for cam-a it was not
an option.

### 3. A ping watchdog for a weak box (cam-a only)

cam-a runs a small root cron job every minute. It pings the gateway (for example 192.0.2.1). After
3 failures in a row it turns the radio off and on (`nmcli radio wifi off`, then `on`). If the link
is still dead, it reboots. It skips the first 5 minutes after boot and logs every action with
`logger`. In late September and early October it bounced the radio twice, both times during a large
nightly upload, and Wi-Fi was back in 8 s. We have not rolled it out to cameras that don't need it.

### 4. Sticky client: bounce the connection

```sh
sudo setsid sh -c 'nmcli con down "<profile>"; nmcli con up "<profile>"' >/dev/null 2>&1 < /dev/null &
```

cam-d moved straight to the near AP at -35 dBm, and hub fetches dropped to 0.1 s.

## Verify

- `sudo /usr/sbin/iw dev wlan0 get power_save` says `Power save: off`, also after a reboot.
- `sudo /usr/sbin/iw dev wlan0 link` shows the AP, band and signal you expect.
- Heartbeats run without gaps, and the camera stays reachable for longer than its old wedge
  interval. cam-a wedged about every 3 days, so judge over a week or more.
- After every power cut, check each camera's AP and signal again.

## Limits and open questions

- We don't know what wedges the driver. Weak signal is the strongest link we found. We keep power
  save off on every board, but have no proof that it prevented a wedge.
- The evening clustering may be neighbourhood Wi-Fi congestion. We have not tested that.
- `brcmf_run_escan: error (-52)` scan errors appear in the kernel log with no loss of connection.
  On their own they are not a sign of a wedge.
- cam-a still has short network blips. In October it failed to send some alerts while other
  cameras sent fine in the same minutes. Its alert error lines showed DNS lookups failing
  (`Temporary failure in name resolution`) and connections dropping, so it is the network, not the
  pre-release motionEye it runs; see [Alerts not arriving](./alerts-not-arriving.md).
- Once, after a power cycle, cam-a was up for 76 minutes before it accepted any inbound connection.
  The cause is unknown. To spot this, compare `uptime -s` with the first `Connection from` line in
  `sudo journalctl -t sshd-session -b` (on Trixie, OpenSSH logs as `sshd-session`, not `sshd`).
- All numbers come from one home network with two APs and a handful of Pis.
