#!/usr/bin/env bash
# shellcheck disable=SC2016 # assertions are single-quoted on purpose: check() evals them later
# Manifest consistency checks, plus `claude plugin validate --strict` when the CLI exists.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=lib.sh
. "$repo/tests/lib.sh"
cd "$repo" || exit 1
# shellcheck disable=SC2034 # m and p are read only by the evals in check()
m=.claude-plugin/marketplace.json p=plugins/harness/.claude-plugin/plugin.json
h=plugins/harness/hooks/hooks.json
check() { if eval "$2"; then ok; else ng "$1"; fi; }

check m-name '[ "$(jq -r .name $m)" = agentic-harness ]'
check m-plugin '[ "$(jq -r ".plugins[0].name" $m)" = harness ] && [ "$(jq -r ".plugins[0].source" $m)" = ./plugins/harness ]'
check m-no-version '[ -z "$(jq -r ".plugins[0].version // empty" $m)" ]'
check m-cross '! jq -e "has(\"allowCrossMarketplaceDependenciesOn\")" $m >/dev/null'
check p-name '[ "$(jq -r .name $p)" = harness ]'
# X.Y.Z or X.Y.Z-rc.N (a release candidate gets its own cache directory)
# shellcheck disable=SC2034 # read only by the evals in check()
semver='^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'
check p-semver 'jq -r .version $p | grep -Eq "$semver"'
check p-semver-forms 'echo 0.4.0 | grep -Eq "$semver" && echo 0.4.0-rc.1 | grep -Eq "$semver" && ! echo 0.4.0-rc | grep -Eq "$semver" && ! echo 0.4.0-beta.1 | grep -Eq "$semver"'
check p-dep '! jq -e "has(\"dependencies\")" $p >/dev/null'
check p-changelog 'grep -q "^## \[$(jq -r .version $p)\]" CHANGELOG.md'
# string form: Codex and Copilot CLI do not run the exec form (command + args), so every hook is
# `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"`; the quotes keep a path with spaces in one argument
hooks='[.hooks[][].hooks[]]'
check h-has-scripts 'jq -r "${hooks}[].command" $h | grep -q "scripts/"'
check h-string-form 'jq -e "$hooks | all(.type == \"command\" and (has(\"args\") | not))" $h >/dev/null && ! jq -r "${hooks}[].command" $h | grep -vE "^bash \"\\\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[a-z-]+\.sh\"\$" | grep -q .'
while IFS= read -r s; do
  check "h-exists-$s" "[ -f plugins/harness/$s ]"
done < <(jq -r "${hooks}[].command" $h | grep -oE 'scripts/[a-z-]+\.sh')
check h-monitor '[ "$(jq -r "[.hooks.PreToolUse[] | select(.matcher == \"Bash|Monitor\")] | length" $h)" = 1 ]'
check h-plugin-root '! jq -r "${hooks}[].command" $h | grep -vE "^bash \"\\\$\{CLAUDE_PLUGIN_ROOT\}/scripts/" | grep -q .'
check h-patch-matcher '[ "$(jq -r "[.hooks.PreToolUse[] | select(.matcher == \"Read|Edit|Write|MultiEdit|NotebookEdit|apply_patch\")] | length" $h)" = 1 ]'
for s in plugins/harness/scripts/*.sh; do
  check "h-wired-$(basename "$s")" "grep -qF 'scripts/$(basename "$s")' $h"
done
# No skill, agent, hook or template file may call a Superpowers skill (`superpowers:<skill>`).
# The settings line `"superpowers@claude-plugins-official": false` has no colon after the name,
# so it does not match. Offending lines (path:line:text) print on stdout.
check no-superpowers '! grep -rnI "superpowers:" plugins template'
# Skills and agents are agent-neutral: Claude-only mechanisms appear only in table rows (per-agent tables).
# adopt is included: its per-agent subsections keep Claude-only tokens in table rows.
# Offending lines (path:line:text) print on stdout.
check neutral-skills '! grep -rnE "subagent_type|/goal|claude -p|scratchpad|SendMessage|Claude Code builds|/opsx:" plugins/harness/skills plugins/harness/agents | grep -vE "^[^:]+:[0-9]+:\|"'
if command -v claude >/dev/null 2>&1; then
  check validate-marketplace 'claude plugin validate . --strict >/dev/null 2>&1'
  check validate-plugin 'claude plugin validate plugins/harness --strict >/dev/null 2>&1'
else
  echo "manifest: claude CLI not found; validate skipped" >&2
fi
report manifest
