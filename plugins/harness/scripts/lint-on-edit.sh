#!/usr/bin/env bash
# harness lint-on-edit — PostToolUse hook (Edit|Write|MultiEdit|apply_patch).
# Runs HARNESS_LINT_CMD on every edited file. On failure prints `decision: block` with the lint
# output (Copilot CLI, whose payload has tool_result: a top-level `additionalContext` alone) so the
# agent fixes it now.
# The file path is passed as a separate argument, never spliced into the command string.
# Files outside a git repository, docs (HARNESS_DOC_PATTERN) and paths not matching
# HARNESS_LINT_PATTERN are skipped.
set -u
# rule:lint-unset
[ -n "${HARNESS_LINT_CMD:-}" ] || exit 0
# end:lint-unset
# rule:no-jq
if ! command -v jq >/dev/null 2>&1; then
  echo "harness lint-on-edit: jq not found; lint skipped" >&2
  exit 0
fi
# end:no-jq
doc=${HARNESS_DOC_PATTERN:-'\.(md|txt)$|^docs/|^openspec/|^\.claude/'}
# rule:lint-bad-pattern
# grep exits 2 on an invalid regex; unchecked, every file would be skipped (or linted) silently
check_pattern() { # <name> <regex>
  grep -Eq -- "$2" </dev/null
  [ $? != 2 ] && return 0
  echo "harness lint-on-edit: invalid $1 (not an extended regex): $2" >&2
  exit 2
}
check_pattern HARNESS_LINT_PATTERN "${HARNESS_LINT_PATTERN:-}"
check_pattern HARNESS_DOC_PATTERN "$doc"
# end:lint-bad-pattern
input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] || cwd=$(pwd)
# tool_input is an object (Claude Code, Codex, Copilot Write) or a string (Copilot's Edit: patch text
# or a JSON object); the object may hold a patch in command/input (Codex apply_patch)
# rule:lint-paths
# Claude Code: file_path (or tool_response.filePath); Copilot CLI: path
files=$(printf '%s' "$input" | jq -r '(.tool_input | if type == "string" then (fromjson? | objects) else objects end) as $o | [$o.file_path, $o.path, .tool_response.filePath? | strings] | .[0] // empty')
# end:lint-paths
# rule:lint-patch
# apply_patch envelope: every file it adds, updates or moves to (deleted files no longer exist)
body=$(printf '%s' "$input" | jq -r '.tool_input | if type == "string" then . else (.command // .input // "") end | strings')
if printf '%s\n' "$body" | grep -Eq '^[[:space:]]*\*\*\* (Add File|Update File|Delete File|Move to):'; then
  # shellcheck source=lib/parse.sh
  . "$(dirname "$0")/lib/parse.sh" 2>/dev/null
  parsed=$?
  if [ "$parsed" != 0 ] || ! declare -F patch_paths >/dev/null; then
    echo "harness lint-on-edit: lib/parse.sh is missing or broken; reinstall the plugin" >&2
    exit 2
  fi
  files=$(patch_paths "$body")
fi
# end:lint-patch
report=''
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in /*) ;; *) file=$cwd/$file ;; esac
  [ -f "$file" ] || continue
  dir=$(cd "$(dirname "$file")" && pwd -P) || continue
  abs="$dir/$(basename "$file")"
  # rule:lint-outside-repo
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
  # end:lint-outside-repo
  root=$(cd "$root" && pwd -P) || continue
  rel=${abs#"$root"/}
  # rule:lint-doc-skip
  printf '%s' "$rel" | grep -Eq -- "$doc" && continue
  # end:lint-doc-skip
  # rule:lint-pattern
  if [ -n "${HARNESS_LINT_PATTERN:-}" ]; then
    printf '%s' "$rel" | grep -Eq -- "$HARNESS_LINT_PATTERN" || continue
  fi
  # end:lint-pattern
  # rule:lint-run
  out=$(cd "$root" && bash -c "$HARNESS_LINT_CMD \"\$1\"" harness-lint "$abs" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    report=$report$(printf 'lint failed after editing %s (exit %d). Fix it before continuing:\n%s' \
      "$rel" "$status" "$(printf '%s\n' "$out" | tail -40)")$'\n'
  fi
  # end:lint-run
done <<END_FILES
$files
END_FILES
# rule:lint-report
if [ -n "$report" ]; then
  if printf '%s' "$input" | jq -e 'has("tool_result")' >/dev/null 2>&1; then
    # Copilot CLI: only a top-level additionalContext reaches the model; decision:block would hide
    # the tool output and mark the applied edit as failed
    jq -n --arg r "$report" '{additionalContext:$r}'
  else
    # Claude Code and Codex read decision:block
    jq -n --arg r "$report" '{decision:"block",reason:$r,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$r}}'
  fi
fi
# end:lint-report
exit 0
