---
name: design
description: The design session of a change - read the context, choose the route, ask the PO one question at a time, then write the whole change (proposal, delta spec, design, tasks that double as the plan) with OpenSpec propose, create the one Issue and end the session. Use when the PO brings a new idea or a behavior change, before any implementation.
---

# Design session

One session turns an idea into a change under `openspec/changes/<name>/` that a later session can implement without asking anything. It writes no application code. The change directory is the only place for the design and the plan: no separate design document, no separate plan document.

## 1. Read the context

- `AGENTS.md`, `docs/status.md`, and the idea as the PO wrote it.
- Every main spec the idea touches, **in full**: `openspec show <spec> --type spec`. Do not summarize or skim a spec; a delta spec's MODIFIED block replaces the whole requirement, so a requirement you did not read can be dropped silently.
- `openspec list` for changes in progress that touch the same specs.

## 2. Choose the route

Apply the small-change test from `harness:workflow`. A small change (only docs, agent settings (`.claude/`, `.codex/`, `.github/copilot/`) or styles, or at most 5 files without a new spec requirement) skips step 3 and goes straight to step 4 with a short change. Everything else takes the full route. When in doubt, take the full route.

## 3. Ask

Ask the PO, **one question at a time**. Each question offers 2-4 options and your recommendation with the reason. Do not batch questions; answers to the first often change the second.

- **Who answers.** The PO is the human, unless `AGENTS.md` names a delegated PO (a party that decides on the human's behalf). Then ask that party. A decision outside the delegation (the items `AGENTS.md` reserves for the human PO) is passed on to the human PO by that party.
- **Do not ask what the rules or earlier agreements already answer.** Decide it, and write it in `design.md` as a ruling (format below).
- **No one to ask (headless or unattended session).** Write the open questions to a file and stop. For each question: the options, your recommendation with the reason, and the cost if the recommendation is wrong. Do not guess and continue; a design built on a guessed answer costs more than a stopped session.

## 4. Write the change

When the agreements are complete, run OpenSpec propose (see the table in `harness:workflow`) and write all four artifacts:

- **proposal**: what and why, scope in and out.
- **delta spec**: requirements as SHALL / SHALL NOT, each with at least one `#### Scenario:` using WHEN / THEN. The reviewer later maps every scenario to a test or a verification task, so write scenarios that a test can check.
- **design.md**: only the decisions the implementation needs. Agreements already made are referenced in one line with their source, not copied. State who can see any stored or shown data when that matters. Rulings:

  ```
  ### <date> <title>
  - Ruling: <what was decided>
  - Reason: <why, with the spec section or evidence>
  - Cost if wrong: <what breaks and how it would be noticed>
  ```

- **tasks.md**, which is also the plan. Follow the shape in the project's `openspec/config.yaml` (`rules.tasks`); do not invent another. Per task `- [ ] N.M <what to do>`, indented below it:
  - `Files:` what is created, changed, tested.
  - `Interface:` names and types other tasks use (omit when none).
  - `Test first:` the test file that goes red first and what it checks (code tasks); for non-code tasks `Verify:` the command and the expected result.
  - `Review:` `solo` or `batch <letter>`, and `Risk:` marks (`security`, `authz`, `data`, `migration`, `ui`, and any the project adds). Solo review is for risk-marked tasks; the rest are batched three or four at a time.

  No code snippets: the implementer writes the code. Add a short mapping of each delta-spec scenario to the task that verifies it. End with an empty `Proposals` section for later findings.

Check consistency before finishing: every scenario has a test or a verify step, every interface used is declared by some task, and `openspec validate <name> --strict` passes.

## 5. Issue, then end

Create exactly **one** GitHub Issue for the change (see `harness:workflow`, "Issue"): title is the change name, body holds the goal, scope in and out, the path `openspec/changes/<name>/`, and completion criteria. Before any `gh` write confirm `gh api user --jq .login` is the repository owner named in `AGENTS.md`; pass long bodies with `--body-file`. Write `Issue: #<n>` at the top of `tasks.md`, commit the change, and **end the session**. Implementation starts in a **new session** with `harness:execute`; a design session that goes on to implement carries a long, stale context into the work.

Model and effort for this session: see `docs/harness/models.md` (the "decision" row; writing the design and `tasks.md` belongs to it).
