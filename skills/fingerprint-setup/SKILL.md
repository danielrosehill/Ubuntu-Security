---
name: fingerprint-setup
description: Set up a fingerprint reader for login, lock screen and sudo on an Ubuntu laptop or desktop — check the reader is supported by libfprint, install fprintd and libpam-fprintd, enroll fingers, enable fingerprint auth with pam-auth-update, verify, and troubleshoot unsupported or flaky readers. Use when the user says "set up the fingerprint reader", "enable fingerprint login", "fingerprint for sudo", "enroll my fingerprint", or "fingerprint reader not working".
---

# Fingerprint authentication

## 1. Is the reader supported?

```bash
lsusb | grep -iE 'finger|synaptics|goodix|elan|validity|egis|focal|upek|authentec'
sudo apt install -y fprintd libpam-fprintd
fprintd-list "$USER"                 # "No devices available" = no driver for this reader
```

`libfprint` supports a fixed list of USB IDs (upstream list:
`https://fprint.freedesktop.org/supported-devices.html`). Match the `ID xxxx:yyyy`
from `lsusb`. Some readers (several Goodix/Synaptics on business laptops) need a
vendor driver from the OEM's PPA (e.g. Dell/Lenovo `libfprint-2-tod1-*` packages)
and are only supported on certified Ubuntu images; say so rather than guessing.

## 2. Enroll

Run as the user (no sudo); it asks for several touches per finger:

```bash
fprintd-enroll                       # default finger (right index)
fprintd-enroll -f left-index-finger
fprintd-list "$USER"                 # enrolled fingers
fprintd-verify                       # test a match
```

GNOME: Settings → Users → Fingerprint Login does the same. KDE: System Settings →
Users → Configure Fingerprint Authentication.

## 3. Enable for login / sudo

```bash
sudo pam-auth-update --enable fprintd
```

This adds `pam_fprintd.so` to `/etc/pam.d/common-auth`, so it applies to the login
screen, lock screen, `sudo`, and polkit prompts. Password still works (fingerprint is
tried first, with a timeout). To check the result:
`grep fprintd /etc/pam.d/common-auth`.

Keep a terminal with `sudo -i` open while testing, as with any PAM change.

```bash
sudo -k; sudo true                   # should say "Place your finger on the fingerprint reader"
```

Notes:
- At first login after boot, GNOME/KDE still need the password to unlock the
  keyring; fingerprint login leaves the keyring locked otherwise. That is expected.
- With the lid closed (external monitor), the prompt waits for the reader timeout
  before falling back to the password; the user can press Enter/Ctrl+C to skip.

## Troubleshooting

```bash
systemctl status fprintd --no-pager
journalctl -u fprintd -b --no-pager | tail -30
```

- Reader stops working after suspend: `sudo systemctl restart fprintd`; some readers
  need a USB autosuspend quirk.
- "enroll-disconnected"/"enroll-unknown-error": delete and re-enroll
  (`fprintd-delete "$USER"`), check BIOS/firmware has the reader enabled, update
  firmware with `fwupdmgr update` (many Synaptics/Goodix fixes ship that way).

## Undo

```bash
sudo pam-auth-update --disable fprintd
fprintd-delete "$USER"
```
