---
name: av-install
description: Install and initialise malware and rootkit scanning on Ubuntu — the core set (ClamAV engine + clamd daemon + freshclam updater, ClamTk GUI on desktops, rkhunter) and, on request, the advanced layer (Lynis hardening audit, chkrootkit, AIDE file-integrity baseline, debsecan). Detects what is already installed, picks a reports folder, runs the first definitions update and baselines. Use when the user says "install antivirus", "set up clamav", "install rkhunter / lynis / aide / chkrootkit", "set up malware scanning", or when malware-scan finds no scanners installed.
---

# Install scanners

Installation and initialisation only; no scans here (that is `malware-scan`).

## 1. Detect

```bash
. /etc/os-release; echo "$PRETTY_NAME"
for b in clamscan clamdscan freshclam clamtk rkhunter chkrootkit lynis aide debsecan; do
  printf '%-10s %s\n' "$b" "$(command -v $b || echo -)"; done
systemctl is-active clamav-freshclam clamav-daemon 2>/dev/null
echo "${XDG_CURRENT_DESKTOP:-no desktop session}"
```

Report what is present. Don't reinstall what is there; just initialise what isn't.

## 2. Reports folder (one question)

Scan reports are the user's data. Default `~/security-reports/`; confirm or take
their path. Remember the choice in the plugin config:

```bash
CFG_DIR="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/ubuntu-security"
mkdir -p "$CFG_DIR" ~/security-reports
cat > "$CFG_DIR/config.json" <<EOF
{ "reports_dir": "$HOME/security-reports", "configured_at": "$(date -Is)" }
EOF
```

If a previous `linux-av-manager` config exists
(`.../claude-plugins/linux-av-manager/config.json`), reuse its `scans_dir` as
`reports_dir`.

## 3. Core set

| Tool | Package(s) | Role |
| --- | --- | --- |
| ClamAV | `clamav clamav-daemon clamav-freshclam` | signature scanner, daemon for fast scans, auto-updater |
| ClamTk | `clamtk` | GUI front-end (desktops only; skip on servers) |
| rkhunter | `rkhunter` | rootkit / suspicious-file checks |

```bash
sudo apt update
sudo apt install -y clamav clamav-daemon clamav-freshclam rkhunter
sudo apt install -y clamtk            # desktop only
```

Initialise:

```bash
# first signature download; the service holds a lock, so stop it for the manual run
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl enable --now clamav-freshclam clamav-daemon
clamscan --version                    # shows engine + signature date
```

`clamav-daemon` won't start until signatures exist (that's why freshclam goes first).
clamd keeps ~1 GB of signatures in RAM; on small servers (<2 GB RAM) skip the daemon
(`sudo systemctl disable --now clamav-daemon`) and let `malware-scan` use `clamscan`.

rkhunter on Ubuntu ships with updates disabled. Make `--update` work, then baseline:

```bash
sudo sed -i -E 's/^#?UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/; s/^#?MIRRORS_MODE=.*/MIRRORS_MODE=0/; s|^WEB_CMD=.*|WEB_CMD=""|' /etc/rkhunter.conf
sudo rkhunter --update
sudo rkhunter --propupd               # baseline file properties
```

`--propupd` records the current state as "known good". Only run it on a system the
user believes is clean; say so and let them defer.

## 4. Advanced layer (only what the user picks)

| Tool | Package | Role | Post-install |
| --- | --- | --- | --- |
| Lynis | `lynis` | hardening audit with a score | none |
| chkrootkit | `chkrootkit` | second-opinion rootkit checks | none |
| AIDE | `aide` | file-integrity database | `sudo aideinit` (several minutes); creates `/var/lib/aide/aide.db` |
| debsecan | `debsecan` | CVE list for installed packages | reads the **Debian** tracker; on Ubuntu `pro security-status` (see `security-updates`) is the accurate source |

```bash
sudo apt install -y lynis chkrootkit aide     # whichever were picked
sudo aideinit                                 # AIDE only; baseline = current state
```

Ubuntu's `aide` package installs a daily cron/timer (`dailyaidecheck`) that mails
root; mention it so the user isn't surprised. The Ubuntu `lynis` package lags
upstream; that's fine for auditing.

## 5. Confirm

One status line per tool: installed version, service state, signature date (ClamAV),
baseline created (rkhunter / AIDE). Then point to `malware-scan` (run now) or
`scan-schedule` (periodic).
