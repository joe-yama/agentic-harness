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
git -C "$SRC" init -q && git -C "$SRC" add -A && git -C "$SRC" commit -q -m snapshot
# Release tagging as documented: annotated vX.Y.Z, then `claude plugin tag` adds annotated harness--vX.Y.Z.
git -C "$SRC" tag -a v9.9.0 -m v9.9.0 && sleep 1 && git -C "$SRC" tag -a harness--v9.9.0 -m harness--v9.9.0

render() { # <dest> <vcs-ref> [--data k=v ...]
  local dest=$1 ref=$2
  shift 2
  if ! $COPIER copy --quiet --defaults --overwrite --vcs-ref "$ref" \
    --data project_name=Sample --data github_owner=octo "$@" "$SRC" "$dest" > "$TMP_ROOT/copier.log" 2>&1; then
    ng "copier copy $dest failed"
    tail -20 "$TMP_ROOT/copier.log" >&2
  fi
}
# Uses the pinned copier environment, which already ships PyYAML. OpenSpec ignores a rules entry that is not an array of strings (an unquoted "key: value" item breaks it).
rules_ok() { uvx --from copier@9.18.2 python -c 'import sys, yaml
r = yaml.safe_load(open(sys.argv[1]))["rules"]
sys.exit(0 if all(isinstance(r[k], list) and r[k] and all(isinstance(i, str) for i in r[k]) for k in ("design", "tasks")) else 1)' "$1"; }
# The CI step that rejects OpenSpec files we strip. Pulled out of the rendered ci.yml by its name so the test runs the exact script CI runs.
# Fails when the step is missing or has an `if:` (it must not be skippable); the job and the triggers carry no filters of their own.
os_step() { uvx --from copier@9.18.2 python -c 'import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
s = [x for x in w["jobs"]["check"]["steps"] if x.get("name", "").startswith("OpenSpec")]
sys.exit(1) if len(s) != 1 or "if" in s[0] or "if" in w["jobs"]["check"] else print(s[0]["run"])' "$1"; }
# <rendered dir> <relative path>... : runs the step in a copy holding those empty files; output goes to $TMP_ROOT/os.log.
os_run() {
  local d=$1 w run
  shift
  run=$(os_step "$d/.github/workflows/ci.yml") && [ -n "$run" ] || return 99
  w=$(mktemp -d "$TMP_ROOT/os.XXXXXX")
  cp -R "$d/." "$w"
  local f
  for f in "$@"; do mkdir -p "$w/$(dirname "$f")" && : > "$w/$f"; done
  (cd "$w" && bash -e -c "$run") > "$TMP_ROOT/os.log" 2>&1
}
# Reads the rows (lines starting with "|") of the first table of models.md (it stops at the first "## " line). Decision and final review must be Opus / high, implementation and
# intermediate review Sonnet / medium; no row may use another model (Haiku included) or be a planning role (planning is part of the decision).
models_ok() { awk -F'|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return tolower(s) }
  /^## / { exit }
  /^\|/ {
    r = trim($2); m = trim($3); e = trim($4)
    if (m == "model" || m ~ /^[-: ]+$/) next
    if (tolower($0) ~ /haiku/ || r ~ /^plan/ || r ~ /planning/) bad = 1
    if (m != "opus" && m != "sonnet") bad = 1
    if (m == "opus" && e != "high") bad = 1
    if (m == "sonnet" && e != "medium") bad = 1
    if (r ~ /^decision/) { dec++; if (m != "opus") bad = 1 }
    if (r ~ /^final review/) { fin++; if (m != "opus") bad = 1 }
    if (r ~ /^implementation/) { imp++; if (m != "sonnet") bad = 1 }
    if (r ~ /^intermediate review/) { mid++; if (m != "sonnet") bad = 1 }
  }
  END { exit (bad || dec != 1 || fin != 1 || imp != 1 || mid != 1) }' "$1"; }
# rows of the table under "## <heading>": four roles, a model, an effort, no Haiku
agent_models_ok() { awk -F'|' -v h="## $2" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return tolower(s) }
  $0 == h { on = 1; next }
  on && /^## / { on = 0 }
  on && /^\|/ { m = trim($3); if (m == "model" || m ~ /^[-: ]+$/) next; n++; if (m == "" || trim($4) == "" || tolower($0) ~ /haiku/) bad = 1 }
  END { exit (bad || n != 4) }' "$1"; }
# "<role prefix>=<model>/<effort>" lines of the Codex table of models.md, for comparison with .codex/agents/*.toml
codex_table() { awk -F'|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  $0 == "## Codex" { on = 1; next }
  on && /^## / { on = 0 }
  on && /^\|/ { a = trim($5); gsub(/`/, "", a); if (a ~ /^harness-/) print a "=" trim($3) "/" trim($4) }' "$1" | sort; }
codex_toml() { for f in "$1"/.codex/agents/*.toml; do n=$(basename "$f" .toml); printf '%s=%s/%s\n' "$n" "$(sed -n 's/^model = "\(.*\)"$/\1/p' "$f")" "$(sed -n 's/^model_reasoning_effort = "\(.*\)"$/\1/p' "$f")"; done | sort; }
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
  # `claude plugin install --scope project` rewrites settings.json as JSON.stringify(v, null, 2) with
  # its own key order. Rendering that exact form keeps the install a no-op
  # (checked by hand with Claude Code 2.1.282: the file stays byte-identical). `jq --indent 2` matches
  # JSON.stringify for these inputs (it differs only for DEL, which jq escapes).
  check "$n-superpowers" '[ "$(settings "$d" ".enabledPlugins[\"superpowers@claude-plugins-official\"]")" = false ]'
  check "$n-install-format" 'jq --indent 2 . "$d/.claude/settings.json" | cmp -s - "$d/.claude/settings.json"'
  local top='$schema,env,permissions,enabledPlugins,extraKnownMarketplaces,sandbox'
  [ -e "$d/.mcp.json" ] && top='$schema,env,permissions,enabledMcpjsonServers,enabledPlugins,extraKnownMarketplaces,sandbox'
  check "$n-install-order" '[ "$(settings "$d" "keys_unsorted | join(\",\")")" = "$top" ] &&
    [ "$(settings "$d" ".sandbox | keys_unsorted | join(\",\")")" = enabled,autoAllowBashIfSandboxed,network,filesystem,excludedCommands ]'
  check "$n-openspec-rules" 'rules_ok "$d/openspec/config.yaml"'
  check "$n-models-doc" '[ -f "$d/docs/harness/models.md" ] && models_ok "$d/docs/harness/models.md" && ! grep -qF "model: \"opus\"" "$d/CLAUDE.md"'
  check "$n-answers" '[ -f "$d/.copier-answers.yml" ]'
  check "$n-claude-imports" '[ "$(head -1 "$d/CLAUDE.md")" = "@AGENTS.md" ]'
}

D1="$TMP_ROOT/defaults"
render "$D1" v9.9.0
common defaults "$D1"
check defaults-agents 'grep -qx "agents:" "$D1/.copier-answers.yml" && grep -qx -- "- claude" "$D1/.copier-answers.yml"'
check defaults-no-codex '[ ! -e "$D1/.codex" ] && [ ! -e "$D1/.github/copilot" ] && [ ! -e "$D1/.github/copilot-instructions.md" ] && [ ! -e "$D1/.harness" ]'

DC="$TMP_ROOT/codex-only"
render "$DC" v9.9.0 --data 'agents=[codex]'
check codex-rendered '[ -f "$DC/AGENTS.md" ]'
check codex-no-jinja '! grep -rIlE "\{\{|\{%" "$DC" --exclude-dir=.git --exclude=ci.yml | grep -q .'
check codex-workflow-schema '$CJS --builtin-schema vendor.github-workflows "$DC/.github/workflows/ci.yml" >/dev/null 2>&1'
check codex-no-claude '[ ! -e "$DC/CLAUDE.md" ] && [ ! -e "$DC/.claude" ]'
check codex-agents-md '! grep -qF "CLAUDE.md" "$DC/AGENTS.md"'
check codex-ci-budget '$CJS --builtin-schema vendor.github-workflows "$DC/.github/workflows/ci.yml" >/dev/null 2>&1 && ! grep -qF "CLAUDE.md" "$DC/.github/workflows/ci.yml"'
toml_ok() { uvx --from copier@9.18.2 python -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; }
check codex-config 'toml_ok "$DC/.codex/config.toml" && grep -qx "sandbox_mode = \"workspace-write\"" "$DC/.codex/config.toml" && grep -qx "approval_policy = \"on-request\"" "$DC/.codex/config.toml"'
check codex-agents '[ -f "$DC/.codex/agents/harness-implementer.toml" ] && [ -f "$DC/.codex/agents/harness-reviewer.toml" ] && [ -f "$DC/.codex/agents/harness-reviewer-intermediate.toml" ]'
check codex-rules 'grep -qF "prefix_rule(pattern = [\"git\", \"push\"], decision = \"prompt\"" "$DC/.codex/rules/harness.rules" && grep -qF "[\"git\", \"push\", \"--force\"], decision = \"forbidden\"" "$DC/.codex/rules/harness.rules"'
check codex-env 'jq -e ".HARNESS_PROTECTED_BRANCHES == \"main\" and (has(\"HARNESS_RM_RF_ALLOW\") | not) and (has(\"HARNESS_ALLOW_LEASE_PUSH\") | not)" "$DC/.harness/env.json" >/dev/null'
check codex-gitignore 'grep -qx ".harness/\*" "$DC/.gitignore" && grep -qx "!.harness/env.json" "$DC/.gitignore" && ! grep -qx ".harness/" "$DC/.gitignore"'
check codex-section 'grep -qF "## Codex specifics" "$DC/AGENTS.md" && grep -qF "harness-reviewer-intermediate" "$DC/AGENTS.md"'
check defaults-gitignore 'grep -qx ".harness/" "$D1/.gitignore"'
if command -v codex >/dev/null 2>&1; then
  execpolicy() { perl -e 'alarm shift; exec @ARGV' 120 codex execpolicy check --rules "$DC/.codex/rules/harness.rules" "$@" </dev/null; }
  check codex-execpolicy '[ "$(execpolicy git push --force origin x | jq -r .decision)" = forbidden ] && [ "$(execpolicy git push -f origin x | jq -r .decision)" = forbidden ] && [ "$(execpolicy git push origin x | jq -r .decision)" = prompt ] && [ "$(execpolicy git push --force-with-lease origin x | jq -r .decision)" = forbidden ] && [ "$(execpolicy pnpm i | jq -r .decision)" = prompt ] && [ "$(execpolicy uv sync | jq -r .decision)" = prompt ] && [ "$(execpolicy pip3 install x | jq -r .decision)" = prompt ] && [ "$(execpolicy npm update | jq -r .decision)" = prompt ] && [ "$(execpolicy pnpm rm x | jq -r .decision)" = prompt ] && [ "$(execpolicy bun install | jq -r .decision)" = prompt ]'
else
  echo "template: codex CLI not found; execpolicy check skipped" >&2
fi

DE="$TMP_ROOT/env-both"
cat > "$TMP_ROOT/env-answers.yml" <<'YML'
lint_cmd: 'eslint "a\b" é'
lint_pattern: '\.(ts|tsx)$'
test_cmd: 'pnpm test -- --grep "x\y"'
YML
render "$DE" v9.9.0 --data 'agents=[claude, codex]' --data-file "$TMP_ROOT/env-answers.yml"
check codex-env-escapes 'jq -S . "$DE/.harness/env.json" > "$TMP_ROOT/e1.json" && jq -S "[.env | to_entries[] | select(.key | IN(\"HARNESS_PROTECTED_BRANCHES\",\"HARNESS_LINT_CMD\",\"HARNESS_LINT_PATTERN\",\"HARNESS_TEST_CMD\"))] | from_entries" "$DE/.claude/settings.json" > "$TMP_ROOT/e2.json" && cmp -s "$TMP_ROOT/e1.json" "$TMP_ROOT/e2.json" && jq -e ".HARNESS_LINT_CMD | contains(\"é\")" "$DE/.harness/env.json" >/dev/null'
check codex-agents-md-eol '[ "$(tail -c 1 "$DC/AGENTS.md" | od -An -c | tr -d " ")" = "\\n" ] && ! tail -n 1 "$DC/AGENTS.md" | grep -q "[[:space:]]$" && [ -n "$(tail -n 1 "$DC/AGENTS.md")" ]'

DP="$TMP_ROOT/copilot-only"
render "$DP" v9.9.0 --data 'agents=[copilot]'
check copilot-rendered '[ -f "$DP/AGENTS.md" ]'
check copilot-no-jinja '! grep -rIlE "\{\{|\{%" "$DP" --exclude-dir=.git --exclude=ci.yml | grep -q .'
check copilot-workflow-schema '$CJS --builtin-schema vendor.github-workflows "$DP/.github/workflows/ci.yml" >/dev/null 2>&1'
check copilot-rules '[ -d "$DP/.claude/rules" ] && [ ! -e "$DP/.claude/settings.json" ] && [ ! -e "$DP/CLAUDE.md" ]'
check copilot-ci-budget '! grep -qF "CLAUDE.md" "$DP/.github/workflows/ci.yml" && grep -qF ".claude/rules" "$DP/.github/workflows/ci.yml"'

check copilot-settings 'jq -e ".enabledPlugins[\"harness@agentic-harness\"] == true and .extraKnownMarketplaces[\"agentic-harness\"].source.ref == \"v9.9.0\" and .extraKnownMarketplaces[\"agentic-harness\"].source.repo == \"joe-yama/agentic-harness\"" "$DP/.github/copilot/settings.json" >/dev/null'
check copilot-instructions 'grep -qF "Copilot CLI specifics" "$DP/.github/copilot-instructions.md"'
check copilot-instructions-dispatch 'grep -qF "gpt-5.6-luna" "$DP/.github/copilot-instructions.md" && grep -qF "without \`model\` the dispatch fails" "$DP/.github/copilot-instructions.md" && grep -qF "openspec-propose" "$DP/.github/copilot-instructions.md" && ! grep -qF "twice" "$DP/.github/copilot-instructions.md"'
check copilot-env '[ -f "$DP/.harness/env.json" ]'
DA="$TMP_ROOT/all-agents"
render "$DA" v9.9.0 --data 'agents=[claude, codex, copilot]'
common all "$DA"
check all-files '[ -f "$DA/CLAUDE.md" ] && [ -f "$DA/.codex/config.toml" ] && [ -f "$DA/.github/copilot/settings.json" ] && [ -f "$DA/.harness/env.json" ]'
check all-same-ref '[ "$(jq -r ".extraKnownMarketplaces[\"agentic-harness\"].source.ref" "$DA/.github/copilot/settings.json")" = "$(settings "$DA" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" ]'
check all-instructions-twice 'grep -qF "may show the rules twice" "$DA/.github/copilot-instructions.md"'
check codex-models 'agent_models_ok "$DC/docs/harness/models.md" Codex'
check copilot-models 'agent_models_ok "$DP/docs/harness/models.md" "Copilot CLI"'
check all-models 'models_ok "$DA/docs/harness/models.md" && agent_models_ok "$DA/docs/harness/models.md" Codex && agent_models_ok "$DA/docs/harness/models.md" "Copilot CLI"'
check codex-models-values '[ -n "$(codex_table "$DC/docs/harness/models.md")" ] && [ "$(codex_table "$DC/docs/harness/models.md")" = "$(codex_toml "$DC")" ]'
check codex-models-pinned 'grep -qF "gpt-6-luna" "$DC/docs/harness/models.md" && grep -qF "sets the model in each agent file" "$DC/docs/harness/models.md"'
check copilot-models-values 'grep -qF "claude-opus-5.5" "$DP/docs/harness/models.md" && grep -qF "claude-sonnet-5.5" "$DP/docs/harness/models.md" && grep -qF "reasoning_effort" "$DP/docs/harness/models.md" && grep -qF "without \`model\` the dispatch fails" "$DP/docs/harness/models.md" && grep -qF "If \`task\` answers that a model is not available, use \`gpt-5.6-luna\`, or another id from the list in that error." "$DP/docs/harness/models.md" && ! grep -qE "<F[0-9]|\{\{|\{%" "$DP/docs/harness/models.md"'
check models-intro 'head -3 "$DC/docs/harness/models.md" | grep -qF "AGENTS.md" && ! head -3 "$DC/docs/harness/models.md" | grep -qE "CLAUDE.md|\.claude/rules" && head -3 "$DP/docs/harness/models.md" | grep -qF ".claude/rules/" && ! head -3 "$DP/docs/harness/models.md" | grep -qF "CLAUDE.md" && head -3 "$DA/docs/harness/models.md" | grep -qF "CLAUDE.md"'
check codex-openspec-skills 'os_run "$DC" .agents/skills/openspec-propose/SKILL.md .agents/skills/openspec-archive-change/SKILL.md .agents/skills/openspec-update-change/SKILL.md .agents/skills/openspec-sync-specs/SKILL.md .agents/skills/.openspec-target'
check codex-openspec-extra '! os_run "$DC" .agents/skills/openspec-explore/SKILL.md && grep -q "openspec-explore" "$TMP_ROOT/os.log"'
check agents-openspec-step-name 'os_step "$DC/.github/workflows/ci.yml" >/dev/null && grep -qF "OpenSpec agent files (only propose, archive, update and sync stay)" "$DC/.github/workflows/ci.yml" && grep -qF "OpenSpec agent files (only the opsx commands propose, archive, update and sync stay)" "$D1/.github/workflows/ci.yml"'
# Every file the ci.yml context-budget step cats must exist in the render (glob entries must match something).
budget_files_ok() { # <rendered dir>
  local d=$1 line f n=0
  line=$(grep -E "^[[:space:]]*bytes=\\$\(cat " "$d/.github/workflows/ci.yml") || return 1
  line=${line#*cat }
  line=${line%% | wc*}
  for f in $line; do
    n=$((n + 1))
    # shellcheck disable=SC2086 # the glob entries are meant to expand
    [ -n "$(cd "$d" && ls -d $f 2>/dev/null)" ] || { echo "missing budget file: $f" >&2; return 1; }
  done
  [ "$n" -ge 1 ]
}
for pair in "claude:$D1" "codex:$DC" "copilot:$DP" "all:$DA"; do
  check "budget-files-${pair%%:*}" 'budget_files_ok "${pair#*:}"'
done
check budget-copilot-counted 'grep -qF ".github/copilot-instructions.md" "$DP/.github/workflows/ci.yml" && grep -qF ".github/copilot-instructions.md" "$DA/.github/workflows/ci.yml" && ! grep -qF "copilot-instructions" "$D1/.github/workflows/ci.yml"'

check none-rejected '! $COPIER copy --quiet --defaults --vcs-ref v9.9.0 --data project_name=S --data github_owner=o --data "agents=[]" "$SRC" "$TMP_ROOT/none" >/dev/null 2>&1'

check defaults-ref '[ "$(settings "$D1" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = v9.9.0 ]'
check defaults-no-lint '[ "$(settings "$D1" ".env.HARNESS_LINT_CMD // \"unset\"")" = unset ]'
check defaults-sandbox-excludes '[ "$(settings "$D1" ".sandbox.excludedCommands | sort | join(\",\")")" = "gh,gh *,git,git *" ]'
check defaults-teams-off '[ "$(settings "$D1" .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)" = 0 ]'
check defaults-branch '[ "$(settings "$D1" .env.HARNESS_PROTECTED_BRANCHES)" = main ]'
check defaults-no-mcp '[ ! -e "$D1/.mcp.json" ]'
check defaults-lang 'grep -q "Japanese" "$D1/AGENTS.md" && grep -q "Japanese" "$D1/openspec/config.yaml"'
# the "!" carve-out applies to the .env rules listed before it, so the order matters
check defaults-env-deny '[ "$(settings "$D1" "[.permissions.deny[] | select(test(\"env\"))] | join(\" \")")" = "Read(.env) Read(.env.*) Read(!.env.example) Edit(.env) Edit(.env.*) Edit(!.env.example)" ]'
check defaults-release-assets 'settings "$D1" ".sandbox.network.allowedDomains[]" | grep -qx release-assets.githubusercontent.com'
check defaults-gh-login 'settings "$D1" ".permissions.allow[]" | grep -qxF "Bash(gh api user --jq .login)" && ! settings "$D1" ".permissions.allow[]" | grep -qF "gh api user:"'

check ci-openspec-step 'os_step "$D1/.github/workflows/ci.yml" >/dev/null && ! grep -qE "^[[:space:]]*paths(-ignore)?:" "$D1/.github/workflows/ci.yml"'
check ci-openspec-empty 'os_run "$D1"'
OS4=.claude/commands/opsx
check ci-openspec-kept 'os_run "$D1" $OS4/propose.md $OS4/archive.md $OS4/update.md $OS4/sync.md'
check ci-openspec-skill '! os_run "$D1" .claude/skills/openspec-propose/SKILL.md && grep -q "openspec-propose" "$TMP_ROOT/os.log"'
check ci-openspec-apply '! os_run "$D1" $OS4/propose.md $OS4/archive.md $OS4/update.md $OS4/sync.md $OS4/apply.md && grep -q "opsx/apply.md" "$TMP_ROOT/os.log" && ! grep -q "opsx/propose.md" "$TMP_ROOT/os.log"'
check ci-openspec-all '! os_run "$D1" $OS4/apply.md $OS4/explore.md .claude/skills/openspec-explore/SKILL.md && grep -q "opsx/apply.md" "$TMP_ROOT/os.log" && grep -q "opsx/explore.md" "$TMP_ROOT/os.log" && grep -q "openspec-explore" "$TMP_ROOT/os.log"'

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
render "$D3" v9.9.0 --data "test_cmd=uv run pytest -q 'tests/' && uv run mypy <src> # ü" --data ui_review=true --data 'lint_cmd=uv run ruff check' --data 'lint_pattern=\.py$'
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

# A release candidate tag keeps its ref; a describe string after it does not.
RC="$TMP_ROOT/rc"
mkdir -p "$RC"
(cd "$repo" && git ls-files -co --exclude-standard | tar -c -T -) | tar -x -C "$RC"
git -C "$RC" init -q && git -C "$RC" add -A && git -C "$RC" commit -q -m snapshot
git -C "$RC" tag -a v9.9.0-rc.1 -m v9.9.0-rc.1
D6="$TMP_ROOT/rc-tag"
$COPIER copy --quiet --defaults --vcs-ref v9.9.0-rc.1 --data project_name=Sample --data github_owner=octo "$RC" "$D6" > "$TMP_ROOT/copier.log" 2>&1
check rc-ref '[ "$(settings "$D6" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = v9.9.0-rc.1 ]'
echo "# dev" >> "$RC/README.md"
git -C "$RC" add -A && git -C "$RC" commit -q -m dev
D7="$TMP_ROOT/rc-after"
$COPIER copy --quiet --defaults --vcs-ref HEAD --data project_name=Sample --data github_owner=octo "$RC" "$D7" > "$TMP_ROOT/copier.log" 2>&1
check rc-after-ref '[ "$(settings "$D7" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = main ]'

# A source repository without any tag makes _commit a bare SHA, which is not a branch or tag.
NOTAG="$TMP_ROOT/notag"
mkdir -p "$NOTAG"
(cd "$repo" && git ls-files -co --exclude-standard | tar -c -T -) | tar -x -C "$NOTAG"
git -C "$NOTAG" init -q && git -C "$NOTAG" add -A && git -C "$NOTAG" commit -q -m snapshot
D5="$TMP_ROOT/notag-out"
$COPIER copy --quiet --defaults --vcs-ref HEAD --data project_name=Sample --data github_owner=octo "$NOTAG" "$D5" > "$TMP_ROOT/copier.log" 2>&1
check notag-ref '[ "$(settings "$D5" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = main ]'

# copier update from v9.9.0 to v9.9.1 applies cleanly and moves the pin.
git -C "$D1" init -q && git -C "$D1" add -A && git -C "$D1" commit -q -m init
printf '\n<!-- updated -->\n' >> "$SRC/template/{% if use_claude %}CLAUDE.md{% endif %}.jinja"
git -C "$SRC" commit -q -am update && git -C "$SRC" tag -a v9.9.1 -m v9.9.1 && sleep 1 && git -C "$SRC" tag -a harness--v9.9.1 -m harness--v9.9.1
if ! (cd "$D1" && $COPIER update --quiet --defaults --vcs-ref v9.9.1 > "$TMP_ROOT/update.log" 2>&1); then
  tail -20 "$TMP_ROOT/update.log" >&2
fi
check update-ref '[ "$(settings "$D1" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" = v9.9.1 ]'
check update-applied 'grep -q "<!-- updated -->" "$D1/CLAUDE.md"'
check update-no-conflict '! grep -rlE "^(<<<<<<<|>>>>>>>) " "$D1" --exclude-dir=.git | grep -q .'

report template
