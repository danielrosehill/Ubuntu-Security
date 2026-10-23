---
name: firewall-allow
description: Add a scoped firewall exemption with ufw on an Ubuntu desktop or server — open a port, port range or app profile (OpenSSH, CUPS, KDE Connect, Samba, Syncthing...) to the LAN, a VPN interface, one host, or anywhere, with a comment, without duplicating existing rules, and verify it actually took effect. Use when the user says "open port X", "allow <service> through the firewall", "add a firewall exemption", "let my phone/printer/other machine connect", "unblock <port>", or when another skill finds ufw blocking something it needs.
---

# Add a firewall exemption

The user's instruction to open something is the approval. Do it, then say in one
line what was opened and to whom.

## 1. Decide the scope (narrowest that works)

| Scope | Use for | Rule form |
| --- | --- | --- |
| LAN | home/office devices: phone, desktop, printer, NAS | `from <lan-cidr>` |
| VPN / overlay | the same devices over a VPN (`tailscale0`, `wg0`, ...) | `in on <iface>` |
| One host | a single known machine | `from <ip>` |
| Anywhere | only when the user says "public" / "from anywhere", or the service is meant to be internet-facing (a web server on a VPS) | no `from` |

When the user doesn't say, use **LAN** (plus the VPN interface if one is up and they
use it). Derive the LAN CIDR from the interface rather than assuming it:

```bash
ip -4 -o addr show scope global | awk '$2 !~ /^(docker|virbr|br-|veth|lxd|tailscale|wg)/ {print $2, $4}'
```

Turn the host address into the network form (`192.168.1.37/24` → `192.168.1.0/24`).
If the machine has several LAN interfaces, ask which one. On a cloud server there is
usually no meaningful "LAN"; ask whether the source is one IP or anywhere.

## 2. Prefer an app profile

```bash
sudo ufw app list
sudo ufw app info '<Profile>'      # shows the ports it covers
```

Profiles come from `/etc/ufw/applications.d/` (installed by packages:
`openssh-server` → `OpenSSH`, `cups` → `CUPS`, `samba` → `Samba`, `kdeconnect` →
`KDEConnect`, `nginx` → `Nginx Full`/`Nginx HTTP`/`Nginx HTTPS`, `apache2` →
`Apache Full`...). If a profile matches the service, use it: the rule then documents
itself.

## 3. Don't duplicate

```bash
sudo ufw status numbered | grep -E '<port>|<Profile>'
```

If an equivalent or broader rule already exists, say so and stop. If a `DENY`/`REJECT`
rule for the same port sits above where the new allow would go, the allow will never
match — see step 4's `insert`.

## 4. Add it

```bash
# app profile
sudo ufw allow from <lan-cidr> to any app OpenSSH comment 'ssh LAN'
sudo ufw allow in on tailscale0 to any app KDEConnect comment 'KDE Connect VPN'

# port / range (always give proto; a bare port opens both tcp and udp)
sudo ufw allow from <lan-cidr> to any port 8000 proto tcp comment 'dev server LAN'
sudo ufw allow from <lan-cidr> to any port 1714:1764 proto udp comment 'KDE Connect LAN'

# one host
sudo ufw allow from <ip> to any port 22 proto tcp comment 'ssh from workstation'

# anywhere (only when asked)
sudo ufw allow 443/tcp comment 'https public'

# must beat an existing deny: insert at a position (1 = top)
sudo ufw insert 1 allow from <ip> to any port 5432 proto tcp comment 'postgres from app host'
```

Syntax traps:

- A port **range** needs `proto`.
- `to any app X` can't be combined with `port`.
- `comment` goes last.
- `insert N` uses the numbers from `status numbered`, where the v4 rules come first
  and the `(v6)` rules after them. A rule with an IPv6 source must be inserted at a
  number inside the v6 block (otherwise `ERROR: Invalid position`). To put a rule at
  the very top of both lists, use `sudo ufw prepend <rule>` (ufw 0.36+).
- A rule that already exists prints `Skipping adding existing rule` and changes nothing.
- `ufw limit` (rate-limit, 6 connections / 30 s per source) is for internet-facing SSH
  on servers; only use it when asked.

If ufw is **inactive**, adding a rule stores it but filters nothing. Say so; don't
enable ufw as a side effect (on a remote box that could cut the session) — route to
`firewall-setup`.

## 5. Verify the effect, not just the rule

```bash
sudo ufw status numbered | tail -n +4
```

Then check the service itself: blocks for that port should stop appearing
(`sudo journalctl -k -f | grep "DPT=<port>"`, or `ufw-blocks.sh --port <port>` from
`firewall-diagnose`), and the client should connect. A rule that is listed but has no
effect usually means a `deny` rule ahead of it (first match wins), traffic arriving
on a different interface than the rule names, the service listening only on
`127.0.0.1`, or the service not running at all. `firewall-diagnose` covers these.

## Docker note

Ports published by Docker (`-p 8080:80`) bypass ufw entirely; a ufw allow rule is
neither needed nor effective for them, and a ufw deny won't block them. To restrict a
published container port, publish it on a specific address
(`-p 127.0.0.1:8080:80` or `-p <lan-ip>:8080:80`), or add rules to Docker's
`DOCKER-USER` chain. Say this when the port the user names belongs to a container.

## Not this skill

- Removing or tightening rules → `firewall-remove`.
- First-time ufw setup on a fresh machine → `firewall-setup`.
  **Allow SSH before enabling ufw on a remote box**, or the session is cut.
