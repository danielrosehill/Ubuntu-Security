---
name: security-audit
description: Read-only security audit of an Ubuntu desktop or server host — updates and reboot state, firewall and network exposure (including Docker publishes), SSH server config and auth logs, accounts and sudo, file permissions and non-package SUID binaries, AppArmor, installed scanners and their freshness, disk encryption and Secure Boot, and on desktops screen lock and discovery services — written up as a findings report with severities. Does not remediate. Use when the user says "security audit", "audit this machine / server / desktop", "security posture check", "how secure is this box", "probe for vulnerabilities", "write a security audit", or "check my system's security".
---

# Security audit (read-only)

An audit is the one place where findings and recommendations are the point. Still:
report facts, rank them, and do not change anything. Fixes happen afterwards, one at
a time, when the user picks them (hand off to the relevant skill).

## 1. Profile

Desktop/laptop or server? Local or remote? Internet-facing or LAN-only? Ask only if
it isn't obvious from `hostnamectl` (Chassis), a graphical session
(`loginctl list-sessions`), and the public addresses on the interfaces.

## 2. Collect facts

```bash
sudo bash "$SCRIPTS/posture-facts.sh" > /tmp/posture-facts.txt 2>&1
```

Sections: `os updates firewall exposure ssh accounts authlog perms mac tools crypto
desktop`. Run one with `--section <name>` to refresh just that part. The `perms`
section walks the root filesystem and can take a few minutes on large disks; run the
script in the background.

Add as needed:

```bash
sudo ufw status numbered                              # rule-level detail (firewall-status)
pro status 2>/dev/null                                # Ubuntu Pro / ESM / Livepatch entitlements
snap list 2>/dev/null; snap connections 2>/dev/null | grep -E 'home|removable-media|system-files|personal-files'
```

## 3. Assess

Rate each finding **Critical / High / Medium / Low / Info**, using the profile.
Same fact, different severity: password SSH auth on an internet-facing server is
High; on a LAN-only desktop with sshd off it is not a finding at all.

| Area | Look for |
| --- | --- |
| Updates | pending `-security` upgrades (count + notable packages), `REBOOT REQUIRED` with a newer kernel, unattended-upgrades not enabled, last unattended run long ago, Ubuntu release past end of standard support (`pro security-status`) |
| Firewall / exposure | ufw inactive while services listen on `0.0.0.0`/`::`; databases, Redis, Docker API (2375), admin panels reachable beyond localhost; Docker `0.0.0.0` publishes; broad `Anywhere` allows |
| SSH server | `permitrootlogin yes`, `passwordauthentication yes` on internet-facing hosts, `permitemptypasswords yes`, many failed auths from few sources and no fail2ban/limit |
| Accounts | extra uid 0 accounts, empty password hashes, unexpected members of `sudo`, broad `NOPASSWD: ALL` |
| Auth logs | bursts of failed sudo, successful SSH logins from unexpected sources |
| Permissions | world-writable files under `/etc` `/usr` `/var`, `/etc/shadow` not `640 root:shadow`, `~/.ssh` not `700`, private keys not `600`, home dirs world-readable, SUID/SGID binaries not owned by any package (vendor software in `/opt` is common; name the vendor) |
| MAC | AppArmor not loaded |
| Malware tooling | none installed (Info on desktops, depends on policy on servers); ClamAV signatures older than ~3 days; scans never scheduled |
| Encryption | laptop without full-disk encryption (High for portable devices, Info for servers in a locked room); unencrypted swap alongside encrypted root |
| Boot | Secure Boot disabled (Info/Low; note it may be deliberate for unsigned modules) |
| Desktop | screen lock disabled; Bluetooth on; Avahi / cups-browsed on untrusted networks (Info) |

Don't pad the report with generic best practice; every finding cites the fact that
supports it (a command and its output line).

## 4. Write the report

Save to the reports folder (`config.json` → `reports_dir`, default
`~/security-reports/`) as `audit/<YYYY-MM-DD>-<hostname>.md`:

```
# Security audit: <hostname> (<Ubuntu version>, desktop|server) — <date>

## Summary
<one paragraph: overall state, counts per severity>

## Findings
### [High] <title>
Evidence: `<command>` → `<output line>`
Why it matters here: <one or two sentences, specific to this host's profile>
Fix: <one-liner or the skill that does it>

## In place
<protections that are present and working: ufw active with N rules, AppArmor N profiles, unattended-upgrades enabled, ...>

## Not checked
<anything skipped and why (no sudo, section timed out, ...)>
```

In the chat reply, give the summary and the Critical/High items; link the file for
the rest.

## Hand-offs for fixes

Firewall → `firewall-allow` / `firewall-remove` / `firewall-setup`. SSH →
`ssh-server-config`, `fail2ban`. Updates → `security-updates`. Malware tooling →
`av-install`, `scan-schedule`. Keys → `ssh-keys`.

## Scripts

`posture-facts.sh` is in this plugin's `scripts/` directory:
`SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"`. If `CLAUDE_PLUGIN_ROOT` is unset, clone
`https://github.com/danielrosehill/Ubuntu-Security` (e.g. to
`~/.local/share/ubuntu-security-skills`) and use its `scripts/`.
