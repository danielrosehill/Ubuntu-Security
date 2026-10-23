---
name: ssh-keys
description: Manage the user's SSH key pairs on Ubuntu — inventory ~/.ssh keys with type, size, fingerprint and comment, which are loaded in the agent and referenced in ~/.ssh/config, flag weak or orphaned keys, generate new ed25519 (or FIDO2 hardware-backed ed25519-sk) keys, copy a public key to other machines with ssh-copy-id, review authorized_keys on this host, fix permissions, and delete keys the user retires. Use when the user says "list my ssh keys", "generate a new ssh key", "set up key auth to <host>", "copy my key to these machines", "who can log in with a key here", "delete old ssh keys", or "fix ssh key permissions".
---

# SSH keys

Client-side keys (`~/.ssh/id_*`) and this host's `authorized_keys`. The SSH *server*
configuration is `ssh-server-config`.

## 1. Inventory

```bash
ls -la ~/.ssh/
for k in ~/.ssh/*.pub; do ssh-keygen -l -f "$k"; done          # bits, fingerprint, comment, type
ssh-add -l 2>/dev/null || echo "agent: no keys / not running"
grep -iE '^\s*(Host|IdentityFile)\s' ~/.ssh/config 2>/dev/null   # which key each host uses
```

Table: file, type, bits, fingerprint, comment, loaded in agent, referenced by
(config hosts). Private keys without a `.pub` twin: regenerate the public half with
`ssh-keygen -y -f <key> > <key>.pub`. Check passphrase presence with
`ssh-keygen -y -P '' -f <key> >/dev/null 2>&1 && echo "NO passphrase"`.

Weak / legacy: `DSA` (disabled by OpenSSH since 7.0, removed in 10.0), `RSA` < 2048
bits (OpenSSH 9.x refuses < 1024; 2048 is the floor), `ECDSA` is acceptable;
`ED25519` is the default to recommend for new keys.

## 2. Generate

```bash
ssh-keygen -t ed25519 -C "<user>@<host> $(date +%F)" -f ~/.ssh/id_ed25519_<purpose>
# hardware-backed (YubiKey / FIDO2 token; needs libfido2, preinstalled on Ubuntu):
ssh-keygen -t ed25519-sk -O resident -O verify-required -C "<label>" -f ~/.ssh/id_ed25519_sk
```

Ask whether to set a passphrase (recommended for laptops; the desktop keyring /
`ssh-agent` unlocks it once per session). Don't overwrite an existing file: `-f` a new
name.

## 3. Copy to other machines

For each target the user lists (SSH alias or IP), one at a time; the user types the
remote password when prompted:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub <user>@<host>
ssh -o PasswordAuthentication=no -o BatchMode=yes <user>@<host> true && echo "key auth OK"
```

If the remote has password auth disabled already, `ssh-copy-id` can't log in; the key
has to be added via an existing session or console. Optionally add a `Host` block to
`~/.ssh/config` with `IdentityFile` and `IdentitiesOnly yes`.

## 4. Who can log in here (authorized_keys)

```bash
for h in /root /home/*; do f="$h/.ssh/authorized_keys"; [ -f "$f" ] && { echo "== $f"; sudo ssh-keygen -l -f "$f"; }; done
sudo sshd -T 2>/dev/null | grep -i authorizedkeysfile
```

List each key's fingerprint and comment. Removing one: edit the file and delete the
line (back it up first: `cp authorized_keys authorized_keys.bak`). On a remote box,
**never remove the key the current session used**: find it with
`journalctl -u ssh | grep "Accepted publickey" | tail -1` (shows the fingerprint).

## 5. Permissions

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_* ~/.ssh/config ~/.ssh/authorized_keys 2>/dev/null
chmod 644 ~/.ssh/*.pub
```

sshd silently ignores `authorized_keys` when the home dir, `~/.ssh`, or the file is
group/world-writable (`StrictModes yes`), which shows up as "key auth doesn't work".

## 6. Retire a key

Confirm per key. Remove it from the agent, the config, and disk; remind the user to
remove the public key from places it was authorized (other hosts' `authorized_keys`,
GitHub/GitLab, cloud consoles) — list the ones you can see from `~/.ssh/config`.

```bash
ssh-add -d ~/.ssh/<old>
rm ~/.ssh/<old> ~/.ssh/<old>.pub
```
