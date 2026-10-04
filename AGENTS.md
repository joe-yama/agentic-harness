# agentic-harness — maintainer instructions

This repository is a Claude Code plugin marketplace (`.claude-plugin/marketplace.json`, plugin in `plugins/harness/`) and a Copier template (`copier.yml`, `template/`). Product repositories adopt it; see `README.md`.

## Layout

| Path | Holds |
|---|---|
| `plugins/harness/scripts/` | hook scripts (bash + jq + git only) |
| `plugins/harness/hooks/hooks.json` | hook wiring, commands via `${CLAUDE_PLUGIN_ROOT}` |
| `plugins/harness/agents/`, `plugins/harness/skills/` | subagents and skills (English) |
| `scripts/` | maintainer tools (`gen-codex-agents.sh`); not shipped |
| `template/` | files rendered into product repositories |
| `tests/` | `all.sh` runs everything CI runs |
| `docs/specs/`, `docs/plans/` | design spec, implementation plans and their ledgers (history; 0.4.0 adds no new design or plan documents, the reasons are in the PR body, `CHANGELOG.md` and `README.md`) |

## Rules

- Before every commit, run the fast checks: `bash tests/lint.sh`, `bash tests/hooks/run.sh`, `bash tests/hooks/lifecycle.sh`, plus `bash tests/template/run.sh` when `template/` or `copier.yml` changed and `bash tests/codex-agents.sh` when `plugins/harness/agents/` changed. Run the full `bash tests/all.sh` (it includes `tests/hooks/mutate.sh`) before requesting review and before opening a PR; CI job `check` runs `all.sh`. Never pipe a test script into `tail` in a chained command — the pipe hides the exit status.
- After editing `plugins/harness/agents/*.md`, run `bash scripts/gen-codex-agents.sh`; `tests/codex-agents.sh` fails otherwise.
- Every hook rule sits between `# rule:<id>` and `# end:<id>` and needs a case in `tests/hooks/cases.tsv` or `tests/hooks/lifecycle.sh`. `tests/hooks/mutate.sh` fails when a rule can be deleted without a test failing.
- Hooks must work with macOS `/bin/bash` 3.2: `HOOK_BASH=/bin/bash bash tests/hooks/run.sh` (CI job `bash32` runs it and `lifecycle.sh` on macOS).
- Change behavior test-first: add the failing case, watch it fail, then change the script.
- English is canonical. Keep `README.ja.md` in sync with `README.md` in the same commit.
- A release bumps `plugins/harness/.claude-plugin/plugin.json` `version` and `CHANGELOG.md` together; the marketplace entry carries no version. Tag `vX.Y.Z` and run `claude plugin tag plugins/harness` for `harness--vX.Y.Z` on the same commit.
- Pinned versions (Actions SHAs, Copier, check-jsonschema, shellcheck-py, Claude Code, Playwright MCP, SchemaStore commit) live in the files that use them (`.github/workflows/`, `template/`, `tests/`, `plugins/harness/skills/adopt/`); change them together. The v0.1.0 plan's Global Constraints list the original choices and are history.
- Commit messages: English, type prefix (`feat:` `fix:` `test:` `docs:` `chore:` `ci:`).
