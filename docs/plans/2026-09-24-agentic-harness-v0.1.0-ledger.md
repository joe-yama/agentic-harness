# v0.1.0 ledger

Rulings made while implementing `docs/plans/2026-09-24-agentic-harness-v0.1.0.md`, and results of manual verification.

### 2026-09-25 Plugin hooks receive the product's settings env
- Ruling: hooks read `HARNESS_*` from the environment; no jq fallback on settings.json.
- Reason: spike with `claude -p --plugin-dir` (Claude Code 2.1.281) — SessionStart and PreToolUse hooks of a plugin both saw `HARNESS_TEST_CMD` and `HARNESS_PROTECTED_BRANCHES` set in the project's `.claude/settings.json` `env`.
- Cost if wrong: hooks silently do nothing for lint/test and use the default protected branch; detectable in the adopt verification step.

### 2026-09-25 Keep the executor workspace out of git
- Ruling: `.gitignore` also ignores `/.superpowers/`.
- Reason: the executing-plans workspace (progress ledger, briefs, review packages) is scratch.
- Cost if wrong: none.

### 2026-09-25 guard env-file rule splits words instead of grep -o
- Ruling: the Bash `.env` rule splits the command on whitespace, quotes, redirections and separators and matches each word's basename against `^\.env(\.[A-Za-z0-9_-]+)*$` (except `.env.example`).
- Reason: the plan's `grep -o` regex consumed the trailing boundary character, so the second file in `cat .env.example .env` was never matched (case g-ev-05 failed).
- Cost if wrong: a quoted string that merely mentions `.env` is blocked (false positive on the safe side).

### 2026-09-25 ask-gate asks for every `uv pip` subcommand and for removals/updates
- Ruling: `lockfile-install` asks for `uv pip <anything>` and also for remove/update subcommands of pnpm, npm, yarn, bun and cargo, beyond the spec's list of installs.
- Reason: they change the lockfile or the environment just like installs; the spec's intent is "installs that can change a lockfile".
- Cost if wrong: an extra confirmation prompt for `uv pip list` / `uv pip show`.

### 2026-09-25 Mutation test found two unguarded rules
- Ruling: `lint-outside-repo` guarded unreachable code (a file outside any repository already exits at `git rev-parse`), so the dead `case` was removed and the rule markers moved to the `rev-parse` line; `stop-unset` / `lint-unset` were only tested with an empty value, so truly unset (`env -u`) cases were added.
- Reason: `tests/hooks/mutate.sh` reported `SURVIVED` for both. Checker self-check: deleting the `g-ps-01..05` rows in a copy makes it report `SURVIVED: guard.sh rule:pipe-shell`.
- Cost if wrong: none; the tests only became stricter.

### 2026-09-25 Hooks are tested under macOS bash 3.2 too
- Ruling: `run.sh` and `lifecycle.sh` accept `HOOK_BASH`; all hook cases pass with `HOOK_BASH=/bin/bash` (GNU bash 3.2.57).
- Reason: hooks are started as `bash …`, and on macOS that can resolve to `/bin/bash` 3.2 depending on PATH.
- Cost if wrong: none.

### 2026-09-25 Agent teams are disabled with "0"
- Ruling: the template sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` to `"0"`.
- Reason: the SchemaStore Claude Code settings schema (pinned commit) only accepts `"0"` or `"1"`; the empty string portfolio used fails validation.
- Cost if wrong: none expected; `"0"` is the documented off value.

### 2026-09-25 The marketplace ref accepts exact release tags only
- Ruling: the rendered `ref` is `_commit` only when it starts with `v` and contains no `-`; otherwise `main`.
- Reason: rendering from a source repository without tags makes Copier's `_commit` a bare short SHA, and the plan's check (reject `-g`) let it through; the settings schema defines `ref` as a branch or tag. Tests `notag-ref` and `notag-status` went RED, then GREEN.
- Cost if wrong: a pre-release tag such as `v1.0.0-rc1` pins to `main` instead.

### 2026-09-25 Local end-to-end smoke (Claude Code 2.1.281)
- Setup: template rendered from HEAD with `lint_cmd=sh -c 'echo "$0" >> .smoke-lint'` and `test_cmd=echo ran > .smoke-test`; `claude -p ... --plugin-dir plugins/harness --permission-mode acceptEdits`.
- `ls ~/.config/gh` → `BLOCKED by harness guard (secrets-dir): credential directories are off limits` ("This hook comes from the harness@inline plugin").
- `git commit -n --allow-empty -m probe` → `BLOCKED by harness guard (no-verify): git commit -n skips hooks`; no commit created; the agent did not rephrase the command (template CLAUDE.md rule).
- Writing `src/hello.ts` → `.smoke-lint` received the absolute path (lint hook ran with the settings `env` command); at the end of the turn `.smoke-test` contained `ran` (Stop hook ran `HARNESS_TEST_CMD`).
- The plugin loaded with its Superpowers dependency satisfied by the user-scope install (no dependency error).
- The rendered rules loaded: the agent flagged the new file as application code before design approval (template `scope.md`).
- Probes were chosen so the controlling session's own portfolio hooks were not tripped or worked around.
- Finding: `claude -p` in a folder whose trust dialog was never accepted ignores the project's `permissions.allow` ("Ignoring 25 permissions.allow entries … this workspace has not been trusted"). Ruling: `harness:adopt` step 7 now says to verify in an interactive session and accept the trust dialog. Cost if wrong: none.

### 2026-09-25 Final review round 1 (context-free Opus reviewer): Needs fixes → fix pass
All Critical and Important findings were fixed in one pass, each with a test that failed first.
- C1 release tags pinned the plugin to `main`: `claude plugin tag` adds an annotated `harness--vX.Y.Z` on the release commit and Copier's `_commit` reports it. The template now strips the `harness--` prefix. Tests `defaults-ref` / `update-ref` now use annotated `v9.9.0` + `harness--v9.9.0` (RED → GREEN). `docs/status.md` no longer renders the version (adopt fills it), removing the duplicated expression.
- I1 backslash-newline continuations bypassed every rule; I2 `/bin/rm`, `sh -c '…'`, quoted words, `\rm`, `git -P` / `--git-dir x` / `-C "my dir"`, `git branch -d -f`, `git push origin 'main'` / `"HEAD:main"` / `@`: new `scripts/lib/parse.sh` normalizes commands (joins continuations, removes quotes while keeping quoted arguments as one token, checks quoted strings as commands, accepts a path prefix, skips git global options); cases `g-bs-*`, `g-wr-*`, `a-q-*`, `a-bs-*` (RED → GREEN). This also removed the `git commit -m "… -n …"` false positive (`g-wr-16`).
- I3 the Monitor tool bypassed both PreToolUse hooks: matcher `Bash|Monitor`, both scripts accept `Monitor`; cases `g-mo-*`, `a-mo-*`, manifest `h-monitor` (RED → GREEN).
- I4 `excludedCommands: ["git","gh"]` did not match `git commit`: now `git`, `git *`, `gh`, `gh *` (sandboxing docs: "Add `docker *` to excludedCommands"); test `defaults-sandbox-excludes` (RED → GREEN).
- I5 unpinned `claude plugin marketplace add` in quick start / adopt: removed; the pinned `extraKnownMarketplaces` entry is registered by accepting the trust dialog.
- I6 Copier writes conflicts inline, not as `.rej`: adopt and README now grep for conflict markers; test `update-no-conflict` replaces the never-failing `update-no-rej`.
- I7 adopt could not start from an empty repository: new step 2 creates the repository and default branch; the ruleset is applied after rendering.
- Spec updated for §5.1 (matcher, parsing), D10 (`excludedCommands` syntax), §5.4 adopt.

### 2026-09-25 Spec deviations accepted by ruling
- Ruling: `git clean -d` / `-x` without `-f` are not blocked (spec §5.1 listed `-f/-d/-x`).
- Reason: git refuses to clean without `-f` under the default `clean.requireForce`, so they cannot delete anything.
- Cost if wrong: a repository with `clean.requireForce=false` can lose untracked files via `git clean -d`.

- Ruling: `lint-on-edit` skips files outside any git repository instead of falling back to `CLAUDE_PROJECT_DIR` (spec §5.1).
- Reason: a file outside every repository is not project code (scratch files, other checkouts); linting it from the project root produced errors in the controlling session during this very build.
- Cost if wrong: a project that is not a git repository gets no lint hook.

### 2026-09-25 Final review round 2: Needs fixes (I8) + re-graded false-positive regression
- I8 (README skipped the ruleset step): README / README.ja now start `harness:adopt` from step 4; adopt step 8 also checks the ruleset. Verified by grep (mechanical).
- Ruling: the reviewer graded the new false positives Minor; re-graded to Important by effect — code search, commit messages and Issue bodies that mention a guarded command were refused, and the template tells the agent not to rephrase but to ask the PO, so ordinary work would stop repeatedly. Fix: a quoted string is treated as a command only after `-c` or `eval`, normalized recursively (nested quotes), with quote state tracked across newlines and `$'…'` unwrapped. Cases `g-fq-*`, `a-fq-01` (false positives) and `g-nq-*`, `a-nq-01` (nested quotes) went RED → GREEN. Cost if wrong: a guarded command inside a quoted string passed to another interpreter flag (`python -c` is also `-c` and is covered; `node -e`, `ssh host '…'` are not).
- Ruling: `a-pp-22` (Issue body quoting `git push origin main`) now expects `pass` instead of `ask`. It documented a known false positive, which this fix removes; the protected-push rule itself is unchanged. Cost if wrong: none.
- `no-verify` now finds git's real subcommand before looking for `-n`, so `git log --grep commit -n 5` passes (`g-fq-06`).

### 2026-09-25 Final review round 3: Approved
- The reviewer re-ran 253 earlier probe lines (no regression), confirmed the -c/eval heuristic on docker/find/xargs/su/nohup/timeout forms, and mutated `lib/parse.sh` nine ways (each caught by a case). Remaining findings are Minor (below). mawk compatibility was reasoned, not run: the first green CI `check` on Ubuntu is the evidence.

### 2026-09-25 Publishing order: private first, ruleset after going public
- Ruling: the repository was created private, CI `check` ran on PR #1 (green on Ubuntu with mawk), then the PO approved switching it public, applying the ruleset, merging and tagging.
- Reason: the reviewer asked not to publish before CI proved the awk parser on mawk; GitHub Free returns 403 "Upgrade to GitHub Pro or make this repository public" for rulesets on private repositories, so the ruleset is applied right after the switch to public and before the merge.
- Cost if wrong: none; the ruleset is in place before the first merge to `main`.

## Proposals

Deferred Minor findings from the final review (none start a fix round):
- Abbreviated long options (`git reset --har`, `git clean --forc`, `git commit --no-verif`, `rm --rec --for`, `git worktree remove --forc`) and `git -c core.hooksPath=/dev/null`, `HUSKY=0` pass the guard.
- `pipe-shell` misses `bash <(curl …)`, `| /bin/bash`, `| sudo -E bash`, `| tee x | sh`, backticks, `source <(curl …)` (the template's `ask: Bash(curl:*)` still prompts).
- `secrets-dir` / `env-file` miss spelling variants (`cd ~ && cat .ssh/…`, `/root/.ssh`, `~user/.ssh`, `.env*`, `git show HEAD:.env`, case variants on case-insensitive filesystems); the sandbox `denyRead` and Read deny rules cover sandboxed Bash.
- `guard.sh` fails open on malformed hook input JSON; an invalid `HARNESS_LINT_PATTERN` / `HARNESS_DOC_PATTERN` silently disables lint/tests.
- Tests: no case for the jq-missing paths; `run.sh` does not assert which rule blocked; `l-symlinked-path` runs only on macOS; the bash 3.2 run is not in CI.
- Template: `allowedDomains` lacks `release-assets.githubusercontent.com`; `Bash(gh api user:*)` also allows `gh api user -X PATCH`; the `.env` deny list is enumerated (`.env.staging` not denied; `Read(.env.*)` + `Read(!.env.example)` is simpler); the workflow skill's `.superpowers/` ledger is gitignored, so rulings recorded only there are not committed; `git ls-files -m` in mutation-check lists deleted files.
- Hooks docs: exec form (`"command":"bash","args":[…]`) is recommended when a path placeholder is used; the Stop hook could use `additionalContext` instead of `decision:block`.
- Over-engineering: `copier.yml` `_templates_suffix: .jinja` is Copier's default; `lib/parse.sh` GOPT lists value-taking long options by name.
- `tests/hooks/mutate.sh` does not mutate `scripts/lib/parse.sh` (the reviewer mutated it by hand; each mutation failed at least one case).
- A quoted `.env` is treated as a file name, so `jq '.env' .claude/settings.json` is refused.
- Round 3 Minors: very large commands (≈400 KB) make the character-by-character parser exceed the 10 s hook timeout, and a timed-out hook does not block — cap the size or build with `split()`; `bash -c -- '…'`, `bash -c -x '…'`, `bash <<< '…'`, `watch '…'`, `ssh host '…'`, `python3 -c "…os.system(…)"`, `node -e`, `git -c 'alias.x=!…'` are not seen; `grep -c "rm -rf" f` is a new false positive; `~/.ssh` mentioned inside a commit message is refused (undocumented); the unterminated-quote branch in `normalize` (lib/parse.sh) is unneeded.
