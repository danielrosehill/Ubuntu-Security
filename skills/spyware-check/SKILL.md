---
name: spyware-check
description: Look for spyware, unwanted telemetry and suspicious software on an Ubuntu machine — installed packages, snaps, flatpaks and /opt software from unknown origins, telemetry and crash-reporting services (apport, whoopsie, popularity-contest, ubuntu-report, vendor agents), unexpected outbound connections and the processes behind them, autostart entries, and browser extensions with broad permissions. Reports what is present and what it sends; removes or disables only what the user picks. Use when the user says "check for spyware", "is anything phoning home", "what telemetry is running", "audit installed software for privacy", "suspicious outbound connections", or "check my browser extensions".
---

# Spyware and telemetry check

Report what is present, where it came from, and what it talks to. Removal and
opt-outs only for the items the user chooses.

## 1. Where software came from

```bash
apt-mark showmanual | wc -l
grep -rhE '^(deb|Types|URIs)' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | sort -u   # third-party repos
apt list --installed 2>/dev/null | grep -F '[installed,local]'         # .debs installed by hand, in no repo
ls /var/lib/apt/lists/ | grep '_Packages$' | cut -d_ -f1 | sort -u | grep -vE 'ubuntu\.com$|canonical\.com$'   # third-party repo hosts
snap list 2>/dev/null
flatpak list --app --columns=application,origin 2>/dev/null
ls -1 /opt /usr/local/bin 2>/dev/null
```

Simpler origin view: `apt-cache policy <pkg>` shows the repo for one package.
Software in `/opt` or `/usr/local` is outside the package manager; name the vendor
and how it updates itself.

## 2. Telemetry and crash reporting (Ubuntu)

| Component | Check | What it sends | Opt out |
| --- | --- | --- | --- |
| apport (crash reports) | `systemctl is-enabled apport` | crash dumps, on user confirmation | `sudo systemctl disable --now apport`; `/etc/default/apport` `enabled=0` |
| whoopsie (error tracker) | `systemctl is-active whoopsie` | crash metadata to errors.ubuntu.com | `sudo systemctl disable --now whoopsie` |
| popularity-contest | `dpkg -l popularity-contest` | installed package list, weekly | `sudo apt purge popularity-contest` |
| ubuntu-report / ubuntu-insights | `ls ~/.cache/ubuntu-report ~/.config/ubuntu-insights 2>/dev/null` | install-time hardware info, opt-in | `ubuntu-report -f send no` / `ubuntu-insights consent -s false` |
| motd-news | `grep ENABLED /etc/default/motd-news` | fetches news, sends release + uptime-ish UA | `ENABLED=0` |
| snapd | always contacts the Snap Store for refreshes | device + snap revisions | inherent to snaps |
| VS Code, Chrome, vendor apps | app settings | usage telemetry | in-app setting (`telemetry.telemetryLevel: off` for VS Code) |

Report state; only change what the user asks.

## 3. Who is talking to whom

```bash
sudo ss -tupnH state established | awk '{print $NF, $(NF-1)}' | sort | uniq -c | sort -rn | head -30
```

For unfamiliar remote addresses: `getent hosts <ip>` / `dig -x <ip> +short`, and
`whois <ip> | grep -iE 'orgname|org-name|netname'`. Map each to its process and
package (`ps -o pid,user,cmd -p <pid>`, `dpkg -S $(readlink -f /proc/<pid>/exe)`).
Flag: processes not owned by any package, binaries running from `/tmp`, `/dev/shm`,
or a hidden directory, and connections to unusual ports from processes that have no
reason to make them. For a longer view, `sudo nethogs` or
`sudo tcpdump -ni any -c 200 'not port 22'` (only if the user wants a capture).

## 4. Autostart and persistence

```bash
ls ~/.config/autostart /etc/xdg/autostart 2>/dev/null
systemctl list-unit-files --state=enabled --no-pager | grep -vE '^(systemd|dbus|getty|snap\.)' | head -50
systemctl --user list-unit-files --state=enabled --no-pager 2>/dev/null
crontab -l 2>/dev/null; sudo ls /etc/cron.d /var/spool/cron/crontabs 2>/dev/null
grep -lE 'curl|wget|nc |base64' ~/.bashrc ~/.profile ~/.bash_profile 2>/dev/null
```

Unknown services, user units and cron entries that fetch-and-run from the network are
the ones to name.

## 5. Browser extensions

```bash
# Firefox (deb or snap profile paths)
for f in ~/.mozilla/firefox/*/extensions.json ~/snap/firefox/common/.mozilla/firefox/*/extensions.json; do
  [ -f "$f" ] && jq -r '.addons[] | select(.type=="extension") | [.defaultLocale.name, .id, .active, (.userPermissions.permissions // [] | join(","))] | @tsv' "$f"
done
# Chrome / Chromium / Brave: one folder per extension id, manifest.json has name + permissions
for d in ~/.config/google-chrome/*/Extensions ~/.config/chromium/*/Extensions ~/snap/chromium/common/chromium/*/Extensions ~/.config/BraveSoftware/Brave-Browser/*/Extensions; do
  [ -d "$d" ] && for m in "$d"/*/*/manifest.json; do jq -r '[.name, (.permissions // [] | join(",")), (.host_permissions // [] | join(","))] | @tsv' "$m"; done
done 2>/dev/null
```

Names starting with `__MSG_` are localised; read them from `_locales/en/messages.json`.
Flag extensions with `<all_urls>`, `*://*/*`, `webRequest`, `cookies`, `history`,
`nativeMessaging`, and ones the user doesn't recognise.

## Report

Sections: unknown-origin software, telemetry components (on/off), notable outbound
connections (process → destination org), autostart oddities, broad-permission
extensions. Each item: what, where it came from, evidence. Then ask which to remove
or disable. Pair with `malware-scan` if anything looks actively malicious.
