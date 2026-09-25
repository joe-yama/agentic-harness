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
- `-c` after `grep`, `egrep`, `fgrep`, `rg`, `wc`, `head`, `tail`, `cut`, `uniq`, `tr` or `git grep` is a flag, so its quoted argument is not read as a command (`grep -c "rm -rf" f` passes).
- More quoted strings are checked as commands: after `-c` with options in between (`bash -c -- '…'`, `bash -c -x '…'`), a here-string to a shell (`bash <<< '…'`), and the quoted arguments of `watch` and `ssh <host>`. `node -e`, `perl -e` and code inside `python -c` stay out of reach.
- ask-gate looks up the current branch once per directory, so a long command of bare `git push` segments no longer runs past the hook timeout (64 KiB: 29 s → 0.6 s).
- guard blocks and ask-gate asks (`bad-parser`) when `lib/parse.sh` is missing, fails to source or does not define the parser, instead of letting every command through.
- An invalid `HARNESS_LINT_PATTERN` or `HARNESS_DOC_PATTERN` fails loudly: lint-on-edit exits 2 and test-on-stop blocks with `invalid HARNESS_…_PATTERN`, instead of silently skipping lint or tests.
- `hooks.json` uses the exec form (`"command": "bash"`, `"args": ["${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"]`), so the plugin path is passed as one argument without shell quoting.
- Template settings: the `.env` deny list is `.env`, `.env.*` and the carve-out `!.env.example` (for `Read` and `Edit`), so every `.env.*` name is denied; the sandbox allows `release-assets.githubusercontent.com` (GitHub release downloads redirect there); the allow rule for the account check is exactly `gh api user --jq .login`.
- Skills: `workflow` and `review-loop` record rulings in the change's committed `openspec/changes/<name>/` (then `docs/changes.md`), not in the gitignored `.superpowers/sdd/`; the `mutation-check` overlay skips deleted files (and deletes them in the copy) instead of failing in `tar`.

## [0.1.0] - 2026-09-25

- First release: guard / ask-gate / lint-on-edit / test-on-stop hooks, implementer and reviewer subagents, workflow / review-loop / mutation-check / adopt skills, and the Copier template.
