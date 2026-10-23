---
name: firewall-status
description: Probe the host firewall (ufw, with nftables/iptables/firewalld detection) on an Ubuntu desktop or server and report what is actually reachable — active or not, default policies, logging level, every rule with its number, listening services cross-checked against the rules, recent blocks, holes ufw does not see (Docker-published ports), and optionally a diff against a saved snapshot or a permissiveness review. Read-only. Use when the user says "what's the firewall state", "is ufw on", "what ports are open", "show firewall rules", "probe the firewall", "audit my ufw rules", "has the firewall changed", or before adding or removing any rule.
---

# Firewall status (read-only)

Changes nothing, except writing a snapshot file when asked. Most commands need
`sudo`; if `sudo -n true` fails, ask the user to run them (or to run the session with
sudo available).

## 1. Which firewall is in charge

```bash
command -v ufw && sudo ufw status verbose     # Ubuntu default front-end
systemctl is-active firewalld 2>/dev/null     # if active, ufw should not also be
sudo nft list tables                          # what is really loaded in the kernel
```

Ubuntu ships `ufw` (on top of nftables via `iptables-nft`). Desktops have it
installed but **inactive** by default; cloud server images often have it inactive too
and rely on a provider firewall. If `firewalld` is active, report it and use
`sudo firewall-cmd --list-all` instead; the rest of this skill is ufw-specific.
Tables named `ip filter`/`ip6 filter` with `ufw-*` chains are ufw; `docker`, `ip nat`
with `DOCKER` chains, `tailscale`, `libvirt` / `LIBVIRT_*` belong to those services.

`Status: inactive` → nothing is filtered by ufw; say so first.

## 2. State and rules

```bash
sudo ufw status verbose          # active?, logging level, default in/out/routed policies
sudo ufw status numbered         # rules with the numbers firewall-remove needs
sudo ufw show added              # rules as the commands that created them
sudo ufw app list                # app profiles (OpenSSH, CUPS, KDEConnect, ...)
```

Each IPv4 rule usually has a `(v6)` twin with its own number. Rule order matters:
ufw evaluates its rules **first match wins**, top to bottom.

## 3. Listening vs allowed: the useful view

The rule list alone doesn't say what is exposed. Cross it with what is listening:

```bash
sudo ss -tulnpH | awk '{print $1, $5, $7}' | sort -u
```

For each socket not bound to `127.0.0.1` / `::1` / `127.0.0.53`, decide: **allowed**
(which rule matches its port, from where?) or **blocked** by the default deny.
Report it as a table:

| Port/proto | Process | Bound to | ufw | Allowed from |
| --- | --- | --- | --- | --- |

`systemd-resolved` on `127.0.0.53:53` and `127.0.0.54:53` is local-only; skip it.
On Ubuntu 22.10+ `sshd` is socket-activated, so the listener shows as `systemd` (pid 1)
on port 22 — that is still SSH.

## 4. What is being blocked right now

Use the bundled summariser (see "Scripts" below):

```bash
bash "$SCRIPTS/ufw-blocks.sh" --since "1 hour ago"
```

or by hand:

```bash
sudo journalctl -k --since -1h --no-pager | grep 'UFW BLOCK' \
  | grep -oE 'SRC=[^ ]+|DPT=[0-9]+|PROTO=[A-Z]+' | paste - - - | sort | uniq -c | sort -rn | head -20
```

`/var/log/ufw.log` has the same lines when rsyslog is installed (readable by group
`adm`). Logging must be on (`Logging: on (low)` or higher) for any of this to appear;
if it's off, an empty result means nothing.

Name the service where the port is well known (1714–1764 KDE Connect / GSConnect,
5353 mDNS, 3702 WS-Discovery, 1900 SSDP, 137–138 NetBIOS, 22000/21027 Syncthing).
Repeated blocks on a known service port from a LAN address usually mean something
legitimate is being refused. High random destination ports are mostly noise (late
replies to expired connections).

## 5. Holes ufw doesn't see

- **Docker** writes its own chains: a container published with `-p 8080:80` is
  reachable from the network **whatever ufw says**, because the traffic is DNAT-ed
  and goes through FORWARD, not INPUT. List them separately:
  `docker ps --format '{{.Names}}\t{{.Ports}}' | grep -E '0\.0\.0\.0|\[::\]|:::'`.
  The same applies to Podman/LXD/libvirt port forwards.
- **VPN / overlay interfaces** (`tailscale0`, `wg0`, `zt*`) are filtered by ufw like
  any interface unless a rule allows `in on <iface>`; the overlay's own ACLs apply
  on top.
- `Default: deny (routed)` matters only for VMs/containers forwarding through this host.

## 6. Optional: snapshot and diff

When the user wants change tracking ("has the firewall changed?", "save the current
rules"):

```bash
STATE="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/ubuntu-security/ufw"
mkdir -p "$STATE"
prev="$(ls -1t "$STATE"/*.rules 2>/dev/null | head -1)"          # newest saved state
[ -n "$prev" ] && diff <(sort "$prev") <(sudo ufw show added | sort)  # < removed, > added
sudo ufw show added > "$STATE/snapshot-$(date +%Y-%m-%dT%H%M%S).rules"
```

To diff against the original instead, use the `baseline-*.rules` file.

`baseline-*.rules` is written by `firewall-setup`; never overwrite it. `ufw show
added` is the best diff format: one line per rule, as the command that created it.

## 7. Optional: permissiveness review

Only when the user asks for an audit/review of the rules. Flag, without changing
anything:

- allow rules with source `Anywhere` on ports that are not meant to be public;
- port ranges wider than ~20 ports without a source restriction;
- rules with no `# comment`;
- duplicates (same action/proto/port/source/interface) — `firewall-remove` can clean
  them up;
- rules for ports nothing listens on any more (stale);
- a `deny`/`reject` rule placed *after* an allow that already matches the same
  traffic (it never fires), or an allow placed after a deny that shadows it.

## Report

Lead with one line: active/inactive, default incoming policy, logging level, number of
rules. Then the listening-vs-allowed table, Docker publishes if any, and the top recent
blocks. Facts only. No hardening advice unless the user asks for it.

## Scripts

`ufw-blocks.sh` lives in this plugin's `scripts/` directory:
`SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"`. If `CLAUDE_PLUGIN_ROOT` is unset (skill
loaded on its own), clone the repo and use its copy:

```bash
git clone --depth 1 https://github.com/danielrosehill/Ubuntu-Security ~/.local/share/ubuntu-security-skills 2>/dev/null \
  || git -C ~/.local/share/ubuntu-security-skills pull -q
SCRIPTS=~/.local/share/ubuntu-security-skills/scripts
```

## Related

- Open something → `firewall-allow`. Close something / clean up → `firewall-remove`.
- "Why can't X connect?" → `firewall-diagnose`.
- ufw not installed or never configured → `firewall-setup`.
