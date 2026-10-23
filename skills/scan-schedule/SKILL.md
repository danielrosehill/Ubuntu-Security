---
name: scan-schedule
description: Schedule periodic malware / rootkit scans and definition refreshes on Ubuntu with systemd timers (cron fallback) — e.g. weekly quick scan, monthly deep scan — writing reports to the user's reports folder, marking the unit failed when there are findings, and sending a desktop notification on desktops. Also lists, changes or removes existing schedules. Use when the user says "schedule virus scans", "run clamav weekly", "automate rkhunter", "set up periodic scans", "what scans are scheduled", or "stop the scheduled scans".
---

# Schedule scans

ClamAV signatures already refresh on their own through the `clamav-freshclam`
service; a timer for definitions is only needed for rkhunter / debsecan. Scans that
read the whole system and run rkhunter/chkrootkit need root, so these are
**system** timers.

## 1. Check what exists

```bash
systemctl list-timers --all --no-pager | grep -Ei 'ubuntu-security|clam|rkhunter|aide|lynis'
ls /etc/cron.daily /etc/cron.weekly 2>/dev/null | grep -Ei 'rkhunter|aide|chkrootkit'
```

Ubuntu packages may already schedule things: `rkhunter` ships
`/etc/cron.daily/rkhunter` (runs only if `CRON_DAILY_RUN="true"` in
`/etc/default/rkhunter`), `aide` ships a daily check (`dailyaidecheck`),
`chkrootkit` ships `/etc/cron.daily/chkrootkit` (gated by `RUN_DAILY` in
`/etc/chkrootkit/chkrootkit.conf`). Report these so nothing runs twice.

## 2. Agree the plan (confirm once before writing)

Default proposal:

| Job | Cadence | Command |
| --- | --- | --- |
| definitions | daily | `av-update.sh` |
| quick scan | weekly | `av-scan.sh --mode quick` |
| deep scan | monthly | `av-scan.sh --mode deep` |

Plus: reports folder (from `config.json`, default `~/security-reports`) and, on a
desktop, which user gets notifications.

## 3. Install the scripts system-wide

Units must not point into a plugin cache that can move:

```bash
sudo install -d /usr/local/lib/ubuntu-security
sudo install -m 0755 "$SCRIPTS"/av-update.sh "$SCRIPTS"/av-scan.sh /usr/local/lib/ubuntu-security/
```

## 4. Write the units

One service + timer per job. Example for the weekly quick scan (substitute
`<user>` and `<reports>`; for a server drop `--notify-user`):

```ini
# /etc/systemd/system/ubuntu-security-quick-scan.service
[Unit]
Description=Weekly quick malware scan (ubuntu-security)
After=network-online.target

[Service]
Type=oneshot
Environment=SUDO_USER=<user>
ExecStart=/usr/local/lib/ubuntu-security/av-scan.sh --mode quick --out <reports> --notify-user <user>
Nice=10
IOSchedulingClass=idle
```

```ini
# /etc/systemd/system/ubuntu-security-quick-scan.timer
[Unit]
Description=Weekly quick malware scan (ubuntu-security)

[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
```

`SUDO_USER` tells the script whose home "quick" means and who owns the reports.
Same pattern for `ubuntu-security-deep-scan` (`--mode deep`, `OnCalendar=monthly`)
and `ubuntu-security-definitions` (`av-update.sh --out <reports>`,
`OnCalendar=daily`). Custom cadences take any `OnCalendar=` expression
(`Sun *-*-* 03:00`); check with `systemd-analyze calendar '<expr>'`.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ubuntu-security-{definitions,quick-scan,deep-scan}.timer
systemctl list-timers --no-pager | grep ubuntu-security
```

`Persistent=true` catches up missed runs after a laptop was asleep or off.

## 5. How findings surface

- `av-scan.sh` exits 1 when there is anything to review, so the service shows as
  **failed**: visible in `systemctl --failed` and
  `journalctl -u ubuntu-security-quick-scan`. On servers this is the signal to
  watch (or hook `OnFailure=` to a mail/notify unit the user already has).
- On desktops, `--notify-user <user>` sends a critical `notify-send` to that user's
  session if they are logged in.
- Reports land in `<reports>/_summary/`.

To test without waiting: `sudo systemctl start ubuntu-security-quick-scan.service`,
then `systemctl status` it.

## Cron fallback (no systemd)

```
# /etc/cron.d/ubuntu-security
0 3 * * *  root  SUDO_USER=<user> /usr/local/lib/ubuntu-security/av-update.sh --out <reports>
0 4 * * 1  root  SUDO_USER=<user> /usr/local/lib/ubuntu-security/av-scan.sh --mode quick --out <reports>
0 5 1 * *  root  SUDO_USER=<user> /usr/local/lib/ubuntu-security/av-scan.sh --mode deep --out <reports>
```

## Remove

```bash
sudo systemctl disable --now ubuntu-security-{definitions,quick-scan,deep-scan}.timer
sudo rm /etc/systemd/system/ubuntu-security-*.{service,timer}
sudo systemctl daemon-reload
```

Units written by the older `linux-av-manager` plugin are named
`linux-av-manager-*.timer`; offer to replace them rather than run both.

## Scripts

`SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"`. If `CLAUDE_PLUGIN_ROOT` is unset, clone
`https://github.com/danielrosehill/Ubuntu-Security` (e.g. to
`~/.local/share/ubuntu-security-skills`) and use its `scripts/`.
