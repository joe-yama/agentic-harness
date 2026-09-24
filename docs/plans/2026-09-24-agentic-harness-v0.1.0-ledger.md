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

## Proposals

(Minor findings and out-of-scope ideas deferred to later versions.)
