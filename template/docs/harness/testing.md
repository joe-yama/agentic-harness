# Test design

Where each behavior is tested, and what is not tested. The always-on rules are in `.claude/rules/testing.md`; read this file when writing a change's test plan (`design.md`) and when reviewing tests. Adapt the layer table to the stack once it exists.

## One layer per behavior

Each behavior is tested at exactly **one** layer: the cheapest one that can show it. The change's `design.md` holds the test plan, a table of behavior → layer. A second layer for the same behavior needs a reason in that table.

| Layer | Tests | Default for |
|---|---|---|
| Unit | logic, parsing, calculation, branches | anything without I/O |
| Route / API | request → response: status, body, persistence, refusals | server behavior and authorization |
| Component | UI states, interaction, conditional rendering | all UI detail |
| E2E | one happy path per feature across API, UI and DB | only that one path |
| Style lint / visual test | colors, spacing, layout, typography | all visual detail |

## Tests we do not write

- Verbatim copy assertions (policy text, landing-page copy, labels). Assert a key, a role or a structure instead.
- Re-assertions of CSS declarations in unit or component tests; style lint and visual tests own them.
- "The removed text is absent" tests.
- Copies of design-doc assets (mockups, sample data pasted from docs) as fixtures or snapshots.
- E2E steps re-implemented in unit or component tests.
- A test at a second layer for a behavior its layer already tests.

## Invariants over per-feature tests

A rule that holds everywhere is tested once, as an invariant every feature passes through, not written again in each change:

- **Shared after-each check.** Example: fixtures seed known personal values, and one after-each hook asserts the logs contain none of them. A new feature is covered as soon as its tests run.
- **Route × audience refusal table.** One table lists every read route and who may read it; one test walks the table, checks each refusal, and fails when the router has a read route the table does not list. A new route adds a row, not a test file.

Prove each invariant once with `harness:mutation-check`; a new row needs no mutation check of its own.

## Test-to-source ratio

CI warns (step `Test-to-source ratio`) when a PR adds more than `HARNESS_TEST_RATIO_MAX` (default 3) test lines per added source line (docs, specs and config count as neither), so a test-only PR always warns. Cut the duplicated layers, or give the reason in a PR body line starting `Test ratio:`.
