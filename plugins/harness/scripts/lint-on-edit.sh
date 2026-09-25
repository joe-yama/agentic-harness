#!/usr/bin/env bash
# harness lint-on-edit — PostToolUse hook (Edit|Write|MultiEdit).
# Runs HARNESS_LINT_CMD on the edited file; on failure exits 2 so Claude fixes it now.
# The file path is passed as a separate argument, never spliced into the command string.
# Files outside a git repository, docs (HARNESS_DOC_PATTERN) and paths not matching
# HARNESS_LINT_PATTERN are skipped.
set -u
# rule:lint-unset
[ -n "${HARNESS_LINT_CMD:-}" ] || exit 0
# end:lint-unset
if ! command -v jq >/dev/null 2>&1; then
  echo "harness lint-on-edit: jq not found; lint skipped" >&2
  exit 0
fi
input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // ""')
[ -n "$file" ] && [ -f "$file" ] || exit 0
dir=$(cd "$(dirname "$file")" && pwd -P) || exit 0
abs="$dir/$(basename "$file")"
# rule:lint-outside-repo
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
# end:lint-outside-repo
root=$(cd "$root" && pwd -P) || exit 0
rel=${abs#"$root"/}
doc=${HARNESS_DOC_PATTERN:-'\.(md|txt)$|^docs/|^openspec/|^\.claude/'}
# rule:lint-doc-skip
printf '%s' "$rel" | grep -Eq -- "$doc" && exit 0
# end:lint-doc-skip
# rule:lint-pattern
if [ -n "${HARNESS_LINT_PATTERN:-}" ]; then
  printf '%s' "$rel" | grep -Eq -- "$HARNESS_LINT_PATTERN" || exit 0
fi
# end:lint-pattern
# rule:lint-run
out=$(cd "$root" && bash -c "$HARNESS_LINT_CMD \"\$1\"" harness-lint "$abs" 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  {
    printf 'lint failed after editing %s (exit %d). Fix it before continuing:\n' "$rel" "$status"
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi
# end:lint-run
exit 0
