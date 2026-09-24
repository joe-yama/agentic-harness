#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034 # assertions are single-quoted and read variables only inside check()'s eval
# Renders the Copier template from a committed snapshot of this working tree and checks the output.
set -u
repo=$(cd "$(dirname "$0")/../.." && pwd -P)
# shellcheck source=../lib.sh
. "$repo/tests/lib.sh"
setup_git_env
COPIER="uvx copier@9.18.2"
CJS="uvx check-jsonschema@0.38.2"
SCHEMA="https://raw.githubusercontent.com/SchemaStore/schemastore/3b2dae966d5e93b94b83cf649d5e1ad583a19ddb/src/schemas/json/claude-code-settings.json"
check() { if eval "$2"; then ok; else ng "$1"; fi; }

# Snapshot the working tree (tracked + untracked, not ignored) into a git repo tagged v9.9.0.
SRC="$TMP_ROOT/src"
mkdir -p "$SRC"
(cd "$repo" && git ls-files -co --exclude-standard | tar -c -T -) | tar -x -C "$SRC"
git -C "$SRC" init -q && git -C "$SRC" add -A && git -C "$SRC" commit -q -m snapshot && git -C "$SRC" tag v9.9.0

render() { # <dest> <vcs-ref> [--data k=v ...]
  local dest=$1 ref=$2
  shift 2
  if ! $COPIER copy --quiet --defaults --overwrite --vcs-ref "$ref" \
    --data project_name=Sample --data github_owner=octo "$@" "$SRC" "$dest" > "$TMP_ROOT/copier.log" 2>&1; then
    ng "copier copy $dest failed"
    tail -20 "$TMP_ROOT/copier.log" >&2
  fi
}
settings() { jq -r "$2" "$1/.claude/settings.json"; }
common() { # <name> <dest>
  local n=$1 d=$2
  check "$n-rendered" '[ -f "$d/AGENTS.md" ] && [ -f "$d/CLAUDE.md" ] && [ -f "$d/.claude/settings.json" ]'
  check "$n-no-jinja" '! grep -rIlE "\{\{|\{%" "$d" --exclude-dir=.git --exclude=ci.yml | grep -q .'
  check "$n-json" 'jq -e . "$d/.claude/settings.json" >/dev/null && jq -e . "$d/docs/harness/ruleset.json" >/dev/null'
  check "$n-schema" '$CJS --schemafile "$SCHEMA" "$d/.claude/settings.json" >/dev/null 2>&1'
  check "$n-workflow-schema" '$CJS --builtin-schema vendor.github-workflows "$d/.github/workflows/ci.yml" >/dev/null 2>&1'
  check "$n-dependabot-schema" '$CJS --builtin-schema vendor.dependabot "$d/.github/dependabot.yml" >/dev/null 2>&1'
  check "$n-budget" '[ "$(cat "$d/AGENTS.md" "$d/CLAUDE.md" "$d"/.claude/rules/*.md | wc -c)" -le 16000 ]'
  check "$n-plugin" '[ "$(settings "$d" ".enabledPlugins[\"harness@agentic-harness\"]")" = true ]'
  check "$n-answers" '[ -f "$d/.copier-answers.yml" ]'
  check "$n-claude-imports" '[ "$(head -1 "$d/CLAUDE.md")" = "@AGENTS.md" ]'
}

D1="$TMP_ROOT/defaults"
render "$D1" v9.9.0
common defaults "$D1"
check defaults-ref '[ "$(settings "$D1" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = v9.9.0 ]'
check defaults-no-lint '[ "$(settings "$D1" ".env.HARNESS_LINT_CMD // \"unset\"")" = unset ]'
check defaults-teams-off '[ "$(settings "$D1" .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)" = 0 ]'
check defaults-branch '[ "$(settings "$D1" .env.HARNESS_PROTECTED_BRANCHES)" = main ]'
check defaults-no-mcp '[ ! -e "$D1/.mcp.json" ]'
check defaults-lang 'grep -q "Japanese" "$D1/AGENTS.md" && grep -q "Japanese" "$D1/openspec/config.yaml"'

D2="$TMP_ROOT/node"
render "$D2" v9.9.0 --data 'lint_cmd=pnpm exec biome check --error-on-warnings --no-errors-on-unmatched' \
  --data 'lint_pattern=\.(ts|tsx|js|astro)$' --data 'test_cmd=pnpm test' --data work_language=en --data default_branch=trunk
common node "$D2"
check node-lint '[ "$(settings "$D2" .env.HARNESS_LINT_CMD)" = "pnpm exec biome check --error-on-warnings --no-errors-on-unmatched" ]'
check node-pattern '[ "$(settings "$D2" .env.HARNESS_LINT_PATTERN)" = "\\.(ts|tsx|js|astro)\$" ]'
check node-branch '[ "$(settings "$D2" .env.HARNESS_PROTECTED_BRANCHES)" = trunk ] && grep -q "\[trunk\]" "$D2/.github/workflows/ci.yml"'
check node-lang 'grep -q "English" "$D2/AGENTS.md"'
check node-commands 'grep -qF "pnpm test" "$D2/AGENTS.md"'

D3="$TMP_ROOT/python"
render "$D3" v9.9.0 --data 'test_cmd=uv run pytest -q' --data ui_review=true --data 'lint_cmd=uv run ruff check' --data 'lint_pattern=\.py$'
common python "$D3"
check python-mcp 'jq -e ".mcpServers.playwright.args | index(\"@playwright/mcp@0.0.82\")" "$D3/.mcp.json" >/dev/null'
check python-mcp-enabled '[ "$(settings "$D3" ".enabledMcpjsonServers[0]")" = playwright ]'
check python-mcp-allow 'settings "$D3" ".permissions.allow[]" | grep -qx "mcp__playwright__\*"'

# A render from a non-tag commit must not produce a describe-style ref such as v9.9.0-1-gabc.
echo "# dev" >> "$SRC/README.md"
git -C "$SRC" add -A && git -C "$SRC" commit -q -m dev
D4="$TMP_ROOT/untagged"
render "$D4" HEAD
check untagged-ref '[ "$(settings "$D4" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = main ]'

# A source repository without any tag makes _commit a bare SHA, which is not a branch or tag.
NOTAG="$TMP_ROOT/notag"
mkdir -p "$NOTAG"
(cd "$repo" && git ls-files -co --exclude-standard | tar -c -T -) | tar -x -C "$NOTAG"
git -C "$NOTAG" init -q && git -C "$NOTAG" add -A && git -C "$NOTAG" commit -q -m snapshot
D5="$TMP_ROOT/notag-out"
$COPIER copy --quiet --defaults --vcs-ref HEAD --data project_name=Sample --data github_owner=octo "$NOTAG" "$D5" > "$TMP_ROOT/copier.log" 2>&1
check notag-ref '[ "$(settings "$D5" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = main ]'
check notag-status 'grep -q "| agentic-harness | main |" "$D5/docs/status.md"'

# copier update from v9.9.0 to v9.9.1 applies cleanly and moves the pin.
git -C "$D1" init -q && git -C "$D1" add -A && git -C "$D1" commit -q -m init
printf '\n<!-- updated -->\n' >> "$SRC/template/CLAUDE.md.jinja"
git -C "$SRC" commit -q -am update && git -C "$SRC" tag v9.9.1
if ! (cd "$D1" && $COPIER update --quiet --defaults --vcs-ref v9.9.1 > "$TMP_ROOT/update.log" 2>&1); then
  tail -20 "$TMP_ROOT/update.log" >&2
fi
check update-ref '[ "$(settings "$D1" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = v9.9.1 ]'
check update-applied 'grep -q "<!-- updated -->" "$D1/CLAUDE.md"'
check update-no-rej '! find "$D1" -name "*.rej" | grep -q .'

report template
