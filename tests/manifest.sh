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
check m-cross '[ "$(jq -r ".allowCrossMarketplaceDependenciesOn[0]" $m)" = claude-plugins-official ]'
check p-name '[ "$(jq -r .name $p)" = harness ]'
check p-semver 'jq -r .version $p | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+$"'
check p-dep '[ "$(jq -r ".dependencies[] | select(.name==\"superpowers\") | .marketplace" $p)" = claude-plugins-official ]'
check p-changelog 'grep -q "^## \[$(jq -r .version $p)\]" CHANGELOG.md'
check h-has-scripts 'jq -r ".. | .command? // empty" $h | grep -q "scripts/"'
while IFS= read -r s; do
  check "h-exists-$s" "[ -f plugins/harness/$s ]"
done < <(jq -r '.. | .command? // empty' $h | grep -oE 'scripts/[a-z-]+\.sh')
check h-monitor '[ "$(jq -r "[.hooks.PreToolUse[] | select(.matcher == \"Bash|Monitor\")] | length" $h)" = 1 ]'
check h-plugin-root '! jq -r ".. | .command? // empty" $h | grep -vF "\${CLAUDE_PLUGIN_ROOT}" | grep -q .'
for s in plugins/harness/scripts/*.sh; do
  check "h-wired-$(basename "$s")" "grep -qF 'scripts/$(basename "$s")' $h"
done
if command -v claude >/dev/null 2>&1; then
  check validate-marketplace 'claude plugin validate . --strict >/dev/null 2>&1'
  check validate-plugin 'claude plugin validate plugins/harness --strict >/dev/null 2>&1'
else
  echo "manifest: claude CLI not found; validate skipped" >&2
fi
report manifest
