---
name: workflow
description: The per-change lifecycle of a PO-steered repository - design, OpenSpec proposal plus one GitHub Issue, implementation with review, PR, archive, status update, one new session per stage. Use when starting, resuming or finishing any change, or when unsure whether to stop and ask the PO.
---

# Change workflow

The PO (a human) decides what to build, priorities and acceptance, and does not specify implementation details. The agent proposes designs, implements, tests, reviews and writes docs. No implementation before design approval, and nothing outside the spec.

## Lifecycle of one change

1. **Idea.** The PO describes it in 1-4 sentences.
2. **Design and proposal.** Run `harness:design`: the design dialogue with the PO, then OpenSpec propose writes the proposal, delta specs, `design.md` and `tasks.md` under `openspec/changes/<name>/`. `tasks.md` is also the implementation plan; there is no separate plan document. Create exactly one GitHub Issue for the change (see "Issue" below). Settle every open question here, so implementation never has to stop for the PO.
3. **Implementation.** In a **new session**, run `harness:execute`: ledger, one `harness:implementer` per task or batch, review in the units `tasks.md` declares, fix rounds. **One implementer per worktree at a time**, on a git worktree branch `feature/<change-name>`.
4. **Final review and PR.** `harness:execute` ends with one review of the whole branch, then the PR with `Closes #<issue>` and the evidence (commands, results, CI run, review verdict). The implementing context never reviews its own work.
5. **Acceptance.** The PO tries the result and merges.
6. **Archive.** Run OpenSpec archive, copy the change's rulings into `docs/changes.md`, and update `docs/status.md` to the new current state.

## OpenSpec and agents

| Agent | Propose | Archive | Update |
|---|---|---|---|
| Claude Code | `/opsx:propose` | `/opsx:archive` | `/opsx:update` |
| Codex | `$openspec-propose` | `$openspec-archive-change` | `$openspec-update-change` |
| Copilot CLI | skill `openspec-propose` | skill `openspec-archive-change` | skill `openspec-update-change` |

## Mixed agents

Any stage may run in any agent the repository selected (`.copier-answers.yml` `agents`): for example the design session in Claude Code and `harness:execute` in Codex. Nothing else changes: the hand-off is still the committed change files and the ledger. The PR evidence names the agent and model of each stage.

If a guardian test was written (a test meant to catch a specific regression), the change's `tasks.md` contains a task to prove it with `harness:mutation-check`.

## One new session per stage

Each stage runs in a new session: design and proposal; implementation (a few tasks at a time); final review and PR; archive. Hand-offs happen only through committed files (`design.md`, `tasks.md`, delta specs) and the ledger `.harness/<change>/progress.md`, never through conversation memory. Pass the next session the spec and design as files, not as a summary: a summary drops what the next session then has to re-read. Details for the implementation stage are in `harness:execute`.

## Small-change path

For a change that touches only docs, agent settings (`.claude/`, `.codex/`, `.github/copilot/`), or styles, or at most 5 files without a new spec requirement:

- skip the design dialogue, **but still create the Issue** and still write a short change with OpenSpec propose (`harness:design`, route choice);
- `tasks.md` is the brief: run the implementer once, and review the whole branch once.

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

Record each ruling in a committed file and in the Issue. The file is in the change's `openspec/changes/<name>/` (`tasks.md` or `design.md`); at archive, copy the rulings into `docs/changes.md`. The ledger `.harness/<change>/progress.md` is gitignored scratch: a ruling kept only there is lost.

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
5. Final review result (`harness:execute`, final review)
6. PR created

Pass long bodies with `--body-file <file>`; command-like text in a heredoc body can trip hooks and the auto-mode classifier. Before any `gh` write, confirm `gh api user --jq .login` is the repository owner named in `AGENTS.md`.

## Definition of done

Report "done" only when all of these hold, with evidence:

- tests are green — show the command and its output;
- lint passes;
- `tasks.md` is updated;
- everything is committed;
- **the CI result is the final evidence.** Local green is not done; defects that only CI or real data shows are common.

## Models

Which model and effort each role uses is in the project's `docs/harness/models.md`, in your agent's section. Where your agent passes a model per dispatch, pass it as that table says.

## Long and unattended runs

Always give a completion condition and a turn limit. In Claude Code and Copilot CLI, headless operations that would prompt are denied and skipped; list them in the final report. In headless Codex, `.codex/rules` `prompt` rules reject the command (observed in the Task 12 smoke test), but the ask-gate hook cannot ask, so the items it covers run unless a rule matches; the plugin hooks run only when the project is trusted:

| Agent | Headless |
|---|---|
| Claude Code | `claude -p --permission-mode auto --permission-prompts none --max-turns N` (interactive: `/goal <condition> or stop after N turns`) |
| Codex | `codex exec "<prompt>"` (`approval: never`: a `.codex/rules` `prompt` rule makes the command be rejected; observed with Codex CLI 0.160.0) |
| Copilot CLI | `copilot -p "<prompt>" --allow-all-tools --no-ask-user` |

Wait for long jobs with background commands (`gh run watch`, a file appearing), not with polling loops that consume turns.
