#!/usr/bin/env bash
# Run records shared by subagent-start.sh, subagent-stop.sh and watchdog.sh. Source it; it defines functions only.
# One record per subagent: <plugin data dir>/runs/<session_id>/<agent_id>/ holding
#   transcript  the subagent's transcript path (its mtime is the heartbeat), empty when unknown
#   start       epoch seconds of the latest (re)start
#   type        the agent_type
#   done        present once the subagent stopped
#   alerted     the last watchdog alert (stall or timeout); a stall alert is removed when the transcript moves again
# The plugin data directory lives outside the repository, so the records need no .gitignore entry and
# do not depend on the session's working directory.

# run_dir <data dir> <session id> <agent id>
# Prints the record directory. Fails when an argument is empty or an id is not [A-Za-z0-9_-]+
# (ids become path segments).
run_dir() {
  [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] || return 1
  # rule:run-safe-id
  case "$2$3" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  # end:run-safe-id
  printf '%s/runs/%s/%s\n' "$1" "$2" "$3"
}
