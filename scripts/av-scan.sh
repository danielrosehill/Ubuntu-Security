#!/usr/bin/env bash
# av-scan.sh - run one or more malware / rootkit / integrity scanners and write
# per-tool reports plus a summary. Run as root (sudo). Never quarantines or deletes.
#
# Usage: sudo av-scan.sh [--mode quick|deep|path] [--path P] [--tools LIST]
#                        [--out DIR] [--notify-user USER]
#
#   --mode quick   ClamAV over the invoking user's home + rkhunter   (default)
#   --mode deep    ClamAV over / (minus /proc /sys /dev /run /snap) + every installed tool
#   --mode path    ClamAV over --path only
#   --tools        comma list overriding the mode's tools: clamav,rkhunter,chkrootkit,lynis,aide
#   --out          report root (default: $REPORTS_DIR or ~/security-reports of the invoking user)
#   --notify-user  send a desktop notification to this user's session when there are findings
#
# Layout: <out>/<tool>/<timestamp>.txt and <out>/_summary/<timestamp>.md
# Exit:   0 clean, 1 findings (incl. warnings to review), 2 usage/run error.
set -uo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 2; }

user="${SUDO_USER:-root}"
home="$(getent passwd "$user" | cut -d: -f6)"
mode=quick; path=""; tools=""; out="${REPORTS_DIR:-$home/security-reports}"; notify_user=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) mode="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --tools) tools="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --notify-user) notify_user="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
installed_tools() {
  local t=()
  have clamscan && t+=(clamav); have rkhunter && t+=(rkhunter); have chkrootkit && t+=(chkrootkit)
  have lynis && t+=(lynis); have aide && [[ -e /var/lib/aide/aide.db ]] && t+=(aide)
  (IFS=,; echo "${t[*]}")
}

targets=()
case "$mode" in
  quick) targets=("$home"); [[ -z "$tools" ]] && tools="clamav,rkhunter" ;;
  deep)
    for d in /*; do
      case "$d" in /proc|/sys|/dev|/run|/snap|/lost+found) continue ;; esac
      [[ -d "$d" && ! -L "$d" ]] && targets+=("$d")
    done
    [[ -z "$tools" ]] && tools="$(installed_tools)" ;;
  path) [[ -n "$path" ]] || { echo "--mode path needs --path" >&2; exit 2; }
        targets=("$path"); [[ -z "$tools" ]] && tools="clamav" ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac

ts="$(date +%Y-%m-%dT%H%M%S)"
mkdir -p "$out/_summary"
summary="$out/_summary/$ts.md"
findings=0
{
  echo "# Scan $ts"
  echo
  echo "- host: $(hostname)  mode: $mode  tools: $tools"
  echo "- targets: ${targets[*]}"
  echo
} >"$summary"

record() { # tool verdict detail report
  printf '## %s: %s\n\n%s\n\nReport: `%s`\n\n' "$1" "$2" "$3" "$4" >>"$summary"
  [[ "$2" == clean ]] || findings=1
}

IFS=, read -r -a tool_list <<<"$tools"
for tool in "${tool_list[@]}"; do
  mkdir -p "$out/$tool"; rep="$out/$tool/$ts.txt"
  case "$tool" in
    clamav)
      have clamscan || { record clamav error "not installed" "-"; continue; }
      if have clamdscan && systemctl is-active --quiet clamav-daemon; then
        clamdscan --multiscan --fdpass --infected "${targets[@]}" >"$rep" 2>&1; r=$?
      else
        clamscan -r --infected --exclude-dir='^/(proc|sys|dev|run|snap)(/|$)' "${targets[@]}" >"$rep" 2>&1; r=$?
      fi
      hits="$(grep -E ' FOUND$' "$rep" || true)"
      case $r in
        0) record clamav clean "No infected files." "$rep" ;;
        1) record clamav findings "$(printf '```\n%s\n```' "$hits")" "$rep" ;;
        *) record clamav error "clamscan/clamdscan exit $r (see report; often unreadable files or no signatures - run av-update.sh)" "$rep" ;;
      esac ;;
    rkhunter)
      have rkhunter || { record rkhunter error "not installed" "-"; continue; }
      rkhunter --check --skip-keypress --report-warnings-only --nocolors >"$rep" 2>&1; r=$?
      if [[ $r -eq 0 && ! -s "$rep" ]]; then record rkhunter clean "No warnings." "$rep"
      else record rkhunter noisy "$(printf 'Warnings (many are benign after package upgrades; see /var/log/rkhunter.log):\n```\n%s\n```' "$(head -40 "$rep")")" "$rep"; fi ;;
    chkrootkit)
      have chkrootkit || { record chkrootkit error "not installed" "-"; continue; }
      chkrootkit -q >"$rep" 2>&1
      if [[ ! -s "$rep" ]]; then record chkrootkit clean "Nothing reported." "$rep"
      else record chkrootkit noisy "$(printf 'Output to review (check known false positives first):\n```\n%s\n```' "$(head -40 "$rep")")" "$rep"; fi ;;
    lynis)
      have lynis || { record lynis error "not installed" "-"; continue; }
      lynis audit system --quick --no-colors >"$rep" 2>&1
      dat=/var/log/lynis-report.dat
      hi="$(grep -m1 '^hardening_index=' "$dat" 2>/dev/null | cut -d= -f2)"
      w="$(grep -c '^warning\[\]=' "$dat" 2>/dev/null || true)"
      s="$(grep -c '^suggestion\[\]=' "$dat" 2>/dev/null || true)"
      if [[ "${w:-0}" -eq 0 ]]; then record lynis clean "Hardening index ${hi:-?}; 0 warnings; ${s:-0} suggestions." "$rep"
      else record lynis noisy "Hardening index ${hi:-?}; $w warnings; ${s:-0} suggestions. Warnings: \`grep '^warning' $dat\`" "$rep"; fi ;;
    aide)
      have aide || { record aide error "not installed" "-"; continue; }
      aide --config /etc/aide/aide.conf --check >"$rep" 2>&1; r=$?
      case $r in
        0) record aide clean "No changes against the baseline." "$rep" ;;
        [1-7]) record aide noisy "Files added/removed/changed since the baseline (expected after apt upgrades): $(grep -E '^(Added|Removed|Changed) entries' -A0 "$rep" | tr '\n' ' ')" "$rep" ;;
        *) record aide error "aide exit $r (no baseline? run: sudo aideinit)" "$rep" ;;
      esac ;;
    *) record "$tool" error "unknown tool" "-" ;;
  esac
done

chown -R "$user": "$out" 2>/dev/null || true
echo "$summary"

if [[ $findings -eq 1 && -n "$notify_user" ]] && have notify-send; then
  uid="$(id -u "$notify_user" 2>/dev/null || true)"
  if [[ -n "$uid" && -S "/run/user/$uid/bus" ]]; then
    runuser -u "$notify_user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
      notify-send -u critical "Security scan: items to review" "$summary" || true
  fi
fi

exit $findings
