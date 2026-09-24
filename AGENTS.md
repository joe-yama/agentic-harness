# agentic-harness — maintainer instructions

This repository is a Claude Code plugin marketplace (`.claude-plugin/marketplace.json`, plugin in `plugins/harness/`) and a Copier template (`copier.yml`, `template/`). Product repositories adopt it; see `README.md`.

## Layout

| Path | Holds |
|---|---|
| `plugins/harness/scripts/` | hook scripts (bash + jq + git only) |
| `plugins/harness/hooks/hooks.json` | hook wiring, commands via `${CLAUDE_PLUGIN_ROOT}` |
| `plugins/harness/agents/`, `plugins/harness/skills/` | subagents and skills (English) |
| `template/` | files rendered into product repositories |
| `tests/` | `all.sh` runs everything CI runs |
| `docs/specs/`, `docs/plans/` | design spec, implementation plans and their ledgers |

## Rules

- Run `bash tests/all.sh` before every commit; CI job `check` runs the same script. Never pipe it into `tail` in a chained command — the pipe hides the exit status.
- Every hook rule sits between `# rule:<id>` and `# end:<id>` and needs a case in `tests/hooks/cases.tsv` or `tests/hooks/lifecycle.sh`. `tests/hooks/mutate.sh` fails when a rule can be deleted without a test failing.
- Hooks must work with macOS `/bin/bash` 3.2: `HOOK_BASH=/bin/bash bash tests/hooks/run.sh`.
- Change behavior test-first: add the failing case, watch it fail, then change the script.
- English is canonical. Keep `README.ja.md` in sync with `README.md` in the same commit.
- A release bumps `plugins/harness/.claude-plugin/plugin.json` `version` and `CHANGELOG.md` together; the marketplace entry carries no version. Tag `vX.Y.Z` and run `claude plugin tag plugins/harness` for `harness--vX.Y.Z` on the same commit.
- Pinned versions (Actions SHAs, Copier, check-jsonschema, shellcheck-py, Claude Code, Playwright MCP, SchemaStore commit) are listed in the current plan's Global Constraints; change them together with CI and the template.
- Commit messages: English, type prefix (`feat:` `fix:` `test:` `docs:` `chore:` `ci:`).
