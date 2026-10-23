---
name: fail2ban
description: Install, configure and operate fail2ban on Ubuntu — sshd jail reading the systemd journal, ban time and retry thresholds, ignoring the LAN/VPN so the user can't ban themselves, list active jails and banned IPs, unban an address, and check whether fail2ban is the reason a client can't connect. Use when the user says "set up fail2ban", "protect ssh from brute force", "who is banned", "unban <ip>", "fail2ban banned me", or "is fail2ban working".
---

# fail2ban

Mostly for internet-facing servers. On a LAN-only desktop with sshd off it does
nothing useful; say so if asked to install it there.

## Status / operate

```bash
systemctl is-active fail2ban
sudo fail2ban-client status                       # list of jails
sudo fail2ban-client status sshd                  # failures, currently banned IPs
sudo fail2ban-client get sshd banip --with-time   # bans with expiry (0.11+)
sudo fail2ban-client set sshd unbanip <ip>        # unban
sudo fail2ban-client unban --all                  # unban everything
sudo zgrep -h 'Ban ' /var/log/fail2ban.log* | tail -20
```

"Fail2ban banned me": a client getting `Connection refused`/timeouts after a few bad
logins is the classic sign. Check `status sshd` for its IP, unban, then add the
network to `ignoreip`.

## Install and configure

```bash
sudo apt install -y fail2ban
```

Never edit `jail.conf` (overwritten on upgrade); write `/etc/fail2ban/jail.local`:

```ini
[DEFAULT]
# addresses that are never banned: localhost, the LAN, the VPN range
ignoreip = 127.0.0.1/8 ::1 <lan-cidr> <vpn-cidr>
bantime  = 1h
findtime = 10m
maxretry = 5
# progressive bans for repeat offenders
bantime.increment = true
backend  = systemd

[sshd]
enabled = true
# custom port? list it so the ban covers it
port    = ssh
```

`backend = systemd` matters on Ubuntu releases where `/var/log/auth.log` may not exist
(no rsyslog); the journal always has sshd's messages. Ubuntu's package already sets
this in `/etc/fail2ban/jail.d/defaults-debian.conf` on recent releases; `jail.local`
makes it explicit.

```bash
sudo fail2ban-client -t                         # config test
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban                 # after edits
sudo fail2ban-client status sshd
```

If `status sshd` shows `Total failed: 0` while the journal plainly has failed logins,
the jail's journal match misses the `sshd-session` process (fail2ban older than 1.1 on
OpenSSH 9.8+). Override in the `[sshd]` section:
`journalmatch = _SYSTEMD_UNIT=ssh.service`, restart, and re-check.

## How bans interact with ufw

The default `banaction` on Ubuntu inserts its own nftables/iptables chain
(`f2b-sshd`), independent of ufw rules; bans work whether ufw is active or not. If
the user wants bans visible in `ufw status`, set `banaction = ufw` in `[DEFAULT]`
(bans then appear as numbered `REJECT`/`DENY` rules — and `firewall-remove` must not
delete them by number while fail2ban is managing them).

## Other jails

Only enable for services that exist on the host: `nginx-http-auth`, `nginx-botsearch`,
`apache-auth`, `postfix`, `dovecot`, `recidive` (long bans for repeat offenders across
jails). Each needs the service's log path or journal match; `sudo fail2ban-client -d`
dumps the resolved config for checking.
