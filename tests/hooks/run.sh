#!/usr/bin/env bash
# Runs every case in tests/hooks/cases.tsv against guard.sh / ask-gate.sh.
# expect: block:<id> | ask:<id> | pass, where <id> is the reason id the hook prints.
# Payloads: bash:<command>, bashe:<command with printf %b escapes>, bashpad:<length>:<command>,
# monitor:<command>, file:<Tool>:<path>,
# raw:<hook input sent as is>.
# env: - for none, or NAME=value assignments separated by ";" (a value may contain blanks).
# @T@ in env and payload is the fixture tree for rm prefixes: work/real/, outside/, and symlinks
# work/out -> outside, link -> work, top -> /usr.
# HOOKS_DIR overrides the script directory (used by mutate.sh).
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
# shellcheck source=../lib.sh
. "$repo/tests/lib.sh"
setup_git_env
HOOKS_DIR=${HOOKS_DIR:-$repo/plugins/harness/scripts}
HOOK_BASH=${HOOK_BASH:-bash} # e.g. /bin/bash to test macOS bash 3.2

for b in main feature; do
  git init -q "$TMP_ROOT/$b"
  git -C "$TMP_ROOT/$b" commit -q --allow-empty -m init
  [ "$b" = feature ] && git -C "$TMP_ROOT/$b" checkout -q -b feature/x
done
git init -q "$TMP_ROOT/envrepo"
git -C "$TMP_ROOT/envrepo" commit -q --allow-empty -m init
mkdir -p "$TMP_ROOT/envrepo/.harness"
printf '%s\n' '{"HARNESS_PROTECTED_BRANCHES":"release","HARNESS_RM_RF_ALLOW":"/tmp/x:/var/tmp/y","HARNESS_ALLOW_LEASE_PUSH":"1"}' > "$TMP_ROOT/envrepo/.harness/env.json"
mkdir -p "$TMP_ROOT/none"
FX="$TMP_ROOT/fx"
mkdir -p "$FX/work/real" "$FX/outside"
ln -s ../outside "$FX/work/out"
ln -s work "$FX/link"
ln -s /usr "$FX/top"

while IFS=$'\t' read -r id script where envkv expect payload; do
  case "$id" in '' | '#'*) continue ;; esac
  envkv=${envkv//@T@/$FX}
  payload=${payload//@T@/$FX}
  cwd="$TMP_ROOT/$where"
  case "$payload" in
    bash:* | bashe:* | bashpad:* | monitor:*)
      # bashe: interprets printf %b escapes (\n for newlines); monitor: sends the Monitor tool;
      # bashpad:<n>:<command> appends " ; : aaa..." until the command is exactly n characters
      tname=Bash
      case "$payload" in
        bashe:*) c=$(printf '%b' "${payload#bashe:}") ;;
        bashpad:*)
          rest=${payload#bashpad:}
          n=${rest%%:*}
          c="${rest#*:} ; : "
          c="$c$(printf '%*s' "$((n - ${#c}))" '' | tr ' ' a)"
          ;;
        monitor:*) c=${payload#monitor:} tname=Monitor ;;
        *) c=${payload#bash:} ;;
      esac
      json=$(jq -nc --arg c "$c" --arg t "$tname" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{command:$c},cwd:$d}') ;;
    file:*)
      rest=${payload#file:}
      tool=${rest%%:*}
      path=${rest#*:}
      json=$(jq -nc --arg t "$tool" --arg p "$path" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{file_path:$p},cwd:$d}') ;;
    patch:* | patchraw:*)
      # patch:<Tool>:<path>[,<path>...] builds an apply_patch envelope (Codex) that updates each path
      # with a body full of dangerous command text; patchraw:<Tool>:<text with printf %b escapes>
      rest=${payload#*:}
      tool=${rest%%:*}
      rest=${rest#*:}
      if [ "${payload%%:*}" = patch ]; then
        body='*** Begin Patch\n'
        IFS=',' read -r -a ps <<<"$rest"
        for p in "${ps[@]}"; do body="$body*** Update File: $p\n@@\n-old\n+rm -rf / && git push --force origin main\n"; done
        body="$body*** End Patch"
      else
        body=$rest
      fi
      c=$(printf '%b' "$body")
      json=$(jq -nc --arg t "$tool" --arg c "$c" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{command:$c},cwd:$d}') ;;
    cpatch:*)
      # cpatch:<Tool>:<printf %b text>: Copilot CLI sends tool_input as a string (F4)
      rest=${payload#cpatch:}
      tool=${rest%%:*}
      c=$(printf '%b' "${rest#*:}")
      json=$(jq -nc --arg t "$tool" --arg c "$c" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:$c,cwd:$d}') ;;
    cfile:*)
      # cfile:<Tool>:<path> is a file tool in Copilot CLI's shape (tool_input.path, per F4)
      rest=${payload#cfile:}
      tool=${rest%%:*}
      path=${rest#*:}
      json=$(jq -nc --arg t "$tool" --arg p "$path" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{path:$p},cwd:$d}') ;;
    raw:*)
      json=${payload#raw:} ;;
    *)
      ng "$id: bad payload"
      continue ;;
  esac
  errf="$TMP_ROOT/stderr"
  if [ "$envkv" = "-" ]; then
    out=$(cd "$cwd" && printf '%s' "$json" | "$HOOK_BASH" "$HOOKS_DIR/$script.sh" 2>"$errf")
  else
    IFS=';' read -r -a envs <<<"$envkv"
    out=$(cd "$cwd" && printf '%s' "$json" | env "${envs[@]}" "$HOOK_BASH" "$HOOKS_DIR/$script.sh" 2>"$errf")
  fi
  rc=$?
  cop=0
  case ";$envkv;" in *";COPILOT_CLI=1;"*) cop=1 ;; esac
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$rc" -eq 2 ] && [ "$script" = guard ] && [ "$cop" = 1 ]; then
    got="rc=2 (Copilot form must exit 0 with JSON)"
  elif [ "$rc" -eq 2 ]; then
    # the id printed in "BLOCKED by harness guard (<id>): ..."
    got=block:$(sed -n 's/^BLOCKED by harness guard (\([a-z0-9-]*\)).*/\1/p' "$errf" | head -n 1)
  elif [ "$rc" -eq 0 ] && [ "$script" = guard ] && [ "$cop" != 1 ] && [ "$decision" = deny ]; then
    # a JSON deny without exactly COPILOT_CLI=1 in the env is a defect: exit 2 is the contract
    got="rc=0 JSON deny without COPILOT_CLI=1 (must exit 2)"
  elif [ "$rc" -eq 0 ] && [ "$decision" = deny ] \
    && ! printf '%s' "$out" | jq -e 'keys == ["hookSpecificOutput"]' >/dev/null 2>&1; then
    # top-level keys next to hookSpecificOutput make Codex fail open (R14)
    got="rc=0 JSON deny with top-level keys (only hookSpecificOutput allowed)"
  elif [ "$rc" -eq 0 ] && [ "$decision" = deny ]; then
    # Copilot CLI form (COPILOT_CLI=1): only the nested deny as JSON on stdout, exit 0
    got=block:$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' \
      | sed -n 's/^BLOCKED by harness guard (\([a-z0-9-]*\)).*/\1/p')
  elif [ "$rc" -eq 0 ] && [ "$decision" = ask ]; then
    # the id in permissionDecisionReason "harness ask-gate (<id>): ..."
    got=ask:$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' \
      | sed -n 's/^harness ask-gate (\([a-z0-9-]*\)).*/\1/p')
  elif [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    got=pass
  else
    got="rc=$rc out=$out"
  fi
  if [ "$got" = "$expect" ]; then ok; else ng "$id [$script] expected $expect, got $got :: $payload"; fi
done < "$here/cases.tsv"

report "hook cases"
