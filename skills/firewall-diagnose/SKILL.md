---
name: firewall-diagnose
description: Work out whether the host firewall (ufw) is what is blocking a connection on an Ubuntu desktop or server, and if so which rule or policy — reads UFW BLOCK lines from the kernel log (journalctl -k) and /var/log/ufw.log, checks logging is on, walks first-match rule order, interface and address-family mismatches, services bound to localhost, and Docker-published ports that bypass ufw. Diagnoses only; hands the fix to firewall-allow / firewall-remove. Use when the user asks "is the firewall blocking X?", "why can't my phone / other machine connect to this one", "KDE Connect / Samba / printer / SSH doesn't work", "port X is unreachable", "ufw is blocking something", or "I opened the port but it still doesn't work".
---

# Is the firewall blocking X?

Goal: a yes/no with evidence, then the smallest fix. Diagnose before changing
anything; temporarily disabling ufw "to test" is a last resort and only with the
user's agreement (never on a remote box without an out-of-band console).

Gather first: **which service/port**, **which client** (IP, on LAN / VPN /
internet), **direction** (into this machine, or out from it).

## 1. Is ufw even active, and is it logging?

```bash
sudo ufw status verbose | head -5
```

- `Status: inactive` → ufw is not the cause. Look elsewhere (service down, bound to
  localhost, router/cloud firewall, client side).
- `Logging: off` → blocks are invisible. Turn on low logging (it records blocked
  packets only, rate-limited) and reproduce:
  `sudo ufw logging low`. Tell the user you did; offer to turn it back off after.

## 2. Is the service actually listening where the client can reach it?

```bash
sudo ss -tulnp | grep -E ':<port>\b'
```

- Nothing listening → not a firewall problem; the service is down or on another port.
- Bound to `127.0.0.1` / `::1` only → not a firewall problem; the service's own config
  must listen on the LAN address (e.g. `bind-address`, `listen_addresses`,
  `ListenAddress`).
- On Ubuntu 22.10+ SSH is socket-activated: port changes are made in `ssh.socket`
  (`systemctl edit ssh.socket` → `ListenStream=`), not just `sshd_config`.

## 3. Look for the block itself

Reproduce the failing connection from the client, then:

```bash
bash "$SCRIPTS/ufw-blocks.sh" --since "10 min ago" --port <port>
bash "$SCRIPTS/ufw-blocks.sh" --since "10 min ago" --src <client-ip> --raw | tail
```

Without the script:

```bash
sudo journalctl -k --since "-10min" --no-pager | grep -E 'UFW (BLOCK|AUDIT)' | grep -E "DPT=<port>|SRC=<client-ip>"
sudo grep -E "DPT=<port>" /var/log/ufw.log | tail      # needs rsyslog; group adm can read it
```

Reading a line: `[UFW BLOCK] IN=<iface> OUT= ... SRC=<client> DST=<this host>
PROTO=TCP SPT=<client port> DPT=<service port>`. `IN=` set and `OUT=` empty = inbound
to this host. `OUT=` set = outbound from this host (only blocked if the outgoing
policy is deny or a deny-out rule matches). `IN=` and `OUT=` both set = routed /
forwarded traffic (VMs, containers) → governed by `ufw route` rules and
`Default: ... (routed)`.

- **Matching BLOCK lines** → ufw is blocking it. Continue to step 4 for *why*.
- **No lines, logging on, client really tried** → ufw is not dropping it. Check the
  client side, the router / cloud security group, or that the traffic even reaches
  this host (`sudo tcpdump -ni any port <port>` while the client retries).
- Broadcast/multicast discovery (mDNS 5353, SSDP 1900, WS-Discovery 3702, KDE Connect
  UDP 1716 broadcast) blocks have `DST=` a broadcast/multicast address; allowing the
  unicast port alone won't fix discovery.

## 4. Why does the rule set block it?

```bash
sudo ufw status numbered
```

Walk the list top to bottom **for the packet you saw** (interface, source,
protocol, port). ufw is first match wins:

1. **No allow rule matches** → default `deny (incoming)` drops it. Fix with
   `firewall-allow`.
2. **A deny/reject above the allow** → the allow never fires. Fix by moving: delete and
   `insert` the allow above it, or remove the deny (`firewall-remove`).
3. **Interface mismatch** → rule says `on tailscale0` / `on eth0` but the log shows
   `IN=wlp3s0` (or the reverse). The client came in over a different path than
   assumed (e.g. LAN vs VPN, Wi-Fi vs Ethernet).
4. **Source mismatch** → rule allows `192.168.1.0/24` but `SRC=` is outside it (another
   subnet, the VPN's CGNAT range `100.64.0.0/10`, a Docker bridge `172.17.0.0/16`, or an
   IPv6 address).
5. **Address family** → rule exists only for IPv4 (source was an IPv4 CIDR) but the
   client connects over IPv6 (`SRC=fe80:...` or a global v6 address); or
   `IPV6=no` in `/etc/default/ufw`.
6. **Protocol** → rule is `proto tcp` but the service also needs UDP (DNS, mDNS, KDE
   Connect, Syncthing discovery, WireGuard, QUIC/HTTP3).
7. **Rate limit** → `LIMIT` rule and `[UFW LIMIT BLOCK]` lines: the client opened more
   than 6 connections in 30 s.

## 5. Things ufw doesn't control

- **Docker-published ports** (`docker ps` shows `0.0.0.0:8080->80/tcp`) bypass ufw:
  if a container port *is* reachable despite a deny, or a ufw allow seems to "do
  nothing" for it, that is why. Traffic from containers *to the host* (e.g. a
  container reaching a host service) comes in on `docker0`/`br-*` and *is* filtered by
  ufw INPUT — allow it with `allow in on docker0 ...` or from the bridge subnet.
- **Other firewalls**: `firewalld`, a hand-written nftables ruleset
  (`sudo nft list ruleset`), cloud provider security groups, the router.
- **Established connections** survive rule changes; reconnect to test.

## 6. Report and hand off

State: blocked by ufw yes/no, the evidence (one or two log lines, the rule number),
and the fix as a one-liner. If the user asked for it to work, apply the fix via the
`firewall-allow` / `firewall-remove` procedure and re-test (step 3 should show no
new blocks). If you turned logging on only for this, offer to set it back:
`sudo ufw logging off`.

## Scripts

`ufw-blocks.sh` is in this plugin's `scripts/` directory:
`SCRIPTS="${CLAUDE_PLUGIN_ROOT}/scripts"`. If `CLAUDE_PLUGIN_ROOT` is unset, clone
`https://github.com/danielrosehill/Ubuntu-Security` (e.g. to
`~/.local/share/ubuntu-security-skills`) and use its `scripts/`.
