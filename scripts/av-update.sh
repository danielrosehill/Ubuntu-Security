#!/usr/bin/env bash
# av-update.sh - refresh signatures / data for every installed scanner.
# Run as root (sudo). Skips tools that are not installed.
#
# Usage: sudo av-update.sh [--out DIR]
#   --out DIR  where to save debsecan output (default: $REPORTS_DIR or ~/security-reports
#              of the invoking user)
#
# Deliberately does NOT run `rkhunter --propupd` or promote a new AIDE database:
# both re-baseline and would hide real changes. Those are explicit user actions.
#
# Exit: 0 all refreshed, 1 at least one refresh failed.
set -uo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 2; }

user="${SUDO_USER:-root}"
home="$(getent passwd "$user" | cut -d: -f6)"
out="${REPORTS_DIR:-$home/security-reports}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ts="$(date +%Y-%m-%dT%H%M%S)"
rc=0
line() { printf '%-10s %s\n' "$1" "$2"; }

if command -v freshclam >/dev/null; then
  was_active=0
  systemctl is-active --quiet clamav-freshclam && was_active=1
  # The freshclam service holds a lock on the database; stop it for a manual run.
  [[ $was_active -eq 1 ]] && systemctl stop clamav-freshclam
  if freshclam --quiet; then
    ver="$(clamscan --version 2>/dev/null | head -1)"
    line clamav "updated ($ver)"
  else
    line clamav "FAILED - see: sudo freshclam (rate-limited or mirror unreachable?)"; rc=1
  fi
  [[ $was_active -eq 1 ]] && systemctl start clamav-freshclam
else
  line clamav "not installed"
fi

if command -v rkhunter >/dev/null; then
  # rkhunter --update exits 2 when files were updated, 0 when nothing changed.
  rkhunter --update --nocolors >/dev/null 2>&1; r=$?
  case $r in
    0) line rkhunter "up to date" ;;
    2) line rkhunter "updated" ;;
    *) line rkhunter "FAILED (exit $r) - on Ubuntu set UPDATE_MIRRORS=1, MIRRORS_MODE=0 and WEB_CMD=\"\" in /etc/rkhunter.conf"; rc=1 ;;
  esac
else
  line rkhunter "not installed"
fi

if command -v lynis >/dev/null; then
  info="$(lynis update info 2>/dev/null | grep -iE 'status|version' | tr -s ' ' | paste -sd ';' -)"
  line lynis "${info:-checked} (upgrade with: sudo apt install --only-upgrade lynis)"
else
  line lynis "not installed"
fi

if command -v chkrootkit >/dev/null; then
  line chkrootkit "no signature feed; updated through apt"
fi

if command -v aide >/dev/null; then
  line aide "no feed; run the malware-scan skill to check the integrity database"
fi

if command -v debsecan >/dev/null; then
  mkdir -p "$out/debsecan"
  f="$out/debsecan/$ts.txt"
  suite="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
  if debsecan --suite "$suite" --format detail >"$f" 2>&1; then
    n="$(grep -c '^CVE-' "$f" || true)"
    line debsecan "$n CVE entries listed - $f"
  else
    line debsecan "FAILED - see $f"; rc=1
  fi
  chown -R "$user": "$out" 2>/dev/null || true
fi

exit $rc
