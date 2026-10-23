---
name: firewall-setup
description: First-time ufw setup on an Ubuntu desktop or server — install if missing, set default policies (deny incoming, allow outgoing), low logging, add narrow allows only for services the user actually runs (SSH first on a remote box, then e.g. mDNS, KDE Connect, Syncthing, Samba, CUPS on a desktop, or HTTP/HTTPS on a web server), enable, verify, and save a baseline. Use when the user says "set up ufw", "enable the firewall", "configure a firewall on this machine", "first-time firewall setup", or when firewall-status finds ufw missing or inactive and the user wants it on.
---

# First-time ufw setup

A sensible default that doesn't surprise the user: deny unsolicited inbound, allow
outbound, and keep reachable only what they actually use. If ufw is already active
with rules, this is not a first-time setup: report the current state
(`firewall-status`) and use `firewall-allow` / `firewall-remove` instead.

## 1. Pre-flight

```bash
command -v ufw || sudo apt install -y ufw
sudo ufw status verbose
systemctl is-active firewalld 2>/dev/null       # if active: stop here and ask; don't run two front-ends
echo "${SSH_CONNECTION:-local session}"         # remote? first field is the client IP
sudo ss -tulnpH | awk '$5 !~ /^(127\.|\[::1\])/' # what is listening beyond localhost
```

Decide the profile: **desktop/laptop** or **server**, and **local** or **remote
(SSH) session**.

## 2. Pick the allows (ask; don't open what isn't running)

Cross-reference listening sockets with this list and confirm each with the user.
Scope defaults to the LAN CIDR (derive it: `ip -4 -o addr show scope global`).

| Service | Rule (prefer the app profile when it exists) | Typical on |
| --- | --- | --- |
| SSH | `allow OpenSSH` or `allow from <lan-cidr> to any app OpenSSH` | servers; desktops only if sshd runs |
| mDNS / Avahi (printer, Chromecast discovery) | `allow from <lan-cidr> to any port 5353 proto udp` | desktop |
| KDE Connect / GSConnect | `allow from <lan-cidr> to any app KDEConnect` (or `1714:1764` tcp+udp) | desktop |
| Syncthing | `allow from <lan-cidr> to any app syncthing` (22000 tcp+udp, 21027 udp) | either |
| Samba file sharing | `allow from <lan-cidr> to any app Samba` | either |
| CUPS printer sharing | `allow from <lan-cidr> to any app CUPS` | desktop sharing a printer |
| HTTP / HTTPS | `allow 'Nginx Full'` / `allow 'Apache Full'` / `allow 80,443/tcp` | web server (usually public) |

Always add `comment '<purpose> <scope>'`.

## 3. Apply

```bash
# only if the user wants to wipe existing (inactive) rules: destructive
# sudo ufw --force reset

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw logging low            # blocked packets only, rate-limited; enough for firewall-diagnose

# REMOTE SSH SESSION: allow SSH BEFORE enabling, or the session is cut.
sudo ufw allow OpenSSH comment 'ssh'
# custom sshd port? check `sudo sshd -T | grep -i ^port` and on 22.10+ `systemctl cat ssh.socket`
# sudo ufw allow 2222/tcp comment 'ssh custom port'

# the opt-in allows the user picked, e.g.
sudo ufw allow from <lan-cidr> to any app KDEConnect comment 'KDE Connect LAN'

sudo ufw --force enable
sudo ufw status verbose
```

Server notes:
- On an internet-facing server, `sudo ufw limit OpenSSH` instead of `allow` throttles
  brute-force attempts (6 new connections / 30 s per source). Use it only if the
  user wants it; `fail2ban` is the alternative.
- On a cloud VM, the provider's security group / firewall sits in front; both must
  allow a port. Mention this if the user expects something to be reachable.
- `/etc/default/ufw` has `IPV6=yes` by default; rules apply to both families.

Desktop notes:
- Don't add SSH if sshd isn't installed/running. Most desktops don't run it.
- Don't add `limit` rules on a desktop.

## 4. Verify from the outside

After enabling, confirm the session survived (remote) and that the allowed services
still work from a client. `sudo journalctl -k -f | grep 'UFW BLOCK'` while the user
tries their usual workflows shows anything still refused → `firewall-allow`.

## 5. Save a baseline

```bash
STATE="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/ubuntu-security/ufw"
mkdir -p "$STATE"
sudo ufw show added > "$STATE/baseline-$(date +%Y-%m-%dT%H%M%S).rules"
```

`firewall-status` diffs against this; `firewall-remove` can reset to it. Never
overwrite a baseline; write a new one if the user wants a new reference point.

## Docker

If Docker is installed, published container ports bypass ufw (see
`firewall-status` §5). Say so once if `docker ps` shows `0.0.0.0:` publishes; don't
change Docker's configuration as part of this skill.

## Undo

`sudo ufw disable` turns filtering off and keeps the rules for later re-enable.
