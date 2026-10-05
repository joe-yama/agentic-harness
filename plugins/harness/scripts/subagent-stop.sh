#!/usr/bin/env bash
# harness subagent-stop — SubagentStop hook (Claude Code).
# Marks the subagent's run record done (lib/runs.sh), when subagent-start.sh made one, so watchdog.sh
# stops watching it. Then checks that harness:implementer and harness:reviewer end with the reply block
# of their agent file: at most 8 lines,
#   STATUS: ok|partial|blocked|failed      first line
#   VERDICT: <verdict>                     reviewer, when STATUS is ok
#   ARTIFACT: <report path>                an existing file, absolute or relative to cwd
# The full report lives in the artifact, so the parent session reads a few lines per subagent.
# A violation returns {"decision":"block"} once: the subagent rewrites its reply and the parent receives
# the rewritten one (observed with Claude Code 2.1.289). No block unless stop_hook_active is exactly
# false (it is true after one block, and a client that omits it gets no block), and none while the
# subagent still has background tasks: blocking a subagent that waits on them can loop.
set -u
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
# rule:stop-mark-done
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && . "$(dirname "$0")/lib/runs.sh" 2>/dev/null && declare -F run_dir >/dev/null &&
  dir=$(run_dir "$CLAUDE_PLUGIN_DATA" "$(j '.session_id | strings')" "$(j '.agent_id | strings')"); then
  [ -d "$dir" ] && : > "$dir/done" # internal agents without a SubagentStart get no record
fi
# end:stop-mark-done
type=$(j '.agent_type | strings')
# rule:contract-scope
case "$type" in harness:implementer | harness:reviewer) ;; *) exit 0 ;; esac
# end:contract-scope
# rule:contract-once
[ "$(j .stop_hook_active)" = false ] || exit 0
# end:contract-once
# rule:contract-background
[ "$(j '.background_tasks | if type == "array" then length else 0 end')" = 0 ] || exit 0
# end:contract-background
msg=$(j '.last_assistant_message | strings')
cwd=$(j '.cwd | strings')
problem=
# rule:contract-status
status=$(printf '%s\n' "$msg" | head -n 1 | sed -nE 's/^STATUS: (ok|partial|blocked|failed)$/\1/p')
[ -n "$status" ] || problem="the first line is not STATUS: ok|partial|blocked|failed"
# end:contract-status
# rule:contract-verdict
if [ -z "$problem" ] && [ "$type" = harness:reviewer ] && [ "$status" = ok ] &&
  ! printf '%s\n' "$msg" | grep -Eq '^VERDICT: (Approved|Needs fixes|Re-implementation recommended)$'; then
  problem="there is no VERDICT: Approved|Needs fixes|Re-implementation recommended line"
fi
# end:contract-verdict
# rule:contract-artifact
if [ -z "$problem" ]; then
  art=$(printf '%s\n' "$msg" | sed -n 's/^ARTIFACT: //p' | head -n 1)
  case "$art" in /*) f=$art ;; *) f=${cwd:-.}/$art ;; esac
  if [ -z "$art" ]; then
    problem="there is no ARTIFACT: <report path> line"
  elif [ ! -f "$f" ]; then
    problem="the ARTIFACT file $art does not exist; write the report there first"
  fi
fi
# end:contract-artifact
# rule:contract-length
if [ -z "$problem" ] && [ "$(printf '%s\n' "$msg" | wc -l)" -gt 8 ]; then
  problem="the reply is longer than 8 lines; the details belong in the ARTIFACT file"
fi
# end:contract-length
[ -n "$problem" ] || exit 0
jq -n --arg r "Your final reply breaks the reply format of your agent file: $problem. Reply again with only the block from the Report section of your agent file (STATUS, then VERDICT for a review, ARTIFACT, SUMMARY with at most three lines), no other text." \
  '{decision:"block",reason:$r}'
exit 0
