---
name: yubikey-setup
description: Set up a YubiKey or other FIDO2/U2F security key for authentication on Ubuntu — detect the key, install libpam-u2f, register the key with pamu2fcfg, require or accept it for sudo, the login screen and the lock screen via PAM, and create FIDO2-backed SSH keys — with a root shell kept open so a PAM mistake can't lock the user out. Use when the user says "set up my yubikey", "use a security key for sudo", "2FA for login", "touch to sudo", "yubikey ssh key", or "my yubikey isn't detected".
---

# Security key (YubiKey / FIDO2) authentication

## 0. Safety first

PAM changes can lock the user out of `sudo` and login. Before editing anything in
`/etc/pam.d/`:

- open a **root shell in a second terminal** (`sudo -i`) and keep it open until
  the change is verified;
- back up the file: `sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.bak`;
- test in a **new** terminal, never in the one holding the root shell.

## 1. Detect the key

```bash
lsusb | grep -iE 'yubico|feitian|solokeys|nitrokey|google|token'
sudo apt install -y libfido2-1 fido2-tools
fido2-token -L                      # lists FIDO2 devices (/dev/hidraw*)
```

Not detected: try another port/cable, `sudo dmesg | tail`; for YubiKey-specific
management (`ykman`, OTP/PIV), `sudo apt install yubikey-manager` and `ykman info`.
Hidraw access for normal users comes from `udev` rules in `libfido2-1`; if
`fido2-token -L` needs sudo, the rules aren't applied yet: `sudo udevadm trigger` or
re-plug.

## 2. Register the key (pam_u2f)

```bash
sudo apt install -y libpam-u2f
mkdir -p ~/.config/Yubico
pamu2fcfg > ~/.config/Yubico/u2f_keys            # touch the key when it blinks
pamu2fcfg -n >> ~/.config/Yubico/u2f_keys        # backup key: appends, run with the 2nd key inserted
```

Register a **second key** (or keep password fallback) — a single lost key otherwise
means no sudo. For a system-wide mapping file instead of per-user, write to
`/etc/u2f_mappings` and add `authfile=/etc/u2f_mappings` to the PAM lines.

## 3. Wire it into PAM

Choose the mode with the user:

| Mode | PAM line | Effect |
| --- | --- | --- |
| Key **or** password | `auth sufficient pam_u2f.so cue` | touch the key instead of typing a password |
| Key **and** password (2FA) | `auth required pam_u2f.so cue` | password plus touch |

Put the line **above** `@include common-auth` in the target file:

| Target | File |
| --- | --- |
| sudo | `/etc/pam.d/sudo` |
| GNOME login screen | `/etc/pam.d/gdm-password` |
| KDE login (SDDM) | `/etc/pam.d/sddm` |
| lock screen | GNOME uses `gdm-password`; KDE uses `/etc/pam.d/kde` |
| everything (incl. TTY, su) | `/etc/pam.d/common-auth` — only once the per-service setup has been proven |

```bash
sudo sed -i '0,/^@include common-auth/s//auth sufficient pam_u2f.so cue\n@include common-auth/' /etc/pam.d/sudo
```

`cue` prints "Please touch the device." Add `nouserok` while rolling out to several
users so those without a registered key can still use their password.

## 4. Verify (new terminal)

```bash
sudo -k; sudo true          # should ask for a touch (sufficient mode) or password+touch (required)
```

Then test once with the key **removed**: in `sufficient` mode the password must still
work; in `required` mode it must fail. If anything is wrong, restore from the root
shell: `cp /etc/pam.d/sudo.bak /etc/pam.d/sudo`.

## 5. SSH with the key

FIDO2-backed SSH keys need no PAM changes; see `ssh-keys` §2:

```bash
ssh-keygen -t ed25519-sk -O resident -O verify-required -C "yubikey"
```

`-O resident` stores the key handle on the token (recover on another machine with
`ssh-keygen -K`); `verify-required` needs the token PIN as well as a touch. The server
needs OpenSSH 8.2+ (any supported Ubuntu).

## Undo

Remove the `pam_u2f.so` line(s) from the edited files (or restore the `.bak`), and
optionally `sudo apt remove libpam-u2f`.
