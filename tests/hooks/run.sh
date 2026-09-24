#!/usr/bin/env bash
# Runs every case in tests/hooks/cases.tsv against guard.sh / ask-gate.sh.
# HOOKS_DIR overrides the script directory (used by mutate.sh).
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
# shellcheck source=../lib.sh
. "$repo/tests/lib.sh"
setup_git_env
HOOKS_DIR=${HOOKS_DIR:-$repo/plugins/harness/scripts}

for b in main feature; do
  git init -q "$TMP_ROOT/$b"
  git -C "$TMP_ROOT/$b" commit -q --allow-empty -m init
  [ "$b" = feature ] && git -C "$TMP_ROOT/$b" checkout -q -b feature/x
done
mkdir -p "$TMP_ROOT/none"

while IFS=$'\t' read -r id script where envkv expect payload; do
  case "$id" in '' | '#'*) continue ;; esac
  cwd="$TMP_ROOT/$where"
  case "$payload" in
    bash:*)
      json=$(jq -nc --arg c "${payload#bash:}" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}') ;;
    file:*)
      rest=${payload#file:}
      tool=${rest%%:*}
      path=${rest#*:}
      json=$(jq -nc --arg t "$tool" --arg p "$path" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{file_path:$p},cwd:$d}') ;;
    *)
      ng "$id: bad payload"
      continue ;;
  esac
  if [ "$envkv" = "-" ]; then
    out=$(cd "$cwd" && printf '%s' "$json" | bash "$HOOKS_DIR/$script.sh" 2>/dev/null)
  else
    out=$(cd "$cwd" && printf '%s' "$json" | env "$envkv" bash "$HOOKS_DIR/$script.sh" 2>/dev/null)
  fi
  rc=$?
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 2 ]; then
    got=block
  elif [ "$rc" -eq 0 ] && [ "$decision" = ask ]; then
    got=ask
  elif [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    got=pass
  else
    got="rc=$rc out=$out"
  fi
  if [ "$got" = "$expect" ]; then ok; else ng "$id [$script] expected $expect, got $got :: $payload"; fi
done < "$here/cases.tsv"

report "hook cases"
