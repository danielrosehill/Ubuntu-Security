# ubuntu-security

Agent skills for host security on **Ubuntu desktops and servers**: the ufw firewall,
malware / rootkit / integrity scanning, read-only security audits, SSH, and hardware
authentication. Each skill is a `SKILL.md` with working commands; where desktop and
server differ (or a remote SSH session needs care) the skill says so.

Skills report facts and do what is asked. Audit skills list findings because that is
what an audit is for; the others don't add unrequested hardening advice.

Written for Ubuntu 22.04 and later (scripts exercised on 26.04 with ufw 0.36 and OpenSSH 10). Most commands also
work on Debian; Ubuntu-only bits (`pro`, `ssh.socket` activation, Ubuntu package
defaults) are called out.

## Skills

### Firewall (ufw)

| Skill | What it does |
| --- | --- |
| `firewall-setup` | First-time ufw setup: defaults, low logging, opt-in allows for services that actually run (SSH first on remote boxes), enable, save a baseline |
| `firewall-status` | Read-only probe: active?, policies, numbered rules, listening-vs-allowed table, recent blocks, Docker holes; optional snapshot diff and permissiveness review |
| `firewall-allow` | Add a scoped exemption (LAN / VPN interface / one host / anywhere), app profiles preferred, no duplicates, verify the effect |
| `firewall-remove` | Delete by spec or number (highest first, ufw renumbers), tighten broad rules, dedupe, reset to baseline; confirms before deleting anything not just added |
| `firewall-diagnose` | "Is the firewall blocking X?": UFW BLOCK lines from `journalctl -k` / `/var/log/ufw.log`, logging check, first-match order, interface / source / IPv6 / protocol mismatch, Docker bypass |

### Malware, rootkits, integrity

| Skill | What it does |
| --- | --- |
| `av-install` | Install + initialise ClamAV (engine, clamd, freshclam), ClamTk, rkhunter; optional Lynis, chkrootkit, AIDE, debsecan; pick the reports folder |
| `av-update-definitions` | Refresh signatures for every installed scanner; diagnose stale ClamAV signatures; never re-baselines |
| `malware-scan` | Quick / path / deep scans, per-tool reports + summary, known false positives; never quarantines |
| `scan-schedule` | systemd timers (cron fallback) for definitions and scans; failed-unit signal on servers, desktop notifications on desktops |

### Audits and checks

| Skill | What it does |
| --- | --- |
| `security-audit` | Read-only host audit (updates, exposure, SSH, accounts, permissions, SUID, AppArmor, scanners, encryption, desktop items) written up with severities |
| `security-updates` | Pending `-security` upgrades, `pro security-status`, CVE/USN fixed?, unattended-upgrades working?, reboot needed? |
| `spyware-check` | Unknown-origin software, Ubuntu telemetry components, outbound connections by process, autostart entries, browser extension permissions |
| `tls-cert-check` | certbot certificates and renewal, certs referenced by services, what live endpoints serve, expiring within 30 days |

### Authentication and SSH

| Skill | What it does |
| --- | --- |
| `ssh-keys` | Inventory, generate (ed25519 / ed25519-sk), `ssh-copy-id` to other hosts, review `authorized_keys`, permissions, retire keys |
| `ssh-server-config` | Effective `sshd -T` config, drop-in precedence, socket-activated port changes, recent logins; safe changes with a kept-open session |
| `fail2ban` | Install with an sshd jail on the journal, ignore LAN/VPN, list bans, unban, ufw interaction |
| `yubikey-setup` | FIDO2/U2F key detection, `pam_u2f` for sudo / login / lock screen, FIDO2 SSH keys, with lockout protection |
| `fingerprint-setup` | libfprint support check, enroll, `pam-auth-update --enable fprintd`, troubleshooting |

## Scripts

`scripts/` holds helpers the skills call:

| Script | Used by | Notes |
| --- | --- | --- |
| `ufw-blocks.sh` | `firewall-status`, `firewall-diagnose` | Summarise UFW log lines by action / interface / source / proto / port; filters `--port --src --since --file --raw`. Read-only |
| `av-update.sh` | `av-update-definitions`, `scan-schedule` | Refresh installed scanners; run with sudo |
| `av-scan.sh` | `malware-scan`, `scan-schedule` | Run scanners, write reports; exit 0 clean / 1 review / 2 error; optional `--notify-user`. Run with sudo |
| `posture-facts.sh` | `security-audit` | Collect read-only facts by section; run with sudo |

Skills find them at `${CLAUDE_PLUGIN_ROOT}/scripts`. When a skill is loaded on its own
and that variable is unset, clone this repository and use its copy:

```bash
git clone --depth 1 https://github.com/danielrosehill/Ubuntu-Security ~/.local/share/ubuntu-security-skills
SCRIPTS=~/.local/share/ubuntu-security-skills/scripts
```

## State and reports

- Plugin state (config, ufw baselines and snapshots):
  `${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/ubuntu-security/`
  — `config.json` holds `reports_dir`; `ufw/` holds `baseline-*.rules` and
  `snapshot-*.rules` (`ufw show added` format).
- Scan and audit reports are the user's data: `reports_dir`, default
  `~/security-reports/` (`<tool>/<timestamp>.txt`, `_summary/`, `audit/`).

## Supersedes

This plugin replaces two older plugins and the security commands of two Linux
management plugins. Nothing was deleted from those repositories; they are superseded.

| Old plugin | Status |
| --- | --- |
| `linux-av-manager` (`Claude-Linux-AV-Manager-Plugin`) | Fully replaced |
| `security-checkup` (`Claude-Security-Checkup-Plugin`) | Linux host items replaced; web / appliance audits dropped (below) |
| `linux-desktop-mgmt` | Security, firewall, AV and auth commands moved here; the rest goes to `ubuntu-admin` |
| `linux-server-mgmt` | `seurity/*` commands and the security-auditor agent moved here; the rest goes to `ubuntu-admin` |

### Old → new

| Old | New |
| --- | --- |
| `linux-av-manager:onboard` | `av-install` (reports folder + detection) |
| `linux-av-manager:install-core` | `av-install` |
| `linux-av-manager:install-advanced` | `av-install` (advanced layer) |
| `linux-av-manager:update-definitions` | `av-update-definitions` |
| `linux-av-manager:scan` | `malware-scan` |
| `linux-av-manager:schedule` | `scan-schedule` |
| `linux-av-manager:ufw-setup` | `firewall-setup` |
| `linux-av-manager:ufw-maintain` | show / audit / diff → `firewall-status`; add → `firewall-allow`; remove / dedupe / reset → `firewall-remove` |
| `security-checkup:audits/security-audit`, `audits/security-auditor`, `audits/linux-server-audit`, `audits/linux-desktop-audit`, `audits/write-audit`, `audits/security-audits-write-audit`, `audits/security-audits-probe-vulnerabilities` | `security-audit` |
| `security-checkup:system-security/security-posture-check` (+ duplicate) | `security-audit` |
| `security-checkup:system-security/security-detect-spyware` | `spyware-check` |
| `security-checkup:firewall/firewall-check`, `firewall/analyze-firewall`, `firewall/security-firewall-analyze-firewall` | `firewall-status` (rule review); hardening findings → `security-audit` |
| `security-checkup:authentication/manage-ssh-keys` | `ssh-keys` |
| `security-checkup:authentication/security-auth-yubi-setup` | `yubikey-setup` |
| `security-checkup:authentication/security-auth-fingerprint-scanner` (was empty) | `fingerprint-setup` |
| `linux-desktop-mgmt:analyze-firewall`, `security-firewall-analyze-firewall` | `firewall-status` |
| `linux-desktop-mgmt:install-clamav`, `security-av-install-clamav` | `av-install` |
| `linux-desktop-mgmt:detect-spyware`, `security-detect-spyware` | `spyware-check` |
| `linux-desktop-mgmt:probe-vulnerabilities`, `security-audits-probe-vulnerabilities`, `write-audit`, `security-audits-write-audit`, `security-posture-check`, `security-posture-diagnostics-security-posture-check` | `security-audit` |
| `linux-desktop-mgmt:yubi-setup`, `security-auth-yubi-setup` | `yubikey-setup` |
| `linux-desktop-mgmt:fingerprint-scanner`, `security-auth-fingerprint-scanner` (both empty) | `fingerprint-setup` |
| `linux-desktop-mgmt:manage-ssh-keys`, `configuration-ssh-manage-ssh-keys` | `ssh-keys` |
| `linux-desktop-mgmt:lan-ssh-setup`, `network-lan-lan-ssh-setup` | `ssh-keys` (copy keys to other machines) |
| `linux-server-mgmt:seurity/security-audit`, `agents/security/security-auditor` | `security-audit` |
| `linux-server-mgmt:seurity/firewall-check` | `firewall-status` |
| `linux-server-mgmt:seurity/certificate-check` | `tls-cert-check` |
| `linux-server-mgmt:networking/configuration-ssh-manage-ssh-keys` | `ssh-keys` |

New, with no direct predecessor: `firewall-diagnose`, `firewall-remove` (split out of
`ufw-maintain`), `security-updates`, `ssh-server-config`, `fail2ban`.

### Dropped (not Linux host security)

| Old | Why |
| --- | --- |
| `security-checkup:audits/seo-audit` | Website SEO, not security |
| `security-checkup:audits/responsive-audit` | Website responsive design, not security |
| `security-checkup:web/static-site-hardening` | Web codebase review, not host security |
| `security-checkup:audits/home-assistant-audit` | Application-specific (Home Assistant), not the Ubuntu host |
| `security-checkup:audits/opnsense-audit` | Network appliance (OPNsense/FreeBSD), not an Ubuntu host |
| `security-checkup:audits/cloudflare-tunnel-proxy-audit` | Third-party service configuration, not host security |
| `security-checkup:audits/firewall-audit` | Dedicated firewall appliances; host firewalls are covered by the firewall skills |

## License

MIT — see [LICENSE](LICENSE).
