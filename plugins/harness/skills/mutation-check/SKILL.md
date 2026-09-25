---
name: mutation-check
description: Proves that a test is a real guardian by breaking the code it guards in an isolated copy of the repository and watching the test go red, with a control run. Use after writing any test meant to catch a specific regression, and whenever "the tests are green" is being used as proof.
---

# Mutation check

"The tests are green" and "the test guards this behavior" are different claims. A test written together with its code often passes for the wrong reason: it checks a path real data never takes, a viewport where the formula is always positive, or a mock instead of the behavior. Prove it: break the guarded code and watch the test fail.

## Never mutate the working tree

Copy the repository **outside** the working tree, install dependencies **inside the copy**, and run the tests **inside the copy**. Sharing `node_modules`, virtualenvs, build caches or config roots with the working tree has produced false greens.

```sh
EXP="$(mktemp -d)/exp"
mkdir -p "$EXP" && git archive HEAD | tar -x -C "$EXP"
# overlay uncommitted files; -m also lists deleted files, which tar cannot read: delete those in the copy
git ls-files -m -o --exclude-standard | while IFS= read -r f; do
  if [ -e "$f" ]; then printf '%s\n' "$f"; else rm -f -- "${EXP:?}/$f"; fi
done | tar -c -T - | tar -x -C "$EXP"
(cd "$EXP" && <install>)      # e.g. pnpm install --frozen-lockfile --offline / uv sync --locked
(cd "$EXP" && <test>)         # control: must be green
# apply the mutation inside $EXP (edit the guarded line, invert a condition, drop a branch)
(cd "$EXP" && <test>)         # the targeted check must now be red
```

Run the overlay line from the working tree root. `<install>` and `<test>` are the repository's own commands from `AGENTS.md`; run only the targeted test file when the suite is slow.

## Rules

1. **Record both runs** — the control (unmutated, green) and the mutated run (red) — with the command and the relevant output lines. A red control means the copy is broken; fix the copy before concluding anything.
2. **Prove the run happened in the copy.** Read the runner's root or working-directory line (for example `RUN v5 /path/to/exp`, `rootdir: /path/to/exp`). Never infer it from test counts: a full copy always has the same number of tests as the working tree.
3. **Still green after the mutation?** Once, rebuild the copy from scratch with the mutation applied **before** installing, and run again. Also confirm the mutation took effect by calling the mutated function directly. If it is still green, the conclusion is "this test is not a guardian" — fix the test, not the procedure.

## Known traps

- Passing only a config file path (for example `--config copy/runner.config`) while the runner's root stays the working tree runs the **original** code and reports green.
- Copying only the files under test into a subdirectory of the working tree lets module resolution and caches reach the original tree.
- Stale transform or build caches inside the copy can mask the mutation; the from-scratch rebuild in rule 3 removes them.
- Ports and servers are shared between the copy and the working tree; do not run both end-to-end suites at the same time.

## Where it goes in a change

When a change adds a guardian test, its `tasks.md` gets one task: "prove <test> is a guardian with `harness:mutation-check`", with the mutation to apply. That task may be a check-only commit.
