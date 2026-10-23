---
name: firewall-remove
description: Remove or tighten ufw firewall rules on an Ubuntu desktop or server — show the numbered rules, delete by number or by rule spec, dedupe redundant entries, replace a broad allow with a scoped one, or reset to a saved baseline. Confirms before deleting anything that was not added in this same session, and deletes highest number first because ufw renumbers after every delete. Use when the user says "remove the firewall rule for X", "close port X", "delete ufw rule 5", "clean up / dedupe the firewall rules", "tighten this rule to the LAN", "undo the rule we just added", or "reset ufw to the baseline".
---

# Remove or tighten firewall rules

## 1. Show what is there

```bash
sudo ufw status numbered
sudo ufw show added          # the same rules as the commands that created them
```

Identify the target rule(s) with the user's description (port, service, source,
comment). Each IPv4 rule usually has a separate `(v6)` twin with its own number;
removing "port 8000" normally means **both**.

## 2. Confirm

- A rule **added earlier in this same session** (e.g. "undo that") → just remove it.
- Anything else → show the exact rule line(s) that will go and get a yes first. If
  the user already named the rule unambiguously ("delete rule 7", "remove the 8000/tcp
  allow"), that is the confirmation.
- **Remote SSH box**: never remove the rule that allows the current SSH session
  (`OpenSSH`, `22/tcp`, or the custom sshd port) unless the user explicitly insists
  and another allow still covers their source address. Check the session's source:
  `echo "$SSH_CONNECTION"` (first field is the client IP).

## 3. Delete

**By spec** (preferred — removes the v4 and v6 rule together, and no numbering to
get wrong): prefix the original rule with `delete`, exactly as `ufw show added` prints
it.

```bash
sudo ufw delete allow 8000/tcp
sudo ufw delete allow from 192.168.1.0/24 to any port 445 proto tcp
sudo ufw delete allow OpenSSH
```

**By number**: ufw renumbers after every delete, so delete the **highest number
first**, and use `--force` to skip the interactive y/n prompt.

```bash
for n in $(printf '%s\n' 12 7 3 | sort -rn); do sudo ufw --force delete "$n"; done
```

Deleting by number removes only that one line — the `(v6)` twin stays unless its
number is in the list too.

## 4. Tighten instead of delete

To narrow `allow 445/tcp` (from anywhere) down to the LAN: **add the scoped rule
first, then delete the broad one**, so there is no gap.

```bash
sudo ufw allow from <lan-cidr> to any port 445 proto tcp comment 'SMB LAN'
sudo ufw delete allow 445/tcp
```

## 5. Dedupe

Group `ufw status numbered` lines by (action, direction, port/proto or app, source,
interface). For groups with more than one rule, keep the one with the most
descriptive comment and remove the others, highest number first. A broader rule
(e.g. `Anywhere on tailscale0`) makes narrower rules on the same interface redundant;
point this out, but only remove them if the user agrees.

## 6. Reset to a baseline

Only on explicit request. It removes every rule added since the baseline.

```bash
STATE="${CLAUDE_USER_DATA:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-plugins}/ubuntu-security/ufw"
ls -1 "$STATE"/baseline-*.rules
```

`sudo ufw --force reset` **disables ufw** and backs up the old rule files to
`/etc/ufw/*.rules.<timestamp>`. Re-apply the defaults and each baseline line
(`ufw show added` format: drop the leading `ufw ` and run `sudo ufw <rest>`), then
`sudo ufw --force enable`. On a remote box, re-add the SSH allow **before** enabling.

## 7. Verify and record

```bash
sudo ufw status numbered
```

Show before → after in the reply (one line per removed rule). If the user keeps
snapshots (`firewall-status` §6), write a new one.

## Notes

- `ufw delete` of a rule that doesn't exist prints `Could not delete non-existent
  rule` and changes nothing: re-read the spec from `ufw show added`.
- Removing an allow does not drop already-established connections (conntrack); the
  user may need to reconnect to see the effect.
- Removing a rule does nothing for Docker-published ports — those never went through
  ufw (see `firewall-status` §5).
