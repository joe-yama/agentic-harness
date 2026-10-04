#!/usr/bin/env bash
# The committed Codex agent files equal a fresh render from plugins/harness/agents/*.md.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=lib.sh
. "$repo/tests/lib.sh"
setup_git_env
out="$TMP_ROOT/agents"
mkdir -p "$out"
bash "$repo/scripts/gen-codex-agents.sh" "$out" || ng "generator failed"
dir="$repo/template/{% if use_codex %}.codex{% endif %}/agents"
for n in harness-implementer harness-reviewer harness-reviewer-intermediate; do
  if cmp -s "$out/$n.toml" "$dir/$n.toml"; then ok; else ng "$n.toml is stale: run scripts/gen-codex-agents.sh"; fi
  if uvx --from copier@9.18.2 python -c 'import sys, tomllib; d = tomllib.load(open(sys.argv[1], "rb")); sys.exit(0 if all(d.get(k) for k in ("name", "description", "developer_instructions", "model", "model_reasoning_effort")) else 1)' "$dir/$n.toml"; then ok; else ng "$n.toml is not valid TOML with the required keys"; fi
done
report "codex agents"
