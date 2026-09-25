# Changelog

All notable changes to this project are documented here. The plugin version in
`plugins/harness/.claude-plugin/plugin.json` and the git tags `vX.Y.Z` / `harness--vX.Y.Z` follow this file.

## Unreleased

- Tests: hook cases assert which rule fired (`block:<id>` / `ask:<id>`), cover a missing `jq`, and the mutation check covers `lib/parse.sh`.
- guard's missing-`jq` message carries the id `no-jq`, like ask-gate's.
- guard blocks and ask-gate asks (`bad-input`) when the hook input is not a JSON object, instead of letting the command through.
- A command over 64 KiB is blocked by guard and asked by ask-gate (`too-large`) before parsing, so the hooks cannot time out on it.
- Abbreviated long options count as the full option (`git reset --har`, `rm --rec --for`, `git commit --no-verif`, `git worktree remove --forc`).
- guard blocks hook bypass by configuration: `git -c core.hooksPath=…` and `HUSKY=0 git …` (`no-verify`), and shell aliases `git -c alias.<x>=!…` (`git-alias`).
- `pipe-shell` catches more spellings: `bash <(curl …)`, `source <(curl …)`, `| /bin/bash`, `| sudo -E bash`, `| tee x | sh`, and backticks or `$(curl …)` given to `sh -c` or `eval`.
- `secrets-dir` and `env-file` match case-insensitively (also for file tools); credential directories after `~user/` and `/root/` or at the start of a word (`cd ~ && cat .ssh/id_rsa`); `.env` after `:` (`git show HEAD:.env`) and as a glob (`.env*`, `.env.?`). A word starting with `.aws/` inside a project is refused too (accepted false positive).
- The first non-option argument of `jq` / `yq` / `gojq` is a filter, not a file: `jq '.env' .claude/settings.json` passes, `jq . .env` is still blocked.

## [0.1.0] - 2026-09-25

- First release: guard / ask-gate / lint-on-edit / test-on-stop hooks, implementer and reviewer subagents, workflow / review-loop / mutation-check / adopt skills, and the Copier template.
