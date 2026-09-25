# Deferred Minors — ledger

Plan: `docs/plans/2026-09-25-deferred-minors.md`. Branch `fix/deferred-minors`.

### 2026-09-25 Docs checked for M17, M18, M21
- Ruling: hooks.json moves to exec form (`command` + `args`); the `.env` deny list uses `!` carve-outs; the Stop hook keeps `decision:block`.
- Reason: code.claude.com/docs/en/hooks ("Set `args` whenever the hook references a path placeholder"); code.claude.com/docs/en/permissions (a `!` deny pattern is a gitignore negation over earlier rules of the same file); Stop `additionalContext` only changes the transcript label, while `decision:block` works on every client.
- Cost if wrong: an older client without exec-form support would not run the hooks — `tests/manifest.sh` and the pinned Claude Code in CI are the evidence.

### 2026-09-25 Task 1 (M1–M4) done
- Commits 26c7a35, e46545b, aa218f2, 5b9662b. `cases.tsv` expects `block:<id>` / `ask:<id>` / `pass` (192 cases converted, kinds unchanged); jq-missing cases in `lifecycle.sh`; `l-symlinked-path` portable, and needs `HARNESS_LINT_PATTERN=^src/` to catch `pwd -L`; `parse.sh` has 7 marked blocks, `mutate.sh` covers `lib/*.sh` (rules=28 survived=0, new case `g-rm-16`).
- Carried into Task 2: guard's jq-missing message gets the id `no-jq`, and the four jq-missing branches get rule markers.

### 2026-09-25 Task 2 (M5–M15) done
- Commits f72fb17 (no-jq id and markers), 5e8d9a6 (M14, M15), 1662f5a (M10), e5d60b0 (M11), 3881e75 (M5), 1348741 (M6), 4f250bd (M7), 45653fc (M8), 36b1335 (M9), 8c292d3 (M13), de0ee6e (M12). `run.sh` 283 cases, `mutate.sh` rules=43 survived=0; `HOOK_BASH=/bin/bash` run.sh green. New rule blocks: path-case, jq-filter, parse-count-flag, parse-c-options, parse-here-string, parse-remote-command.
- M14: no case was removed. No case depended on the unterminated-quote branch; all cases still passed without it.
- M11 timings (Apple M4 Max, `/usr/bin/time -p`, command of exactly 65536 bytes, at de0ee6e; 181494a before M8–M13 gives the same within 0.1 s):

  | input (repeated to 64 KiB) | guard | ask-gate |
  |---|---|---|
  | `ls ; : aaa…` (the `bashpad` case) | 2.85 s | 0.48 s |
  | `git commit -m "word word …"` | 1.03 s | 0.46 s |
  | `bash -c 'echo word …'` (one quoted string) | 0.95 s | 0.80 s |
  | `bash -c 'git push origin x' ; …` | 0.70 s | 0.50 s |
  | `ssh h "a b" ; …` | 0.50 s | 0.36 s |
  | `git push x ; …` (cwd on a feature branch) | 0.77 s | **20.21 s** |
  | `git push;…` (cwd on a feature branch) | 0.81 s | **28.99 s** |

  guard stays well under the 10 s timeout. ask-gate does not when many push segments name no branch: each one runs `git symbolic-ref` for the current branch. Not fixed here (see the ruling below).
- mutate.sh speedup (181494a): mutant runs stop at the first failing case (`MUTATE_FAIL_FAST=1`, honored by `ng()` in `tests/lib.sh`) and run the short lifecycle suite first; the control run stays full. `bash tests/all.sh` 8:15 (HEAD 1348741 in a copy, old mutate) → 2:47 (new mutate, M7 in the tree). Survivor check: deleting `g-al-01`/`g-al-02` in a copy gives `SURVIVED: guard.sh rule:git-alias`, `rules=37 survived=1`, exit 1.

### 2026-09-25 Ruling: fail-fast lives in `ng()`
- Ruling: `MUTATE_FAIL_FAST=1` makes `ng()` exit 1; mutate.sh sets it only for mutant runs and runs lifecycle.sh before run.sh.
- Reason: a suite fails exactly when `ng()` is called once, so exiting there gives the same verdict; both suites call `ng()` only in the main shell (never in a subshell), so the exit ends the script.
- Cost if wrong: a future `ng()` inside `$(…)` would only end the subshell; the survivor check above would then show a false SURVIVED, not a false kill.

### 2026-09-25 Ruling: ask-gate over the timeout is reported, not fixed
- Ruling: the 20–29 s ask-gate runs above are recorded and proposed as a follow-up (look up the current branch once per directory in protected-push), not fixed in this task.
- Reason: M11 is committed and the fix is a change to ask-gate that none of M7–M13 covers; the brief for this round lists no ask-gate work. guard (the hard block) is unaffected.
- Cost if wrong: a command over about 30 KB of bare `git push x` segments followed by `git push origin main` times out ask-gate, and a timed-out hook does not ask, so the protected push is not routed to the human.

### 2026-09-25 Ruling: M8 / M9 / M12 / M13 edges
- Ruling: `.env.example` is compared after lowercasing, so `.ENV.example` passes; a credential directory after `:` (`git show HEAD:.ssh/x`) is not matched (the plan lists `:` for `.env` only); the jq filter is the first whitespace-separated word after jq's options, so `jq -f .env` is read as a filter and passes; after `grep`, `wc`, `head` … any quoted string after an option is data (not only after `-c`); every quoted argument of `watch` / `ssh` is a command, including `ssh -o 'ProxyCommand=…'`.
- Reason: the smallest rule that catches the listed spellings (plan: "prefer the smallest rule"); the false positives fail safe.
- Cost if wrong: `jq -f .env` can print parts of `.env` in its parse error; a `HEAD:.ssh/…` path passes. Both are proposed follow-ups.

### 2026-09-25 Ruling: awk checked on BWK awk only
- Ruling: the awk changes (pipe-shell, normalize) were run on macOS BWK awk 20200816; mawk is not installed and the Docker daemon is not running, so the Ubuntu CI job `check` is the mawk evidence.
- Reason: no new dependencies (plan).
- Cost if wrong: CI on the PR fails on mawk and the parser needs a fix before merge.
