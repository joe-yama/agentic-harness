# Deferred Minors — ledger

Plan: `docs/plans/2026-09-25-deferred-minors.md`. Branch `fix/deferred-minors`.

### 2026-09-25 Docs checked for M17, M18, M21
- Ruling: hooks.json moves to exec form (`command` + `args`); the `.env` deny list uses `!` carve-outs; the Stop hook keeps `decision:block`.
- Reason: code.claude.com/docs/en/hooks ("Set `args` whenever the hook references a path placeholder"); code.claude.com/docs/en/permissions (a `!` deny pattern is a gitignore negation over earlier rules of the same file); Stop `additionalContext` only changes the transcript label, while `decision:block` works on every client.
- Cost if wrong: an older client without exec-form support would not run the hooks — `tests/manifest.sh` and the pinned Claude Code in CI are the evidence.

### 2026-09-25 Task 1 (M1–M4) done
- Commits 26c7a35, e46545b, aa218f2, 5b9662b. `cases.tsv` expects `block:<id>` / `ask:<id>` / `pass` (192 cases converted, kinds unchanged); jq-missing cases in `lifecycle.sh`; `l-symlinked-path` portable, and needs `HARNESS_LINT_PATTERN=^src/` to catch `pwd -L`; `parse.sh` has 7 marked blocks, `mutate.sh` covers `lib/*.sh` (rules=28 survived=0, new case `g-rm-16`).
- Carried into Task 2: guard's jq-missing message gets the id `no-jq`, and the four jq-missing branches get rule markers.
