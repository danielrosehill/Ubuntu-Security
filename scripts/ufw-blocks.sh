#!/usr/bin/env bash
# ufw-blocks.sh - summarise ufw log lines ([UFW BLOCK], [UFW AUDIT], [UFW ALLOW],
# [UFW LIMIT BLOCK]) from the kernel journal or /var/log/ufw.log. Read-only.
#
# Usage:
#   ufw-blocks.sh [--since "1 hour ago"] [--port N] [--src IP] [--action BLOCK]
#                 [--file /var/log/ufw.log] [--limit 25] [--raw]
#
#   --since   journalctl --since value (default "1 hour ago"). Ignored with --file.
#   --port    only lines whose destination port (DPT=) matches
#   --src     only lines whose source address (SRC=) matches
#   --action  only this action (BLOCK, ALLOW, AUDIT, "LIMIT BLOCK")
#   --file    read this file instead of the journal (last 50000 lines)
#   --limit   rows to print in the summary (default 25)
#   --raw     print the matching log lines instead of a summary
#
# Output (summary): count, action, in-interface, source, protocol, dest port.
# An empty result only means "nothing blocked" if ufw logging is on
# (ufw status verbose -> "Logging: on (low)" or higher).
set -euo pipefail

since="1 hour ago"; port=""; srcf=""; actf=""; file=""; limit=25; raw=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)  since="$2"; shift 2 ;;
    --port)   port="$2"; shift 2 ;;
    --src)    srcf="$2"; shift 2 ;;
    --action) actf="$2"; shift 2 ;;
    --file)   file="$2"; shift 2 ;;
    --limit)  limit="$2"; shift 2 ;;
    --raw)    raw=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

read_log() {
  if [[ -n "$file" ]]; then
    if [[ -r "$file" ]]; then tail -n 50000 "$file"; else sudo tail -n 50000 "$file"; fi
  else
    # Members of adm / systemd-journal can read the kernel journal without sudo.
    if [[ $EUID -eq 0 ]] || id -nG | grep -qwE 'adm|systemd-journal'; then
      journalctl -k --since "$since" --no-pager -o short-iso
    else
      sudo journalctl -k --since "$since" --no-pager -o short-iso
    fi
  fi
}

read_log | awk -v port="$port" -v srcf="$srcf" -v actf="$actf" -v raw="$raw" '
  /\[UFW [A-Z ]+\]/ {
    match($0, /\[UFW [A-Z ]+\]/); act = substr($0, RSTART + 5, RLENGTH - 6)
    in_ = "-"; src = "-"; proto = "-"; dpt = "-"
    for (i = 1; i <= NF; i++) {
      n = index($i, "="); if (n == 0) continue
      k = substr($i, 1, n - 1); v = substr($i, n + 1)
      if (k == "IN" && v != "") in_ = v
      else if (k == "SRC") src = v
      else if (k == "PROTO") proto = v
      else if (k == "DPT") dpt = v
    }
    if (port != "" && dpt != port) next
    if (srcf != "" && src != srcf) next
    if (actf != "" && act != actf) next
    if (raw == 1) { print; next }
    c[act "\t" in_ "\t" src "\t" proto "\t" dpt]++
  }
  END { if (raw != 1) for (k in c) print c[k] "\t" k }
' | if [[ $raw -eq 1 ]]; then cat; else
  { printf 'COUNT\tACTION\tIN\tSRC\tPROTO\tDPT\n'; sort -t$'\t' -k1,1nr | awk -v n="$limit" 'NR<=n'; } | column -t -s$'\t'
fi
