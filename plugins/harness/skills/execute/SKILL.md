---
name: execute
description: The implementation session of a change - read the change, keep a ledger, dispatch harness:implementer per task, review in solo or batched units with harness:reviewer, run fix rounds, rebuild when fixing fails, then one final review, one push and the PR. Use when starting or resuming implementation of a change that has a tasks.md.
---

# Execute a change (controller side)

One session, or a few, carries a change from its `tasks.md` to an open PR. The change directory `openspec/changes/<name>/` is the plan: there is no separate plan document and no separate task brief. The controller distributes the tasks, judges and records; it does not write code and does not review. The reviewer's own rules live in the `harness:reviewer` agent, the implementer's in `harness:implementer`.

Models and effort for every role (implementation, intermediate review, final review) are in the project's `docs/harness/models.md`, in your agent's section. Where your agent passes a model per dispatch, always pass it; an omitted model inherits the session's.

## 1. Start

- Use a **new session**. Do not continue from the design session: its long context is stale for this work.
- Work in a git worktree on `feature/<change-name>`. Before the first task, check whether `origin/<default branch>` moved since the change was proposed and merge it (parallel worktrees drift; a delta spec's MODIFIED block can silently drop requirements another change added).
- Read the change directory **in full, as files**: proposal, design, every delta spec, `tasks.md`. Do not summarize them for yourself or for a subagent; a summary drops what later has to be re-read.
- Create or read the ledger `.harness/<change>/progress.md` (gitignored scratch). It holds the state a restart needs: tasks dispatched (with BASE SHA) and completed (with commit range and review verdict), carry-overs to later tasks, deferred Minor findings, open Critical and Important findings, the last pushed SHA, unanswered PO questions, operations that were refused, and the first file the next session should read. Rulings do not live only here: put them in the change's `design.md` or `tasks.md` (committed) and on the Issue, in the `workflow` ruling format.

## 2. Dispatch

- For each task, or each batch the plan marks, start `harness:implementer` (how to start each subagent: the table in section 3). Pass only: the change path, the task number(s) and the BASE SHA (the commit before the task starts). The task text is `tasks.md` itself; do not write a brief.
- **One implementer per worktree at a time.** They share the git index, build output and ports.
- Note `Task N: dispatched (BASE <sha>)` in the ledger; on completion note the commit range and the review verdict.
- If an implementer asks a question that the change files answer, answer from them. If the files do not answer it and every way forward is a guess, that is a plan defect: stop and ask the PO (see `harness:workflow`). Otherwise rule by the spec, record the ruling, continue.

## 3. Review

**Units.** Follow what each task declares in `tasks.md`: solo or a named batch.

- A task is reviewed **solo** only when it carries a risk mark (a shared interface, authorization, data or migration, security, UI, or a mark the project adds).
- Everything else is reviewed in batches of three or four tasks.
- If `tasks.md` declares nothing, apply the same rule yourself and write the units into the ledger.
- **Always review the whole branch once** at the end (section 5).

**Package.** Give the reviewer paths and a range, never a diff body: the change path, the range `BASE..HEAD`, the task numbers under review, and the UI URL when there is UI. The reviewer's ground truth is the change's delta specs, `design.md` and `tasks.md`; it reads the diff itself (`git log`, `git diff BASE..HEAD`).

**UI.** If the unit has UI, build and start the preview server yourself and pass its HTTP URL. The reviewer never builds (it must not change the working tree). List the UI items to check; the reviewer has a turn budget. Follow the project's rules on when UI is checked over HTTP (often once, at the final review). **Stop any preview server you started before handing work back to an implementer**: a running server can hold the port the test suite needs.

**Dispatch.** Start the reviewer with the change path, range, task numbers, URL and items:

| Agent | Implementer | Intermediate review | Final review | Follow-up to the same subagent |
|---|---|---|---|---|
| Claude Code | `Agent(subagent_type: "harness:implementer", model: …)` | `Agent(subagent_type: "harness:reviewer", model: <intermediate>)` | `Agent(subagent_type: "harness:reviewer", model: <final>)` | `SendMessage` |
| Codex | `spawn_agent {agent_type: "harness-implementer", task_name, message, fork_turns: "none"}` | `spawn_agent {agent_type: "harness-reviewer-intermediate", task_name, message, fork_turns: "none"}` | `spawn_agent {agent_type: "harness-reviewer", task_name, message, fork_turns: "none"}` | `followup_task {target: <task_name>, message}`, then `wait_agent` |
| Copilot CLI | `task(agent_type: "harness:implementer", model: …, reasoning_effort: …, mode: "background")` | `task(agent_type: "harness:reviewer", model: <fast model>, reasoning_effort: …, mode: "background")` | `task(agent_type: "harness:reviewer", model: <final>, reasoning_effort: …, mode: "background")` | `write_agent {agent_id, message}`, then `read_agent {agent_id, wait: true}` |

Codex: without `fork_turns: "none"` the child inherits the parent's context, and the context that implemented something must never review it. `fork_turns: "none"` is unverified until the smoke test. Copilot CLI: take `model` from the Copilot section of `docs/harness/models.md`; a dispatch without `model` fails (fallback `gpt-5.6-luna`).

**Mutation checks.** Where a new refusal or security test needs `harness:mutation-check`, follow the project's rules (`AGENTS.md`, `.claude/rules/` where present, and project docs) for which tests it is required for. Otherwise run it only when the reviewer doubts a test.

**Fix round.** On "Needs fixes", send **all** Critical and Important findings to the implementer in **one** follow-up to the same subagent (table above); split messages get findings dropped. When the implementer reports back, verify every "fixed" claim yourself with the diff and `grep` before re-review. Then re-review by a follow-up to the same reviewer (history and prompt cache are kept; this also resumes a reviewer that hit its turn limit). For mechanical one-line fixes (a rename, wording, a single value), verify with diff and grep yourself and skip the re-review.

**Minor findings.** They never start a fix round. Copy them to the "Proposals" section at the end of the change's `tasks.md` and note them in the ledger.

- A report with only Minor and over-engineering findings counts as **Approved**.
- Two exceptions: the PO asks for the fix, or someone shows why it is Important (an input that breaks, or a spec sentence it contradicts).

**Rebuild instead of fixing.** Stop the fix loop and start a **fresh** `harness:implementer` (new context, same change path, task numbers and BASE, plus the review report) when any of these holds:

1. spec compliance is ❌ and there is at least one Critical finding;
2. two fix rounds have passed without Approved;
3. the reviewer wrote "Re-implementation recommended".

Record the rebuild and its reason in the change's `openspec/changes/<name>/` (committed; the ledger is gitignored) and on the Issue.

## 4. Waiting

- **Never leave a subagent waiting.** Do not dispatch a subagent whose answer you will not read soon, and do not hold one open while you wait for CI or the PO. Only the controller waits for CI.
- A subagent's prompt cache expires after about five minutes. If more than five minutes passed since its last turn, do **not** resume it with a follow-up (table above); dispatch a fresh one with the same inputs plus what it needs to continue. If your agent cannot send a follow-up to a finished subagent, dispatch a fresh one with the same inputs plus the findings.
- **Before re-dispatching,** check that the earlier subagent is not still running (list the running agents). A restarted or resumed session can find the previous subagent still working, and two on one worktree corrupt each other's state. Wait for it or stop it first.
- **Context limit.** When your context passes about 200k tokens, or you must wait for the PO for more than an hour, write a handoff into the ledger (state, next task, open findings, first file to read) and end the session. Do not rely on compaction: it is itself a large request. A new session resumes from the ledger and the change files.

## 5. Finish

1. **Final review.** After the last task, run **one** review of the whole branch with the model of the "final review" row of `docs/harness/models.md` (heavier than the intermediate review). It catches what batched reviews missed. Its report maps **every** delta-spec scenario of the change to a test (`file:line`) or a verification task; a scenario with neither is an Important finding. Handle its findings as in section 3.
2. **Pre-push checks.** Fix every Critical and Important finding of the final review (Minor findings go to Proposals, as in section 3), then run the project's pre-commit and pre-push checks (its commands in `AGENTS.md` and its testing docs) once more.
3. **Open the PR only after** implementation and the final review are done. No draft PR along the way, and do not open the PR at the start of a stage.
4. **One push.** Collect fixes into a single push, so CI runs once per push. Intermediate state is not visible on GitHub; the ledger is where progress lives. If the PR needs more than a few CI runs, write the cause in the ledger.
5. **PR body.** `Closes #<issue>` plus the evidence: commands and their results, the review verdict, the scenario-to-test map, and the CI run.
6. **Issue comment.** Write **one** comment on the change's Issue after the final review: the verdict per review unit, the number of findings, whether a rebuild happened, and the Minor findings moved to Proposals.
7. **While CI runs,** use the wait yourself (archive preparation, status notes). Record the CI result in the ledger. The CI result, not local green, is the final evidence.

Acceptance, merge and OpenSpec archive follow in `harness:workflow`.
