#!/usr/bin/env bash
# harness subagent-start — SubagentStart hook (Claude Code).
# Records the subagent for watchdog.sh (lib/runs.sh): transcript path, start time, type.
# Prints nothing and never blocks; without jq or CLAUDE_PLUGIN_DATA (set for plugin hooks) it does nothing.
# SubagentStart carries no agent_transcript_path (Claude Code 2.1.289), so the path is derived from the
# session's transcript_path: <transcript without .jsonl>/subagents/agent-<agent_id>.jsonl.
set -u
command -v jq >/dev/null 2>&1 || exit 0
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || exit 0
# shellcheck source=lib/runs.sh
. "$(dirname "$0")/lib/runs.sh" 2>/dev/null && declare -F run_dir >/dev/null || exit 0
input=$(cat)
j() { printf '%s' "$input" | jq -r "$1 | strings" 2>/dev/null; }
dir=$(run_dir "$CLAUDE_PLUGIN_DATA" "$(j .session_id)" "$(j .agent_id)") || exit 0
tp=$(j .transcript_path)
t=
case "$tp" in *.jsonl) t="${tp%.jsonl}/subagents/agent-$(basename "$dir").jsonl" ;; esac
mkdir -p "$dir" || exit 0
# rule:start-reset
# a subagent resumed after it stopped is watched again
rm -f "$dir/done" "$dir/alerted"
# end:start-reset
# rule:start-record
printf '%s' "$t" > "$dir/transcript"
date +%s > "$dir/start"
j .agent_type > "$dir/type"
# end:start-record
exit 0
