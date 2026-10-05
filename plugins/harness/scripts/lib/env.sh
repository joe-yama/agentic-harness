#!/usr/bin/env bash
# HARNESS_* for agents without a per-repository hook environment (Codex, Copilot CLI).
# Source it; it defines functions only.

# harness_env <dir>
# For each listed HARNESS_* variable that is unset (set-but-empty counts as set), exports its string
# value from <git root of dir>/.harness/env.json. Claude Code sets them through .claude/settings.json
# env, which therefore wins. The guard relaxations HARNESS_ALLOW_LEASE_PUSH and HARNESS_RM_RF_ALLOW
# are never read from the file: an agent can write repository files.
harness_env() {
  local root f n v
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  f=$root/.harness/env.json
  [ -f "$f" ] || return 0
  # rule:env-file-read
  for n in HARNESS_LINT_CMD HARNESS_LINT_PATTERN HARNESS_TEST_CMD HARNESS_DOC_PATTERN HARNESS_PROTECTED_BRANCHES; do
    eval "[ -n \"\${$n+x}\" ]" && continue # bash 3.2: no ${!n+x}; n comes from the fixed list above
    v=$(jq -r --arg n "$n" '.[$n] | strings' "$f" 2>/dev/null) || continue
    [ -n "$v" ] || continue
    printf -v "$n" '%s' "$v"
    export "${n?}"
  done
  # end:env-file-read
  return 0
}
