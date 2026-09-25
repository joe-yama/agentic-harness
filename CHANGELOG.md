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
- guard blocks hook bypass by configuration: `git -c core.hooksPath=…` and `HUSKY=0 git …` (`no-verify`), and shell aliases `git -c alias.<x>=!…` (`git-alias`).

## [0.1.0] - 2026-09-25

- First release: guard / ask-gate / lint-on-edit / test-on-stop hooks, implementer and reviewer subagents, workflow / review-loop / mutation-check / adopt skills, and the Copier template.
