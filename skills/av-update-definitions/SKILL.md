---
name: av-update-definitions
description: Refresh signature databases and data for every installed scanner on Ubuntu — freshclam (ClamAV), rkhunter --update, Lynis version check, debsecan CVE list — and report one status line per tool, without re-baselining rkhunter or AIDE. Also explains stale ClamAV signatures (freshclam service down, mirror rate-limiting). Use when the user says "update antivirus definitions", "refresh signatures", "update clamav", "is clamav up to date", or before a scan when signatures are old.
---

# Update definitions

## Run

```bash
sudo bash "$SCRIPTS/av-update.sh"            # optional: --out <reports_dir>
```

The script skips tools that aren't installed and prints one line per tool:

```
clamav     updated (ClamAV 1.4.3/27800/Thu Oct 23 08:21:00 2026)
rkhunter   up to date
lynis      ...
debsecan   41 CVE entries listed - ~/security-reports/debsecan/<ts>.txt
```

By hand, the equivalent is:

| Tool | Command | Note |
| --- | --- | --- |
| ClamAV | `sudo systemctl stop clamav-freshclam && sudo freshclam; sudo systemctl start clamav-freshclam` | stop the service first: it holds the DB lock |
| rkhunter | `sudo rkhunter --update` | exit 0 = nothing new, 2 = updated, 1 = failed |
| Lynis | `sudo lynis update info` | upgrade via apt if behind |
| chkrootkit | — | no feed; updated with the package |
| AIDE | — | no feed; integrity check lives in `malware-scan` |
| debsecan | `debsecan --suite "$(. /etc/os-release; echo $VERSION_CODENAME)" --format detail` | Debian tracker data; for Ubuntu use `security-updates` |

## Is ClamAV keeping itself current?

```bash
systemctl status clamav-freshclam --no-pager | head -5
clamscan --version                        # last field = signature date
sudo tail -20 /var/log/clamav/freshclam.log
```

- Service inactive → `sudo systemctl enable --now clamav-freshclam`.
- `ERROR: ... 429` / "rate limited" / "cool-down" in the log → the ClamAV CDN is
  throttling this IP (often from running `freshclam` too often, or many hosts behind
  one NAT). Wait out the cool-down shown in the log; don't loop retries.
- The service checks 24 times a day by default (`Checks 24` in
  `/etc/clamav/freshclam.conf`); nothing else is needed.

## rkhunter `--update` fails

Ubuntu disables rkhunter's updater by default. Fix once:

```bash
sudo sed -i -E 's/^#?UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/; s/^#?MIRRORS_MODE=.*/MIRRORS_MODE=0/; s|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf
```

## Never do here

- `rkhunter --propupd` (re-baselines file properties; masks real changes). It is the
  right step only *after* reviewing warnings caused by a known package upgrade, and
  only when the user says so.
- Promoting a new AIDE database (`aide --update` + moving `aide.db.new`). Same reason.

## Scripts

`av-update.sh` is in this plugin's `scripts/` directory:
`SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"`. If `CLAUDE_PLUGIN_ROOT` is unset, clone
`https://github.com/danielrosehill/Ubuntu-Security` (e.g. to
`~/.local/share/ubuntu-security-skills`) and use its `scripts/`.
