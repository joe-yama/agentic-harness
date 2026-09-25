#!/usr/bin/env bash
# harness test-on-stop — Stop hook.
# Runs HARNESS_TEST_CMD before Claude ends its turn when non-doc files have uncommitted
# changes; on failure returns {"decision":"block"} so Claude keeps working.
# stop_hook_active (set after a previous block) ends the loop.
set -u
# rule:stop-unset
[ -n "${HARNESS_TEST_CMD:-}" ] || exit 0
# end:stop-unset
# rule:no-jq
if ! command -v jq >/dev/null 2>&1; then
  echo "harness test-on-stop: jq not found; tests skipped" >&2
  exit 0
fi
# end:no-jq
input=$(cat)
# rule:stop-active
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = true ] && exit 0
# end:stop-active
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] || cwd=$(pwd)
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
doc=${HARNESS_DOC_PATTERN:-'\.(md|txt)$|^docs/|^openspec/|^\.claude/'}
changed=$(
  {
    git -C "$root" diff --name-only HEAD 2>/dev/null || git -C "$root" diff --name-only
    git -C "$root" diff --name-only --cached
    git -C "$root" ls-files --others --exclude-standard
  } | sort -u
)
# rule:stop-doc-only
code=$(printf '%s\n' "$changed" | grep -v '^$' | grep -Ev -- "$doc" || true)
[ -n "$code" ] || exit 0
# end:stop-doc-only
# rule:stop-run
out=$(cd "$root" && bash -c "$HARNESS_TEST_CMD" 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  reason=$(printf 'Tests failed (%s, exit %d). Fix the failures before finishing; do not skip, delete or weaken tests.\n%s' \
    "$HARNESS_TEST_CMD" "$status" "$(printf '%s\n' "$out" | tail -30)")
  jq -n --arg r "$reason" '{decision:"block",reason:$r}'
fi
# end:stop-run
exit 0
