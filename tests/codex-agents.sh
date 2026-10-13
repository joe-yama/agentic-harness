#!/usr/bin/env bash
# The generated agent files equal a fresh render: plugins/harness/agents/reviewer-intermediate.md (reviewer.md's
# body under the intermediate review's frontmatter) and the Codex agents rendered from plugins/harness/agents/*.md.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=lib.sh
. "$repo/tests/lib.sh"
setup_git_env
out="$TMP_ROOT/agents"
mkdir -p "$out"
bash "$repo/scripts/gen-codex-agents.sh" "$out" "$out/reviewer-intermediate.md" || ng "generator failed"
src="$repo/plugins/harness/agents"
body() { awk 'n >= 2 { print } /^---$/ { n++ }' "$1"; }
if cmp -s "$out/reviewer-intermediate.md" "$src/reviewer-intermediate.md"; then ok; else ng "reviewer-intermediate.md is stale: run scripts/gen-codex-agents.sh"; fi
if [ -n "$(body "$src/reviewer.md")" ] && [ "$(body "$src/reviewer.md")" = "$(body "$src/reviewer-intermediate.md")" ]; then ok; else ng "reviewer-intermediate.md body differs from reviewer.md"; fi
if grep -qx "model: sonnet" "$src/reviewer-intermediate.md" && grep -qx "effort: medium" "$src/reviewer-intermediate.md"; then ok; else ng "reviewer-intermediate.md is not sonnet / medium"; fi
dir="$repo/template/{% if use_codex %}.codex{% endif %}/agents"
for n in harness-implementer harness-reviewer harness-reviewer-intermediate; do
  if cmp -s "$out/$n.toml" "$dir/$n.toml"; then ok; else ng "$n.toml is stale: run scripts/gen-codex-agents.sh"; fi
  if uvx --from copier@9.18.2 python -c 'import sys, tomllib; d = tomllib.load(open(sys.argv[1], "rb")); sys.exit(0 if all(d.get(k) for k in ("name", "description", "developer_instructions", "model", "model_reasoning_effort")) else 1)' "$dir/$n.toml"; then ok; else ng "$n.toml is not valid TOML with the required keys"; fi
done
report "codex agents"
