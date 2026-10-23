#!/usr/bin/env bash
# posture-facts.sh - collect read-only security facts about an Ubuntu host, as
# plain text sections, for the security-audit skill to interpret. Changes nothing.
#
# Usage: sudo posture-facts.sh [--section NAME]... > facts.txt
#   Sections: os updates firewall exposure ssh accounts authlog perms mac tools
#             crypto desktop   (default: all)
set -uo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo (reads /etc/shadow, sshd -T, journal)" >&2; exit 2; }

user="${SUDO_USER:-root}"
home="$(getent passwd "$user" | cut -d: -f6)"
want=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --section) want+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
on() { [[ ${#want[@]} -eq 0 ]] && return 0; local s; for s in "${want[@]}"; do [[ $s == "$1" ]] && return 0; done; return 1; }
have() { command -v "$1" >/dev/null 2>&1; }
hdr() { printf '\n===== %s =====\n' "$1"; }
run() { printf -- '--- %s\n' "$*"; "$@" 2>&1 || true; }
sh_() { printf -- '--- %s\n' "$1"; bash -c "$1" 2>&1 || true; }

if on os; then
  hdr os
  sh_ '. /etc/os-release; echo "$PRETTY_NAME"'
  run uname -r
  sh_ 'hostnamectl 2>/dev/null | grep -E "Chassis|Virtualization|Operating"'
  sh_ 'systemctl get-default'
  run uptime -p
fi

if on updates; then
  hdr updates
  sh_ 'apt list --upgradable 2>/dev/null | grep -- "-security" | wc -l | sed "s/^/pending security upgrades: /"'
  sh_ 'apt list --upgradable 2>/dev/null | grep -- "-security" | head -30'
  have pro && sh_ 'pro security-status 2>/dev/null | head -25'
  sh_ '[ -f /var/run/reboot-required ] && { echo "REBOOT REQUIRED"; cat /var/run/reboot-required.pkgs 2>/dev/null; } || echo "no reboot required"'
  sh_ 'dpkg-query -W -f="\${Status}\n" unattended-upgrades 2>/dev/null | grep -q "install ok installed" && echo "unattended-upgrades installed" || echo "unattended-upgrades NOT installed"'
  sh_ 'apt-config dump | grep -E "^APT::Periodic::(Update-Package-Lists|Unattended-Upgrade) "'
  sh_ 'ls -l --time-style=long-iso /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null; tail -3 /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null'
  have canonical-livepatch && sh_ 'canonical-livepatch status 2>/dev/null | head -10'
fi

if on firewall; then
  hdr firewall
  if have ufw; then run ufw status verbose; else echo "ufw not installed"; fi
  have firewall-cmd && sh_ 'firewall-cmd --state; firewall-cmd --list-all'
  sh_ 'nft list ruleset 2>/dev/null | grep -cE "^\s*table" | sed "s/^/nftables tables: /"'
  sh_ 'nft list tables 2>/dev/null'
fi

if on exposure; then
  hdr exposure
  sh_ 'ss -tulnpH | awk '"'"'$5 !~ /^(127\.|\[::1\]|::1)/'"'"''
  have docker && sh_ 'docker ps --format "{{.Names}}\t{{.Ports}}" 2>/dev/null | grep -E "0\.0\.0\.0|\[::\]|:::" '
fi

if on ssh; then
  hdr ssh
  sh_ 'systemctl is-active ssh.service ssh.socket 2>/dev/null | paste -sd" " | sed "s/^/ssh.service ssh.socket: /"'
  if have sshd; then
    sh_ 'sshd -T 2>/dev/null | grep -Ei "^(port|listenaddress|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitemptypasswords|authenticationmethods|allowusers|allowgroups|denyusers|x11forwarding|maxauthtries|usepam) "'
  else echo "openssh-server not installed"; fi
  have fail2ban-client && sh_ 'fail2ban-client status 2>/dev/null'
fi

if on accounts; then
  hdr accounts
  sh_ 'awk -F: '"'"'$3==0{print "uid0:", $1}'"'"' /etc/passwd'
  sh_ 'awk -F: '"'"'$7 !~ /(nologin|false|sync|halt|shutdown)$/ {print "login shell:", $1, $3, $7}'"'"' /etc/passwd'
  sh_ 'getent group sudo admin wheel'
  sh_ 'awk -F: '"'"'($2==""){print "EMPTY PASSWORD:", $1}'"'"' /etc/shadow'
  sh_ 'grep -rhE "^[^#].*NOPASSWD" /etc/sudoers /etc/sudoers.d 2>/dev/null | sed "s/^/NOPASSWD: /"'
fi

if on authlog; then
  hdr authlog
  sh_ 'journalctl --since "-7d" --no-pager -u ssh 2>/dev/null | grep -cE "Failed password|Invalid user" | sed "s/^/sshd failed auth lines (7d): /"'
  sh_ 'journalctl --since "-7d" --no-pager -u ssh 2>/dev/null | grep -oE "(Failed password|Invalid user).* from [0-9a-f.:]+" | grep -oE "[0-9a-f.:]+$" | sort | uniq -c | sort -rn | head -10'
  sh_ 'journalctl --since "-7d" --no-pager -u ssh 2>/dev/null | grep -E "Accepted (publickey|password|keyboard)" | tail -10'
  sh_ 'journalctl --since "-7d" --no-pager _COMM=sudo 2>/dev/null | grep -E "authentication failure|incorrect password|NOT in sudoers" | tail -10'
fi

if on perms; then
  hdr perms
  sh_ 'stat -c "%A %U:%G %n" /etc/passwd /etc/shadow /etc/gshadow /etc/sudoers /etc/ssh/sshd_config 2>/dev/null'
  sh_ "stat -c '%A %U:%G %n' '$home' '$home/.ssh' '$home'/.ssh/* 2>/dev/null"
  sh_ 'find /etc /usr /var -xdev -type f -perm -0002 2>/dev/null | grep -vE "^/var/(tmp|crash)" | head -30 | sed "s/^/world-writable: /"'
  # Container image layers (docker/containerd/podman/lxd) carry their own SUID copies; skip them.
  sh_ 'find / -xdev \( -path /var/lib/docker -o -path /var/lib/containerd -o -path /var/lib/containers -o -path /var/lib/lxd -o -path /var/snap -o -path "/home/*/.local/share/containers" \) -prune -o -type f \( -perm -4000 -o -perm -2000 \) -print 2>/dev/null | while read -r f; do dpkg -S "$f" >/dev/null 2>&1 || echo "SUID/SGID not from a package: $f"; done'
  sh_ 'find /home /root -maxdepth 1 -type d -perm -0007 2>/dev/null | sed "s/^/world-accessible home: /"'
fi

if on mac; then
  hdr mac
  have aa-status && sh_ 'aa-status 2>/dev/null | head -8' || echo "apparmor utils not installed"
fi

if on tools; then
  hdr tools
  for b in clamscan clamdscan freshclam rkhunter chkrootkit lynis aide debsecan fail2ban-client auditctl; do
    printf '%-16s %s\n' "$b" "$(command -v "$b" || echo -)"
  done
  sh_ 'for u in clamav-freshclam clamav-daemon fail2ban auditd apparmor; do printf "%-18s %s\n" "$u" "$(systemctl is-active $u 2>/dev/null)"; done'
  sh_ 'ls -l --time-style=long-iso /var/lib/clamav/*.c[lv]d 2>/dev/null'
  sh_ 'systemctl list-timers --all --no-pager 2>/dev/null | grep -Ei "clam|rkhunter|lynis|aide|ubuntu-security"'
fi

if on crypto; then
  hdr crypto
  sh_ 'lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINTS 2>/dev/null | grep -E "crypt|LUKS" || echo "no dm-crypt / LUKS devices found"'
  have mokutil && sh_ 'mokutil --sb-state 2>/dev/null'
  sh_ 'swapon --show 2>/dev/null'
fi

if on desktop; then
  hdr desktop
  sid="$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$user" '$3==u{print $1; exit}')"
  if [[ -n "$sid" ]]; then
    sh_ "loginctl show-session $sid -p Type -p Desktop -p Remote"
    uid="$(id -u "$user")"
    run runuser -u "$user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" gsettings get org.gnome.desktop.screensaver lock-enabled
    for k in kreadconfig6 kreadconfig5; do
      have $k && { run runuser -u "$user" -- $k --file kscreenlockerrc --group Daemon --key Autolock; break; }
    done
  else
    echo "no graphical session for $user (server, or not logged in)"
  fi
  sh_ 'systemctl is-active bluetooth 2>/dev/null | sed "s/^/bluetooth: /"'
  sh_ 'systemctl is-active avahi-daemon cups-browsed 2>/dev/null | paste -sd" " | sed "s/^/avahi-daemon cups-browsed: /"'
fi
