# agentic-harness

A product-development harness for [Claude Code](https://code.claude.com/docs) in which a human **PO** steers and the agent executes: brainstorm → spec (OpenSpec) → plan → test-first implementation by subagents → adversarial review in a separate context → PR → PO acceptance. It is the generalized form of a harness built and measured on a real project, checked against current Claude Code, GitHub and supply-chain guidance.

> 日本語版は [README.ja.md](README.ja.md)。この英語版が正本です。

## What you get

One repository, two channels, one version line:

| Channel | Carries | Updated by |
|---|---|---|
| **Plugin** `harness@agentic-harness` (`plugins/harness/`) | hooks: `guard` (hard blocks), `ask-gate` (routes to the PO), `lint-on-edit`, `test-on-stop`; subagents `harness:implementer`, `harness:reviewer`; skills `harness:workflow`, `harness:review-loop`, `harness:mutation-check`, `harness:adopt` | `claude plugin update` |
| **Copier template** (`copier.yml`, `template/`) | what a plugin cannot carry: `AGENTS.md`, `CLAUDE.md` (`@AGENTS.md` + Claude specifics), `.claude/rules/`, `.claude/settings.json` (permissions, sandbox, `HARNESS_*` env, plugin pin), CI job `check`, Dependabot, PR template, OpenSpec config, status / ledger / lessons docs, branch ruleset | `copier update` (a reviewable PR) |

The plugin depends on [Superpowers](https://github.com/obra/superpowers) from the official marketplace. OpenSpec comes from its own CLI.

### What the hooks do

| Hook | Behavior |
|---|---|
| `guard` (PreToolUse on Bash, Monitor and file tools) | blocks recursive forced `rm`, force pushes (including `+refspec` and `-uf`), `git reset --hard`/`--merge`, `git clean -f`, whole-tree checkout/restore, `git branch -D`, `--no-verify` / `commit -n` / `--no-gpg-sign`, `.env` files (except `.env.example`), credential directories, `curl … \| sh` |
| `ask-gate` (PreToolUse on Bash and Monitor) | asks the PO for pushes to protected branches (and refspec-less pushes from them), remote branch deletion, `--all` / `--mirror` / `--prune`, `git worktree remove --force`, and lockfile-changing installs (pnpm, npm, yarn, bun, uv, pip, cargo) |
| `lint-on-edit` (PostToolUse) | runs `HARNESS_LINT_CMD <file>` on each edited file and makes Claude fix failures immediately |
| `test-on-stop` (Stop) | runs `HARNESS_TEST_CMD` before the turn ends when non-doc files changed, and keeps Claude working while it fails |

## Quick start

Prerequisites: Claude Code ≥ 2.1.277, `jq`, `git`, [`uv`](https://docs.astral.sh/uv/), `gh`, and the OpenSpec CLI.

```sh
# in the product repository (its default branch must already exist on GitHub)
git switch -c fix/adopt-agentic-harness
uvx copier@9.18.2 copy --vcs-ref v0.1.0 gh:joe-yama/agentic-harness .
claude            # interactive: accept the trust dialog; this registers the marketplace pinned to v0.1.0
claude plugin install harness@agentic-harness --scope project
```

Do not run `claude plugin marketplace add joe-yama/agentic-harness` yourself: that registers the unpinned default branch under the same name. Then, in a new session, ask Claude to run **`harness:adopt`** from step 4 on: it sets up OpenSpec with pinned skills, applies the branch ruleset (after you confirm) and verifies that the guard is live. The skill is the full procedure, including creating the repository.

## Configuration

The template writes these into `.claude/settings.json` → `env`. The hooks do nothing for an unset command, so a repository can adopt the harness before choosing a stack.

| Variable | Default | Used by |
|---|---|---|
| `HARNESS_LINT_CMD` | unset (no lint) | `lint-on-edit`; the edited file is passed as the last argument, never spliced into the command |
| `HARNESS_LINT_PATTERN` | every non-doc file | `lint-on-edit`; extended regex on the repo-relative path |
| `HARNESS_TEST_CMD` | unset (no test) | `test-on-stop` |
| `HARNESS_DOC_PATTERN` | `\.(md\|txt)$\|^docs/\|^openspec/\|^\.claude/` | paths that never trigger lint or tests |
| `HARNESS_PROTECTED_BRANCHES` | `main` | `ask-gate`; space-separated |

## Updating

```sh
git switch -c fix/harness-v0.2.0
uvx copier@9.18.2 update --vcs-ref v0.2.0      # also moves the plugin pin in .claude/settings.json
grep -rnE '^(<<<<<<<|>>>>>>>) ' . --exclude-dir=.git   # conflicts are written inline, not as .rej files
```

Resolve the conflict markers, restart Claude Code so it reads the new pin, run `claude plugin update harness@agentic-harness`, then open a PR and let CI and review check it. Under auto mode, Claude cannot write `.claude/settings.json`; it prepares the merged file and you place it.

## Security notes

- **Plugins run with your user privileges.** Read `plugins/harness/scripts/` at the tag you install. Hooks need only `bash`, `jq` and `git`.
- `HARNESS_*_CMD` values come from the repository's own committed settings and run with `bash -c`. Treat a change to them like any code change.
- Do not run `claude -p` over repositories you do not trust without `--bare`: committed hooks run in headless mode.
- The hooks match command text; they are a tripwire, not a sandbox. The template turns on the Claude Code sandbox (credential directories unreadable, network limited to GitHub and package registries) as the OS-level boundary. Known gaps and false positives:
  - a quoted string is checked as a command only after `-c` (`sh -c '…'`, `bash -lc "…"`, also with options in between: `bash -c -- '…'`) or `eval`, as a here-string to a shell (`bash <<< '…'`), and as an argument of `watch` or `ssh <host>`; `-c` of `grep`, `wc`, `head` and the like is a flag. Other quoted strings (commit messages, grep patterns, Issue bodies) are data. A quoted `.env` is still treated as a file name, except as the filter of `jq` / `yq` / `gojq` (`jq '.env' …` passes), and heredoc bodies are checked line by line, so pass long bodies with `--body-file`;
  - commands assembled from variables or run through another interpreter (`python -c`, `node -e`) are not seen;
  - `uv run` can update `uv.lock` without asking.
- Third-party components: Superpowers (MIT, pinned by the official marketplace), OpenSpec (MIT, pinned tag via `gh skill`), Playwright MCP (Apache-2.0, exact version, only with `ui_review`). All GitHub Actions are pinned by commit SHA and updated by Dependabot.

## What stays in your user settings

Machine- and person-specific policy does not belong in a shared template. Keep it in `~/.claude/settings.json` and user-level hooks, for example: a gate that asks before `git push` / `gh` writes when the origin or the `gh` login is not your personal account, commit-signing setup, and model defaults.

## Versioning

Tags `vX.Y.Z` (template) and `harness--vX.Y.Z` (plugin, from `claude plugin tag`) point at the same commit. The plugin version lives only in `plugins/harness/.claude-plugin/plugin.json`; see [CHANGELOG.md](CHANGELOG.md).

## Development

```sh
bash tests/all.sh   # shellcheck, 192 hook cases, lifecycle tests, rule mutation test, manifests + claude plugin validate, template renders
claude --plugin-dir plugins/harness   # load the plugin under development
```

Requires `jq`, `git`, `uv` and the `claude` CLI. Every hook rule sits between `# rule:<id>` and `# end:<id>`; `tests/hooks/mutate.sh` deletes each rule in turn and fails if no test notices.

## Credits

- [obra/superpowers](https://github.com/obra/superpowers) — brainstorming, planning, subagent-driven development, TDD.
- [Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec) — spec-driven changes with delta specs and archives.
- The reviewer's over-engineering pass follows the idea of [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail).
- Anthropic, [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) and [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps).

## License

[MIT](LICENSE)
