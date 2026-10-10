#!/bin/bash
# backfill.sh -- nightly: extractor lines -> sessions-tracker register+heartbeat.
# Best effort, never fails cron (exit 0). Mirrors task-ledger §6 backfill rule:
# an agent that never called the CLI still lands in the registry a day late.
H=$(cd "$(dirname "$0")/../.." && pwd)   # harness root
export SESS_ROOT="$H/run/sessions-tracker/sessions"
export INBOX_SENDER="${INBOX_SENDER:-backfill@sh}"
SESS="$H/run/sessions-tracker/tools/session"
SINCE_MIN=${SINCE_MIN:-1500}  # ~25h

have() { [ -f "$1" ] && [ "$(find "$1" -mmin -$SINCE_MIN 2>/dev/null)" ]; }

# pi: newest session files touched in window -> register + heartbeat from pi.py
for f in "$HOME"/.pi/agent/sessions/*/*.jsonl; do
  have "$f" || continue
  sid=$(basename "$f" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}' | head -1 | cut -c1-12)
  [ -n "$sid" ] || continue
  line=$(python3 "$H/tools/session-extract/pi.py" "$f" 2>/dev/null | head -1) || continue
  [ -n "$line" ] || continue
  ti=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d['tokens']; print(t['in'],t['out'],t['cache_read'],d['turns'],d['cost_usd'])" 2>/dev/null) || continue
  # shellcheck disable=SC2086
  set -- $ti
  "$SESS" register --agent pi --session "$sid" --cwd unit --next "backfilled $(date -u +%F)" >/dev/null 2>&1
  "$SESS" heartbeat "pi-$sid" --tokens-in "$1" --tokens-out "$2" --cache "$3" --turns "$4" --cost "$5" >/dev/null 2>&1
done

# other agents: one line per store when the extractor runs clean; tokens only, no turns invent
for a in dsh codex opencode claude agy; do
  script="$H/tools/session-extract/$a.py"
  [ -x "$script" ] || [ -f "$script" ] || continue
  python3 "$script" 2>/dev/null | head -5 | while read -r line; do
    echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('session',''), d.get('agent','$a'))" 2>/dev/null
  done | while read -r sid ag; do
    [ -n "$sid" ] || continue
    "$SESS" register --agent "$ag" --session "$sid" --next "backfilled $(date -u +%F)" >/dev/null 2>&1
  done
done
exit 0
