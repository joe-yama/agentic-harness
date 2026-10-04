# Changelog

All notable changes to this project are documented here. The plugin version in
`plugins/harness/.claude-plugin/plugin.json` and the git tags `vX.Y.Z` / `harness--vX.Y.Z` follow this file.

## [Unreleased]

### Added

- Codex CLI and GitHub Copilot CLI support. Copier question `agents` (`claude`, `codex`, `copilot`; default `claude`) renders each selected agent's files: `.codex/config.toml`, `.codex/rules/harness.rules`, `.codex/agents/harness-*.toml` (generated from the plugin agents by `scripts/gen-codex-agents.sh`; `tests/codex-agents.sh` checks them), `.github/copilot/settings.json`, `.github/copilot-instructions.md`, and `.harness/env.json` for hook settings. `.claude/` and `CLAUDE.md` render only when `claude` is selected (`.claude/rules/` also for `copilot`).
- Hooks accept Codex `apply_patch` and Copilot CLI payloads: `guard` checks every path a patch writes (its body is not a command), `lint-on-edit` lints every patched file.
- New guard rule `harness-env` refuses access to `.harness/env.json`. The file is edited only by the PO and never carries the guard relaxations. The rule reads command text, so a glob in the directory part (`.h*/env.json`) is not seen.
- With `COPILOT_CLI=1` (exactly `1`), `guard` prints its denial as JSON on stdout and exits 0, because Copilot CLI does not pass the stderr of an exit-2 denial to the model. Only the message form changes; exit 2 stays the form otherwise. Claude Code and Codex also honour the JSON form, so an inherited `COPILOT_CLI=1` still blocks there; it remains a residual risk if either agent stops reading it.
- `docs/harness/models.md` has a section per agent; `harness:execute`, `harness:workflow` and `harness:design` name each agent's mechanics in per-agent tables; `harness:adopt` installs, sets up OpenSpec for and verifies each selected agent.
- The question `agents` is also asked by `copier update` (default `[claude]`); `.gitignore` and `ci.yml` change when another agent is added.

### Changed

- `hooks.json` goes back from the exec form (`"command": "bash", "args": [...]`, introduced in 0.2.0) to the string form `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"`. Neither Codex nor Copilot CLI runs the exec form: Codex fails open (the guard is off) and Copilot denies every matched tool. The quotes keep a path with spaces in one argument. `tests/manifest.sh` checks the string form.
- `lint-on-edit` reports failures as JSON instead of exit 2: Claude Code and Codex get `decision: block` with `additionalContext`, Copilot CLI gets top-level `additionalContext` only (it ignores the nested form, and a block would hide the tool output and mark an applied edit as failed). Claude Code behavior is the same: the agent must fix the file.
- Template CI job `check`: with Codex or Copilot selected, the OpenSpec step also rejects `.agents/skills/openspec-*` other than the four the harness uses; the context-budget step counts the selected agents' instruction files.
- Template `AGENTS.md` has a "Codex specifics" section when `codex` is selected: `.codex/rules` cover what ask-gate would ask (pushes, branch deletions, merges, releases, lockfile changes) because Codex hooks cannot ask; guard still blocks destructive commands.
- `tests/manifest.sh` applies the agent-neutrality check to `harness:adopt` too and adds `/opsx:` to its token list.
- `tests/hooks/run.sh` requires exit 2 for a guard block unless the case sets exactly `COPILOT_CLI=1`.
- README (English and Japanese): the "Agents" section has the support matrix and known gaps. Among them: Codex hooks run only after you trust them; Codex hooks cannot ask, and `.codex/rules` match command prefixes only; Codex ignores `sandbox_mode` in agent files, so the reviewer runs writable and its instructions forbid edits; Copilot CLI has no repository permissions or sandbox; Copilot PostToolUse cannot block; Copilot lists plugin skills without the `harness:` prefix and may show AGENTS rules twice; `test-on-stop` keeps an agent working while tests fail even when it paused to ask the PO.
- The plugin manifest gets no `agents` key: Codex and Copilot CLI read the same `plugins/harness/` tree, so there is one manifest and one version line.

## [0.4.0-rc.1] - 2026-10-04

Release candidate for 0.4.0 (the final 0.4.0 follows after the candidate is tried; the README install pins stay at v0.3.0 until then). **Not backward compatible**: the plugin no longer depends on Superpowers, and the design document and the plan document are replaced by the OpenSpec change itself. The steps to move an adopted repository are in `harness:adopt` ("From 0.3.x to 0.4.0").

### Changed

- **BREAKING** plugin: `plugin.json` has no `dependencies` and no `superpowers` keyword, and `marketplace.json` has no `allowCrossMarketplaceDependenciesOn`. Installing the plugin no longer installs Superpowers. `tests/manifest.sh` asserts both are absent and accepts `X.Y.Z-rc.N` versions.
- **BREAKING** `harness:workflow`: the lifecycle is idea → `harness:design` → `/opsx:propose` plus one Issue → `harness:execute` in a new session → final review and PR → acceptance → `/opsx:archive`. `tasks.md` is the plan, so there is no separate planning step and no reference to Superpowers skills. One new session per stage, handing over only through committed files and the ledger. The ledger is `.harness/<change>/progress.md` (gitignored).
- **BREAKING** `harness:implementer` and `harness:reviewer`: they receive the change path, task numbers and BASE/range instead of a task brief, global constraints or a diff file. The implementer is now `model: sonnet`, `effort: medium`, and gains a short debugging rule (reproduce and find the root cause first, one hypothesis at a time, stop after three failed fixes). The reviewer reads the change's delta specs, `design.md` and `tasks.md` as ground truth and reports a scenario map: every touched `#### Scenario:` maps to a test (`file:line`) or a verification task, and a scenario with neither is an Important finding.
- **BREAKING** template: `AGENTS.md` and `CLAUDE.md` name `harness:design` and `harness:execute` instead of Superpowers skills, and refer to `docs/harness/models.md` instead of naming a model; `.claude/settings.json` sets `superpowers@claude-plugins-official` to `false` (set it to `true` to use Superpowers) and keeps a `vX.Y.Z-rc.N` ref, falling back to `main` for `git describe` output after an rc; `docs/status.md` drops the Superpowers row; `.gitignore` adds `.harness/`; `openspec/config.yaml` gets `rules.design` and `rules.tasks`, which `/opsx:propose` follows so that `tasks.md` carries files, tests first, review unit and risk per task.
- `harness:adopt`: the `gh skill install` step is gone. After `openspec init` it deletes `.claude/skills/openspec-*`, `opsx/apply.md` and `opsx/explore.md`, and optionally sets OpenSpec's global profile (`openspec config set profile custom`, `workflows`, `delivery commands`) so they are never generated. The verification no longer looks for Superpowers or OpenSpec skills; it looks for `harness:design` and `harness:execute`. "Updating" has a 0.3.x to 0.4.0 migration.
- README (English and Japanese): the Superpowers dependency is gone; the components list matches 0.4.0; the Superpowers default and how to turn it on, the OpenSpec command set and the migration are described. Credits keep obra/superpowers as the source of ideas.

### Added

- `harness:design`: the design session. It reads the context, picks the route, asks the PO one question at a time (or writes a questions file when headless), writes the whole change with `/opsx:propose`, creates the one Issue and ends.
- `harness:execute`: carries a change from `tasks.md` to an open PR: ledger, one implementer per task or batch, review units from `tasks.md`, fix rounds, rebuild conditions, waiting and context rules, a final review of the branch, one push and the PR.
- Template `docs/harness/models.md`: the role-to-model/effort table (no planning row, no Haiku) and how model and effort are set.
- Template CI job `check`: a step, run on every change including documentation-only ones, that fails when `.claude/skills/openspec-*` or an `opsx` command other than `propose`, `archive`, `update` and `sync` exists (`openspec update` restores them under its default profile).
- Tests: `tests/template/run.sh` checks the Superpowers entry is `false`, the rc ref, the OpenSpec rules, the models document and the CI step.

### Removed

- **BREAKING** `harness:review-loop`: its content (review units, materials, fix rounds, rebuild conditions, Minor handling) moved into `harness:execute`.

## [0.3.0] - 2026-09-29

- guard: two opt-in exceptions, off unless set (behavior is unchanged when unset). `HARNESS_ALLOW_LEASE_PUSH=1` lets `git push --force-with-lease=refs/heads/<branch>:<sha> [--force-if-includes] <remote> <src>:refs/heads/<branch>...` through when refs are written in full, leases and destinations match one to one, no branch is in `HARNESS_PROTECTED_BRANCHES` (space-separated, as in ask-gate), and the command neither mentions a `GIT_CONFIG*` variable nor runs `git config`; every other force push stays blocked (`force-push`). `HARNESS_RM_RF_ALLOW=<prefix>[:<prefix>...]` lets a recursive forced `rm` through when every operand is a plain absolute path that, with symlinks resolved (`cd -P`), is at or under one of the (resolved) prefixes of at least two segments; relative paths, globs, `..`, expansions, words after the first operand that look like options (BSD `rm`), operands over 1024 bytes, commands that run `ln`, and `rm` run by `xargs`, `find -exec`, `sudo` or `sh -c` stay blocked (`rm-rf`). See README "Opt-in guard exceptions".
- Tests: the env column of `tests/hooks/cases.tsv` takes several `NAME=value` assignments separated by `;`, and `@T@` in a case is a fixture tree with symlinks; `tests/hooks/timing.sh` also runs with both opt-ins set. `tests/hooks/mutate.sh` runs `MUTATE_JOBS` mutants at a time (default: the CPU count), without wall-clock assertions (`MUTATE_NO_TIMING=1`), and reports a mutant that does not finish in `MUTATE_TIMEOUT` seconds (default 300) as TIMED OUT, which fails the run.

## [0.2.1] - 2026-09-25

- Template: `.claude/settings.json` is rendered exactly as `claude plugin install --scope project` writes it — JSON.stringify with 2-space indent, Claude Code's key order, no HTML or ASCII escaping in string values (`&&`, `'`, `<`, `ü` stay literal) — and enables the `superpowers@claude-plugins-official` dependency. The install in `harness:adopt` step 5 now leaves the file byte-identical (checked with Claude Code 2.1.282 for `ui_review` true and false); before, it reformatted the whole file and left an uncommitted diff. `tests/template/run.sh` checks the layout, and `harness:adopt` step 5 checks `git diff --exit-code .claude/settings.json`. The Quick start commits the render before the install, so that check compares against it. `harness:adopt` "Updating" points to these CHANGELOG notes before resolving conflicts.
- Updating from 0.2.0: if `.claude/settings.json` still has the 0.2.0 layout, `copier update` applies cleanly. If you committed the file the install rewrote, Copier reads the reformatting as your change and writes conflict markers into `.claude/settings.json` (two hunks for an otherwise unchanged file): keep the "after updating" side and re-add your own entries in the new layout. Checked with Copier 9.18.2 from `v0.2.0` renders.

## [0.2.0] - 2026-09-25

- Tests: hook cases assert which rule fired (`block:<id>` / `ask:<id>`), cover a missing `jq`, and the mutation check covers `lib/parse.sh`.
- guard's missing-`jq` message carries the id `no-jq`, like ask-gate's.
- guard blocks and ask-gate asks (`bad-input`) when the hook input is not a JSON object, instead of letting the command through.
- A command over 64 KiB is blocked by guard and asked by ask-gate (`too-large`) before parsing. Below the cap, guard no longer forks per word (`git -c` keys, `.env`-like words; up to 16 s before) and ask-gate asks when a command needs the branch of more than 16 directories; `tests/hooks/timing.sh` checks that every hook answers within 5 s on commands up to the cap.
- Abbreviated long options, down to one letter after `--`, count as the full option (`git reset --h`, `git clean --f`, `rm --r --f`, `git commit --no-verif`, `git worktree remove --f`).
- guard blocks hook bypass by configuration: `git -c core.hooksPath=…` and `HUSKY=0 git …` (`no-verify`), and shell aliases `git -c alias.<x>=!…` (`git-alias`).
- `pipe-shell` catches more spellings: `bash <(curl …)`, `source <(curl …)`, `| /bin/bash`, `| sudo -E bash`, `| tee x | sh`, and backticks or `$(curl …)` given to `sh -c` or `eval`.
- `secrets-dir` and `env-file` match case-insensitively (also for file tools); credential directories after `~user/` and `/root/` or at the start of a word (`cd ~ && cat .ssh/id_rsa`); `.env` after `:` (`git show HEAD:.env`) and as a glob (`.env*`, `.env.?`). A word starting with `.aws/` inside a project is refused too (accepted false positive).
- When `jq` / `yq` / `gojq` is the command word, its first non-option argument is a filter, not a file: `jq '.env' .claude/settings.json` passes; `jq . .env`, `grep jq .env` and `jq -n 1;cat<.env` are still blocked.
- `-c` after `grep`, `egrep`, `fgrep`, `rg`, `wc`, `head`, `tail`, `cut`, `uniq`, `tr` or `git grep` is a flag, so its quoted argument is not read as a command (`grep -c "rm -rf" f` passes).
- More quoted strings are checked as commands: after `-c` with options in between (`bash -c -- '…'`, `bash -c -x '…'`), a here-string to a shell (`bash <<< '…'`), and the quoted arguments of `watch` and `ssh <host>`. `node -e`, `perl -e` and code inside `python -c` stay out of reach.
- ask-gate looks up the current branch once per directory, so a long command of bare `git push` segments no longer runs past the hook timeout (64 KiB: 29 s → 0.6 s).
- guard blocks and ask-gate asks (`bad-parser`) when `lib/parse.sh` is missing, fails to source or does not define the parser, instead of letting every command through.
- An invalid `HARNESS_LINT_PATTERN` or `HARNESS_DOC_PATTERN` fails loudly: lint-on-edit exits 2 and test-on-stop blocks with `invalid HARNESS_…_PATTERN`, instead of silently skipping lint or tests.
- `hooks.json` uses the exec form (`"command": "bash"`, `"args": ["${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"]`), so the plugin path is passed as one argument without shell quoting.
- Template settings: the `.env` deny list is `.env`, `.env.*` and the carve-out `!.env.example` (for `Read` and `Edit`), so every `.env.*` name is denied; the sandbox allows `release-assets.githubusercontent.com` (GitHub release downloads redirect there); the allow rule for the account check is exactly `gh api user --jq .login`.
- Skills: `workflow` and `review-loop` record rulings in the change's committed `openspec/changes/<name>/` (then `docs/changes.md`), not in the gitignored `.superpowers/sdd/`; the `mutation-check` overlay skips deleted files (and deletes them in the copy) instead of failing in `tar`.
- `copier.yml` drops `_templates_suffix: .jinja`, Copier's default; renders are unchanged.
- README "Known gaps" matches the current hooks: credential and `.env` names are refused anywhere in the command text (commit messages, grep patterns), `$(…)` inside double quotes and `jq -f .env` / `git show HEAD:.ssh/…` are not caught, abbreviations count, the 64 KiB cap.
- CI job `bash32` runs the hook cases and lifecycle tests with macOS `/bin/bash` 3.2 on `macos-latest` (not a required check).

## [0.1.0] - 2026-09-25

- First release: guard / ask-gate / lint-on-edit / test-on-stop hooks, implementer and reviewer subagents, workflow / review-loop / mutation-check / adopt skills, and the Copier template.
