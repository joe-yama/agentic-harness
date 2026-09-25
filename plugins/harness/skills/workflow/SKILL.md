---
name: workflow
description: The per-change lifecycle of a PO-steered repository - brainstorm, OpenSpec proposal plus one GitHub Issue, plan, TDD implementation by subagents, adversarial review, PR, archive, status update. Use when starting, resuming or finishing any change, or when unsure whether to stop and ask the PO.
---

# Change workflow

The PO (a human) decides what to build, priorities and acceptance, and does not specify implementation details. The agent proposes designs, implements, tests, reviews and writes docs. No implementation before design approval, and nothing outside the spec.

## Lifecycle of one change

1. **Idea.** The PO describes it in 1-4 sentences.
2. **Design.** Run `superpowers:brainstorming` and get the PO's approval. Settle every open question here, so implementation never has to stop for the PO.
3. **Proposal.** Run `/opsx:propose` to create proposal, delta specs, design and tasks under `openspec/changes/<name>/`. At the same time, create exactly one GitHub Issue for the change (see "Issue" below).
4. **Plan.** Start implementation in a **new session**. Run `superpowers:writing-plans`. The plan says which tasks get their own review and which are reviewed together (`harness:review-loop`).
5. **Implement.** Work in a git worktree on `feature/<change-name>`. Before the first task, check whether `origin/<default branch>` moved since the change was proposed and merge it (parallel worktrees drift; a delta spec's MODIFIED block can silently drop requirements another change added). Run `superpowers:subagent-driven-development`: dispatch `harness:implementer` per task with `model: "opus"`. **One implementer per worktree at a time** — they share the git index, build output and ports.
6. **Review.** Follow `harness:review-loop`. The implementing context never reviews its own work.
7. **PR.** Create the PR with `Closes #<issue>` in the body and the evidence (commands, results, CI run, review verdict).
8. **Acceptance.** The PO tries the result and merges. Then run `/opsx:archive` and update `docs/status.md` to the new current state.

If a guardian test was written (a test meant to catch a specific regression), the change's `tasks.md` contains a task to prove it with `harness:mutation-check`.

## Small-change path

For a change that touches only docs, `.claude/`, or styles, or at most 5 files without a new spec requirement:

- skip brainstorming, **but still create the Issue**;
- use `tasks.md` itself as the brief, run the implementer once, and review the whole branch once.

Edits to the harness or docs that belong to no change go straight to a `fix/<description>` branch and PR, without an Issue. When in doubt, use the full path.

## Bundle changes

Put as much as possible into one change. Split only where parallel worktrees would conflict, not by theme.

## Stop and ask only for these

| # | Stop for | Examples |
|---|---|---|
| 1 | Destructive or irreversible operations | deleting data or branches, rewriting pushed history, discarding uncommitted work |
| 2 | Security | secrets, credentials, permissions, anything that widens access |
| 3 | Side effects outside the worktree | pushing to the default branch, publishing, releases, merging, creating repositories |
| 4 | A plan defect where every way forward is a guess | the spec contradicts itself on the core behavior |

For everything else during implementation, **do not stop**. Rule by the spec, record the ruling, and continue. The PO can overturn it later.

## Ruling format

Record each ruling in the ledger (`.superpowers/sdd/<plan>/progress.md` or the change's ledger) and in the Issue:

```
### <date> <title>
- Ruling: <what was decided>
- Reason: <why, with the spec section or evidence>
- Cost if wrong: <what breaks and how it would be noticed>
```

## Issue

One Issue per change, titled with the change name. The body holds the goal, scope (in / out), the path `openspec/changes/<name>/`, and the completion criteria. Comment at these six milestones only — never per task:

1. PO approval of the design / proposal
2. Implementation started
3. Change of direction (reason and new direction)
4. Blocker or question for the PO
5. Final review result (`harness:review-loop` step 5)
6. PR created

Pass long bodies with `--body-file <file>`; command-like text in a heredoc body can trip hooks and the auto-mode classifier. Before any `gh` write, confirm `gh api user --jq .login` is the repository owner named in `AGENTS.md`.

## Definition of done

Report "done" only when all of these hold, with evidence:

- tests are green — show the command and its output;
- lint passes;
- `tasks.md` is updated;
- everything is committed;
- **the CI result is the final evidence.** Local green is not done; defects that only CI or real data shows are common.

## Long and unattended runs

Use `/goal <completion condition> or stop after N turns` and always give a turn limit. Headless: `claude -p --permission-mode auto --permission-prompts none --max-turns N`; operations that would prompt are denied and skipped, so list them in the final report. Wait for long jobs with background commands (`gh run watch`, a file appearing), not with polling loops that consume turns.
