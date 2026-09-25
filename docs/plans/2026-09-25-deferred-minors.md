# Deferred Minors from the v0.1.0 final review — plan

Source: `docs/plans/2026-09-24-agentic-harness-v0.1.0-ledger.md` § Proposals. Every item is handled here: fixed, or kept with a documented reason (marked **keep**). Branch `fix/deferred-minors`, one PR, no Issue (harness-only change). Ledger: `docs/plans/2026-09-25-deferred-minors-ledger.md`.

## Global constraints

- `AGENTS.md` rules apply: `bash tests/all.sh` green before every commit, test-first (add the failing case, watch it fail, then change the script), every hook rule between `# rule:<id>` / `# end:<id>` with a case, macOS `/bin/bash` 3.2 compatible (`HOOK_BASH=/bin/bash bash tests/hooks/run.sh`), awk must work on mawk (Ubuntu CI) and BWK awk (macOS), English, `README.ja.md` in sync with `README.md` in the same commit, commit prefixes `feat:` `fix:` `test:` `docs:` `chore:` `ci:`.
- Hooks stay a tripwire, not a sandbox: prefer the smallest rule that catches the listed spelling. Do not add rules beyond the items below.
- No new dependencies. Hooks use bash + jq + git only.
- Do not bump the plugin version or tag; add entries under `## Unreleased` in `CHANGELOG.md`.
- Pinned versions are unchanged. The CI job named `check` must keep its name.

## Items and rulings

### Task 1 — test harness first (`tests/`)

- **M1 run.sh asserts the rule.** The `expect` column becomes `block:<reason-id>`, `ask:<reason-id>` or `pass`, where `<reason-id>` is the id printed in `BLOCKED by harness guard (<id>)` / `harness ask-gate (<id>)`. Convert every existing case mechanically, then check a few by hand. A case that blocks for a different reason than expected now fails.
- **M2 jq-missing cases.** Add cases (in `lifecycle.sh` or run.sh with a `PATH` that lacks jq) for: guard blocks, ask-gate asks (`no-jq`), lint-on-edit and test-on-stop skip with the stderr message.
- **M3 `l-symlinked-path` on Linux.** Make the case portable: create a symlinked directory to the repo in `$TMP_ROOT` and lint through it, so it runs on every OS.
- **M4 mutate.sh covers `lib/parse.sh`.** Put `# rule:<id>` / `# end:<id>` markers around the independently removable pieces of `lib/parse.sh` (continuation join, `$'` unwrap, recursive normalization of `-c`/`eval` strings, path prefix on the command word, git global options, …) and make `mutate.sh` iterate `lib/*.sh` too. Every marker must be killed by a case (awk accepts `#` comments, so markers inside the awk program are fine).

### Task 2 — guard / ask-gate / parse.sh (`plugins/harness/scripts/`)

- **M5 abbreviated long options.** git and GNU rm accept unambiguous prefixes. A token of at least 4 characters (`--` + 2) that is a prefix of a guarded long option counts as that option: rm `--recursive` / `--force`; git push `--force` / `--force-with-lease` / `--force-if-includes`; git reset `--hard` / `--merge`; git clean `--force`; git branch `--delete` / `--force`; git commit `--no-verify` / `--no-gpg-sign`; git worktree remove `--force` (ask-gate). Cases: the spellings in the ledger (`--har`, `--forc`, `--no-verif`, `--rec --for`, `worktree remove --forc`) block/ask; `--no-edit`, `--help` pass.
- **M6 hook bypass by config.** `git -c core.hooksPath=…` (key case-insensitive) and an assignment `HUSKY=0` before a git command are `no-verify`. `git -c alias.<x>=!…` (a shell alias hides the command) is also blocked, as `git-alias`.
- **M7 pipe-shell spellings.** Block when a download (`curl`/`wget`) reaches a shell: a later pipe stage whose command word (after `sudo` and its options, and a path prefix such as `/bin/`) is `sh`/`bash`/`zsh`/`dash`/`ksh` — including after intermediate stages (`| tee x | sh`); process substitution `<(curl …)` given to a shell, `source` or `.`; `` `curl …` `` / `$(curl …)` given to `sh -c` / `eval`. Cases for each ledger spelling plus `curl -o x url | cat` and `curl url | jq .` passing.
- **M8 secrets-dir / env-file spellings.** Credential directory names match case-insensitively after `~`, `~user/`, `$HOME/`, `${HOME}/`, `/root/`, `/Users/<u>/`, `/home/<u>/`, and at the start of a word (`cd ~ && cat .ssh/id_rsa`). `.env` names match case-insensitively, after `:` (`git show HEAD:.env`), and as a glob (`.env*`, `.env.?`). `.env.example` stays allowed. The file-tool path check becomes case-insensitive too. Case `project/.aws/config` relative inside a repo is accepted as a false positive only at word start — document it.
- **M9 quoted `.env` as a jq filter.** The first non-option argument of `jq` / `yq` / `gojq` is a filter, not a file: `jq '.env' .claude/settings.json` passes; `jq . .env` still blocks.
- **M10 fail closed on bad input.** When the hook input is not valid JSON, guard blocks (`bad-input`) and ask-gate asks (`bad-input`).
- **M11 command size cap.** A command longer than 64 KiB is blocked by guard (`too-large`: "write it to a file and run the file") and asked by ask-gate, before `normalize` runs. Show on CI-like input that a command just under the cap finishes well under the 10 s hook timeout (record the timing in the ledger).
- **M12 more command strings.** Treated as commands (normalized recursively like `-c`): the string after `-c` even with option words in between (`bash -c -- '…'`, `bash -c -x '…'`); a here-string `<<< '…'` whose command word is a shell; the quoted argument(s) of `watch` and `ssh <host>`. **keep (documented limit):** `node -e`, `perl -e`, strings inside `python -c` code (`os.system('…')`) — `-e` is a pattern flag for grep/sed, and code in another language is out of reach of a text tripwire.
- **M13 `grep -c` false positive.** `-c` is a count/bytes/complement flag, not a command, when the segment's command word is `grep`, `egrep`, `fgrep`, `rg`, `wc`, `head`, `tail`, `cut`, `uniq`, `tr`, or `git grep`: `grep -c "rm -rf" f` passes; `sudo sh -c 'rm -rf x'` still blocks.
- **M14 unterminated-quote branch.** Remove the `if (q != "" …)` line after the loop in `normalize`: a shell refuses an unterminated quote, so nothing runs. Remove its cases if any exist only for that branch (not a weakening: the input cannot execute) and record it in the ledger.
- **M15 GOPT names. keep.** Value-taking long options with a separate value (`--git-dir <dir>`) must be named: a generic `--x <value>` pattern would swallow the subcommand (`git --no-pager push`). Add that reason as a comment above `GOPT`.

### Task 3 — lint / stop hooks, hooks docs

- **M16 invalid patterns fail loudly.** If `HARNESS_LINT_PATTERN` or `HARNESS_DOC_PATTERN` is not a valid extended regex (grep exit 2), lint-on-edit exits 2 with `invalid HARNESS_…_PATTERN`; test-on-stop returns `{"decision":"block"}` with that reason. Cases in `lifecycle.sh`.
- **M17 Stop hook `additionalContext`. keep.** Both keep the conversation going (docs: same `stop_hook_active` / 8-continuation protections; `additionalContext` only changes the transcript label). `decision:block` is supported by every Claude Code version, and a client that ignores `hookSpecificOutput.additionalContext` would let the turn end with red tests. Say so in the script header.
- **M18 exec form in hooks.** The hooks docs: "Set `args` whenever the hook references a path placeholder, since each element is passed as one argument with no quoting." Rewrite every entry of `plugins/harness/hooks/hooks.json` as `{"type":"command","command":"bash","args":["${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh"],"timeout":N}`; update `tests/manifest.sh` if it checks the command string, and any README text quoting it.

### Task 4 — template, skills, copier, docs

- **M19 `allowedDomains`.** Add `release-assets.githubusercontent.com` (GitHub release asset downloads redirect there).
- **M20 `gh api user`.** Replace `Bash(gh api user:*)` with `Bash(gh api user --jq .login)` (the only use the rules make).
- **M21 `.env` deny list.** The permissions docs: a deny pattern starting with `!` is a gitignore negation that carves out of the path rules listed before it in the same file. Replace the enumeration with `Read(.env)`, `Read(.env.*)`, `Read(!.env.example)` and the same three for `Edit`, in that order. `tests/template/run.sh` (check-jsonschema) must still pass.
- **M22 ledger is gitignored.** The workflow skill says rulings go to a committed file: the change's `openspec/changes/<name>/` (tasks.md or design.md) and `docs/changes.md` at archive, plus the Issue; `.superpowers/sdd/` is scratch. Check `review-loop` for the same wording.
- **M23 mutation-check overlay.** `git ls-files -m -o --exclude-standard` includes deleted files and `tar` fails on them; use `git ls-files -m -o --exclude-standard | while read f; do [ -e "$f" ] && …` or equivalent that skips deleted paths (and note that deleted files are then present in the copy — delete them in the copy too).
- **M24 `_templates_suffix`.** Remove `_templates_suffix: .jinja` from `copier.yml` (Copier's default); `tests/template/run.sh` proves rendering is unchanged.
- **M25 `~/.ssh` inside a commit message.** Documented limit in README / README.ja "Known gaps": credential paths are refused anywhere in the command text, including quoted messages. Also update that list for M5/M9/M12 (abbreviations now seen, `jq '.env'` passes, the new command strings, remaining `node -e` / `python -c` code limits) and M11.

### Task 5 — CI

- **M26 bash 3.2 in CI.** Add a separate job `bash32` on `macos-latest` running `HOOK_BASH=/bin/bash bash tests/hooks/run.sh` and `HOOK_BASH=/bin/bash bash tests/hooks/lifecycle.sh` (if lifecycle supports it; otherwise only run.sh). Do not rename `check`. The ruleset is not changed (outward-facing; proposed to the PO).

## Review

One implementer at a time (shared working tree). Task 2 gets its own review (shared parser, many rules); Tasks 1, 3, 4, 5 are reviewed together with the whole-branch review.
