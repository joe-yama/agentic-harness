#!/usr/bin/env bash
# harness test-on-stop — Stop hook.
# Runs HARNESS_STOP_TEST_CMD, or HARNESS_TEST_CMD when that is unset or empty, before Claude ends
# its turn when non-doc files have uncommitted changes; on failure returns {"decision":"block"} so
# Claude keeps working. HARNESS_STOP_TEST_CMD is for a faster command than the full suite, such as
# `vitest run --changed HEAD` or `pytest --testmon`: the hook pays it every turn, not every commit.
# An untracked directory holding a .git file or directory (a worktree such as .worktrees/<name>/,
# or another repository) is another checkout's work and does not count as a change.
# stop_hook_active (set after a previous block) ends the loop.
# {"decision":"block"} rather than hookSpecificOutput.additionalContext: both keep the turn going
# under the same stop_hook_active protection, but every Claude Code version honors decision:block,
# while a client that ignores additionalContext would let the turn end with failing tests.
set -u
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
# shellcheck source=lib/env.sh
. "$(dirname "$0")/lib/env.sh" 2>/dev/null # a missing file only means no values from .harness/env.json
declare -F harness_env >/dev/null && harness_env "$cwd"
# rule:stop-unset
[ -n "${HARNESS_STOP_TEST_CMD:-}${HARNESS_TEST_CMD:-}" ] || exit 0
# end:stop-unset
# rule:stop-fast-cmd
cmd=${HARNESS_STOP_TEST_CMD:-$HARNESS_TEST_CMD}
# end:stop-fast-cmd
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
doc=${HARNESS_DOC_PATTERN:-'\.(md|txt)$|^docs/|^openspec/|^\.claude/'}
# rule:stop-bad-pattern
# grep exits 2 on an invalid regex; unchecked, no change would count as code and tests would be skipped silently
grep -Eq -- "$doc" </dev/null
if [ $? = 2 ]; then
  jq -n --arg r "invalid HARNESS_DOC_PATTERN (not an extended regex): $doc. Fix it in .claude/settings.json (Claude Code) or ask the PO to fix it in .harness/env.json (Codex, Copilot CLI); tests were not run." \
    '{decision:"block",reason:$r}'
  exit 0
fi
# end:stop-bad-pattern
changed=$(
  {
    git -C "$root" diff --name-only HEAD 2>/dev/null || git -C "$root" diff --name-only
    git -C "$root" diff --name-only --cached
    git -C "$root" ls-files --others --exclude-standard
  } | sort -u
)
# rule:stop-nested-checkout
# git lists an untracked repository or worktree as "<dir>/" without descending into it.
# The case pattern opens with "(": bash 3.2 misreads a bare ")" inside $(...).
changed=$(printf '%s\n' "$changed" | while IFS= read -r p; do
  case "$p" in (*/) [ -e "$root/$p.git" ] && continue ;; esac
  printf '%s\n' "$p"
done)
# end:stop-nested-checkout
# rule:stop-doc-only
code=$(printf '%s\n' "$changed" | grep -v '^$' | grep -Ev -- "$doc" || true)
[ -n "$code" ] || exit 0
# end:stop-doc-only
# rule:stop-run
out=$(cd "$root" && bash -c "$cmd" 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  reason=$(printf 'Tests failed (%s, exit %d). Fix the failures before finishing; do not skip, delete or weaken tests.\n%s' \
    "$cmd" "$status" "$(printf '%s\n' "$out" | tail -30)")
  jq -n --arg r "$reason" '{decision:"block",reason:$r}'
fi
# end:stop-run
exit 0
