---
name: security-updates
description: Check the security-patch state of an Ubuntu host — pending upgrades from the -security pocket, Ubuntu Pro / ESM coverage via `pro security-status`, whether a specific CVE or USN is fixed, whether unattended-upgrades is actually running and when it last applied something, and whether a reboot or service restart is needed to load patched code. Read-only unless the user asks to apply the security updates. Use when the user asks "are there security updates", "is this machine patched", "am I affected by CVE-XXXX", "is unattended-upgrades working", "do I need to reboot", or "apply security updates only".
---

# Security updates

Read-only by default. Configuring the auto-update *policy* (which origins, auto-reboot
windows) is general package management, not covered here.

## 1. What is pending

```bash
sudo apt update -qq
apt list --upgradable 2>/dev/null | grep -- '-security'        # security pocket only
apt list --upgradable 2>/dev/null | grep -vc -- '-security'     # other pending upgrades (count)
```

Ubuntu-specific: `pro` (package `ubuntu-pro-client`, preinstalled) knows which
packages come from main/universe and whether ESM covers them:

```bash
pro security-status                   # summary: packages from main, universe, third-party, ESM coverage
pro security-status --esm-apps        # universe packages with fixes only available via ESM
pro status                            # attached? esm-infra / esm-apps / livepatch enabled?
```

Universe packages receive security fixes through `esm-apps` (Ubuntu Pro, free for
personal use on a few machines). If `pro security-status` shows fixes "available with
esm-apps", that is a fact to report, not a sales pitch.

## 2. Is a specific CVE / USN fixed?

```bash
pro fix CVE-2024-6387 --dry-run       # or USN-6859-1; says fixed / not affected / needs action
```

Without `pro`: find the package, compare the installed version with the fixed version
on `https://ubuntu.com/security/<CVE-ID>`:

```bash
dpkg -l <package> | tail -1
apt changelog <package> 2>/dev/null | grep -m3 -i <CVE-ID>
```

## 3. Is unattended-upgrades working?

```bash
apt-config dump | grep -E '^APT::Periodic::(Update-Package-Lists|Unattended-Upgrade) '   # want "1"
systemctl is-enabled unattended-upgrades apt-daily.timer apt-daily-upgrade.timer
systemctl list-timers apt-daily-upgrade.timer --no-pager
sudo tail -20 /var/log/unattended-upgrades/unattended-upgrades.log
grep -h ' install \| upgrade ' /var/log/dpkg.log | tail -5
```

"Working" = the timer ran recently and the log shows packages installed (or "No
packages found that can be upgraded unattended"). Common breakages: a held package
(`apt-mark showhold`), a dpkg lock left by a crashed run (`sudo dpkg --audit`),
a third-party repo with an expired key making `apt update` fail, or the machine being
off when the timer fires (desktops; it catches up on next boot).

## 4. Reboot / restart needed?

```bash
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs
uname -r; ls -1 /boot/vmlinuz-* | tail -1          # running vs newest installed kernel
sudo needrestart -b 2>/dev/null                     # services still running old libraries (servers)
canonical-livepatch status 2>/dev/null              # kernel patched live?
```

## 5. Apply security updates only (on request)

```bash
sudo unattended-upgrade -v          # applies whatever the security policy allows, logs as usual
# or, explicit:
sudo apt install --only-upgrade $(apt list --upgradable 2>/dev/null | grep -- '-security' | cut -d/ -f1)
```

On a server, say which services will restart (`needrestart` prompts on Ubuntu
22.04+; `NEEDRESTART_MODE=a` restarts automatically). Don't reboot unless asked.

## Report

One line: N security updates pending (M with a newer kernel), unattended-upgrades
working yes/no (last run date), reboot required yes/no. Then the package list if the
user wants it.
