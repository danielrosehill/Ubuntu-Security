---
name: ssh-server-config
description: Inspect and change the OpenSSH server configuration on an Ubuntu desktop or server safely — effective settings via `sshd -T`, drop-ins in /etc/ssh/sshd_config.d, socket activation (ssh.socket) on Ubuntu 22.10+, recent logins and failed attempts — and apply requested changes such as disabling password or root login, changing the port, restricting users, or turning sshd off on a desktop, with a config test and a kept-open session so a mistake can't lock the user out. Use when the user says "check my ssh server config", "disable password login", "disable root ssh", "change the ssh port", "only allow key auth", "who has been logging in over ssh", "turn off sshd", or "harden ssh" (when explicitly asked).
---

# SSH server configuration

## 1. Current state

```bash
dpkg -l openssh-server 2>/dev/null | tail -1 || echo "openssh-server not installed"
systemctl is-active ssh.socket ssh.service        # 22.10+: ssh.socket listens, ssh.service starts on demand
sudo sshd -T | grep -Ei '^(port|listenaddress|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|permitemptypasswords|authenticationmethods|allowusers|allowgroups|maxauthtries|x11forwarding|usepam) '
ls /etc/ssh/sshd_config.d/                         # drop-ins; cloud-init often writes 50-cloud-init.conf
```

`sshd -T` prints the **effective** config (after drop-ins and defaults); trust it over
reading `sshd_config`. Note the precedence trap: for most options the **first**
value read wins, and `/etc/ssh/sshd_config.d/*.conf` is included at the **top** of
`sshd_config`. A `PasswordAuthentication yes` in `50-cloud-init.conf` beats a `no`
further down the main file.

Recent activity:

```bash
sudo journalctl -u ssh --since -7d --no-pager | grep -E 'Accepted|Failed password|Invalid user' | tail -30
last -n 20 -i | grep -v '^reboot'
```

Filter by unit (`-u ssh`), not by process name: since OpenSSH 9.8 (Ubuntu 24.10+) the
per-connection process is `sshd-session`, and `Accepted` / `Failed password` lines
come from it, so `journalctl _COMM=sshd` misses them.

## 2. Change safely

Always:

1. Write changes as a drop-in that sorts **first**, e.g.
   `/etc/ssh/sshd_config.d/00-local.conf`, so it takes precedence.
2. Test: `sudo sshd -t` (no output = valid).
3. Apply: `sudo systemctl reload ssh` (existing sessions stay up).
4. **Remote session**: keep the current session open and verify from a *second*
   connection before closing it. Before disabling passwords, confirm key login works:
   `ssh -o PasswordAuthentication=no -o BatchMode=yes <user>@<host> true`.

Common requests:

```bash
# key-only auth
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/00-local.conf
# no root login (or "prohibit-password" to allow root with keys only)
echo 'PermitRootLogin no' | sudo tee -a /etc/ssh/sshd_config.d/00-local.conf
# restrict who can log in
echo 'AllowUsers <user1> <user2>' | sudo tee -a /etc/ssh/sshd_config.d/00-local.conf
# listen only on the LAN/VPN address
echo 'ListenAddress <lan-ip>' | sudo tee -a /etc/ssh/sshd_config.d/00-local.conf
sudo sshd -t && sudo systemctl reload ssh
```

### Changing the port (socket activation)

On Ubuntu 22.10 and later, `ssh.socket` owns the listening port: `Port` in
`sshd_config` is read by a systemd generator at boot / `daemon-reload` and turned
into the socket's `ListenStream`. Procedure:

```bash
echo 'Port 2222' | sudo tee -a /etc/ssh/sshd_config.d/00-local.conf
sudo sshd -t
sudo ufw allow 2222/tcp comment 'ssh new port'      # BEFORE switching, if ufw is active
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo ss -tlnp | grep -E ':2222\b'
```

Test the new port from a second session, then remove the old ufw rule
(`firewall-remove`). On 22.04 and earlier (no socket activation) it's just
`sudo systemctl restart ssh`. Mention cloud security groups if this is a VM.

### Turning sshd off (desktop that doesn't need it)

```bash
sudo systemctl disable --now ssh.socket ssh.service
```

or remove it: `sudo apt remove openssh-server`. Never on a box the user is connected
to over SSH.

## 3. Report

Effective values for the settings above, who logged in recently and how (key /
password), failed-attempt volume and top sources. Changes made: the drop-in contents
and the `sshd -t` result. No unrequested hardening.

## Related

- Brute-force throttling → `fail2ban`, or `ufw limit OpenSSH` (`firewall-allow`).
- Keys and authorized_keys → `ssh-keys`.
- Hardware 2FA for SSH → `yubikey-setup` (`ed25519-sk` keys, or `pam_u2f`).
