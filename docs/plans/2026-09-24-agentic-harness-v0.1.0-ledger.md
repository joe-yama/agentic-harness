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

## Proposals

(Minor findings and out-of-scope ideas deferred to later versions.)
