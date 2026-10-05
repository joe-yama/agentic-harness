#!/usr/bin/env bash
# harness watchdog — plugin monitor (monitors/monitors.json): Claude Code starts one per interactive session.
# Every HARNESS_WATCHDOG_INTERVAL seconds (default 60) it reads this session's run records (lib/runs.sh,
# written by subagent-start.sh and subagent-stop.sh) and prints one line per running subagent that
#   STALL    has not written its transcript for HARNESS_WATCHDOG_IDLE seconds (default 900), or
#   TIMEOUT  has run HARNESS_WATCHDOG_MAX seconds (default 7200) since its latest start.
# Each stdout line reaches the session as a notification. Otherwise it prints nothing: waiting costs no tokens.
# It complements Claude Code's own stall timeout (CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS, default 10 min), which
# resets on every streamed chunk and so misses a subagent that keeps streaming without progress. The idle
# default stays above the 10-minute ceiling of one foreground Bash call, during which a healthy
# subagent writes nothing. Records of other sessions are skipped (CLAUDE_CODE_SESSION_ID; without it,
# every session's), and session directories untouched for 7 days are deleted.
# Usage: watchdog.sh <plugin data dir> [--once]   (--once: a single pass, for tests)
set -u
[ -n "${1:-}" ] || exit 0
runs=$1/runs
idle_limit=${HARNESS_WATCHDOG_IDLE:-900}
max=${HARNESS_WATCHDOG_MAX:-7200}
interval=${HARNESS_WATCHDOG_INTERVAL:-60}
sid=${CLAUDE_CODE_SESSION_ID:-}
case "$sid" in *[!A-Za-z0-9_-]*) sid= ;; esac

mtime() { stat -L -c %Y "$1" 2>/dev/null || stat -L -f %m "$1" 2>/dev/null; } # GNU first: GNU stat -f means --file-system

alert() { # <record dir> <kind> <message>: prints once per kind
  [ "$(cat "$1/alerted" 2>/dev/null)" = "$2" ] && return 0
  echo "$2" > "$1/alerted"
  printf 'harness watchdog: %s\n' "$3"
}

check() { # <record dir> <now>
  local d=$1 now=$2 start t m idle run id type
  # rule:wd-skip-done
  [ -e "$d/done" ] && return 0
  # end:wd-skip-done
  start=$(cat "$d/start" 2>/dev/null)
  case "$start" in '' | *[!0-9]*) return 0 ;; esac
  t=$(cat "$d/transcript" 2>/dev/null)
  id=$(basename "$d")
  type=$(cat "$d/type" 2>/dev/null)
  run=$((now - start))
  # rule:wd-timeout
  if [ "$run" -gt "$max" ]; then
    alert "$d" timeout "TIMEOUT ${type:-subagent} $id has run ${run}s (limit ${max}s). Stop it, read its report or transcript tail, then resume it or dispatch a fresh one (harness:execute, Waiting)."
    return 0
  fi
  # end:wd-timeout
  # rule:wd-unknown-transcript
  [ -n "$t" ] || return 0
  # end:wd-unknown-transcript
  # rule:wd-heartbeat
  # a transcript that does not exist yet, or predates a restart, counts from the start
  m=$(mtime "$t") || m=$start
  [ "$m" -ge "$start" ] || m=$start
  # end:wd-heartbeat
  idle=$((now - m))
  # rule:wd-stall
  if [ "$idle" -gt "$idle_limit" ]; then
    alert "$d" stall "STALL ${type:-subagent} $id has not written its transcript for ${idle}s (limit ${idle_limit}s). Check for a pending permission prompt, then stop it and resume it or dispatch a fresh one (harness:execute, Waiting)."
    return 0
  fi
  # end:wd-stall
  # rule:wd-rearm
  [ "$(cat "$d/alerted" 2>/dev/null)" = stall ] && rm -f "$d/alerted"
  # end:wd-rearm
  return 0
}

pass() {
  local now d
  now=$(date +%s)
  # rule:wd-session
  if [ -n "$sid" ]; then set -- "$runs/$sid"/*/; else set -- "$runs"/*/*/; fi
  # end:wd-session
  for d in "$@"; do
    [ -d "$d" ] && check "${d%/}" "$now"
  done
}

# rule:wd-prune
[ -d "$runs" ] && find "$runs" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
# end:wd-prune
if [ "${2:-}" = --once ]; then
  pass
  exit 0
fi
while :; do
  pass
  sleep "$interval"
done
