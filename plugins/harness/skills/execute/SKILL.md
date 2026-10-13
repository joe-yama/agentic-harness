---
name: execute
description: The implementation session of a change - read the change, keep a ledger, dispatch harness:implementer per task, review in solo or batched units with harness:reviewer-intermediate, run fix rounds, rebuild when fixing fails, then one final review with harness:reviewer, one push and the PR. Use when starting or resuming implementation of a change that has a tasks.md.
---

# Execute a change (controller side)

One session, or a few, carries a change from its `tasks.md` to an open PR. The change directory `openspec/changes/<name>/` is the plan: there is no separate plan document and no separate task brief. The controller distributes the tasks, judges and records; it does not write code and does not review. The reviewer's own rules live in the `harness:reviewer` agent (`harness:reviewer-intermediate` carries the same instructions), the implementer's in `harness:implementer`.

Models and effort for every role (implementation, intermediate review, final review; in Claude Code also this controller session, the Controller row) are in the project's `docs/harness/models.md`, in your agent's section. Where your agent passes a model per dispatch, always pass it; an omitted model inherits the session's.

## 1. Start

- Use a **new session**. Do not continue from the design session: its long context is stale for this work.
- Work in a git worktree on `feature/<change-name>`. Before the first task, check whether `origin/<default branch>` moved since the change was proposed and merge it (parallel worktrees drift; a delta spec's MODIFIED block can silently drop requirements another change added).
- Read the change directory **in full, as files**: proposal, design, every delta spec, `tasks.md`. Do not summarize them for yourself or for a subagent; a summary drops what later has to be re-read. This is the only full read before the final review: implementers and task or batch reviewers read slices (section 2).
- Create or read the ledger `.harness/<change>/progress.md` (gitignored scratch). It holds the state a restart needs and every execution record: tasks dispatched (with BASE SHA) and completed (with commit range, review verdict and report paths), carry-overs to later tasks, mutation-check results, rebuilds and their reasons, open Critical and Important findings, the last pushed SHA, unanswered PO questions, operations that were refused, and the first file the next session should read. Minor findings are not copied here; they stay in the review reports. Rulings do not live here: they go to the change's `design.md` only (committed, in the `workflow` ruling format); an Issue comment links to them, never copies them. `tasks.md` holds the plan only: during execution it changes only by its checkboxes.

## 2. Dispatch

- For each task, or each batch the plan marks, start `harness:implementer` (how to start each subagent: the table in section 3). Pass only: the change path, the task number(s), the BASE SHA (the commit before the task starts), the report path `REPORT: .harness/<change>/reports/task-<N>-implementer.md` (`-r<k>` before `.md` for fix round k) and the scope of `harness:mutation-check` in these words: "Mutation checks: refusal tests for authorization and data access, security tests, and tests the reviewer doubts; nothing else." The task text is `tasks.md` itself; do not write a brief. The implementer reads the task's paragraph, the Requirements and Scenarios its `Refs:` names and the `design.md` decisions (`D<n>`) it names, as files. To add context, point at a file section (a path and a heading), never paraphrase it. When a ruling or carry-over affects the task, add its `design.md` heading (or the ledger line) to the dispatch.
- **One implementer per worktree at a time.** They share the git index, build output and ports.
- Note `Task N: dispatched (BASE <sha>)` in the ledger; on completion note the commit range, the review verdict and the report paths.
- **Replies.** Every harness subagent writes its full report to the report path and replies with a short block: `STATUS: ok | partial | blocked | failed`, the reviewer's `VERDICT`, `ARTIFACT: <report path>` and at most three summary lines. Judge from the block; open the report only when the next step needs it (findings to verify, a question, a failure). `partial`: resume the same subagent with a follow-up (table in section 3; the cache rule in section 4 applies). `blocked`: answer its question as below, by a follow-up. `failed`: read the report, then fix the cause or rebuild (section 3).
- If an implementer asks a question that the change files answer, answer from them. If the files do not answer it and every way forward is a guess, that is a plan defect: stop and ask the PO (`AGENTS.md`, "Stop and ask only for"). Otherwise rule by the spec, record the ruling in `design.md`, continue.
- A task without `Refs:` (planned before `Refs:` existed): answer the blocked implementer by a follow-up with the section pointers. Do not edit `tasks.md`.

## 3. Review

**Units.** Follow what each task declares in `tasks.md`: solo, a named batch, or `final`.

- A task is reviewed **solo** only when it carries the risk mark `security`, `authz`, `data` or `migration`. `ui` is not a solo mark: UI tasks go into batches (CI checks them, and the final review drives the app).
- Everything else is reviewed in batches of four to six tasks; the remainder may form a smaller batch.
- A change of three tasks or fewer may skip intermediate reviews (`Review: final` on every task, risk marks included): the final review is its only review.
- If `tasks.md` declares nothing, apply the same rule yourself and write the units into the ledger.
- **Always review the whole branch once** at the end (section 5).

**Package.** Give the reviewer paths and a range, never a diff body: the change path, the range `BASE..HEAD`, the review kind (task or batch review with the task numbers, or the final whole-branch review), the report path `REPORT: .harness/<change>/reports/<unit>-review.md` (`-r<k>` for re-review k), the implementer reports of the unit, and the UI URL when there is UI. A task or batch reviewer reads only the reviewed tasks' paragraphs and what their `Refs:` names; the final reviewer reads the whole change. Both read the diff themselves (`git log`, `git diff BASE..HEAD`).

**UI.** If the unit has UI, build and start the preview server yourself and pass its HTTP URL. The reviewer never builds (it must not change the working tree). List the UI items to check; the reviewer has a turn budget. Follow the project's rules on when UI is checked over HTTP (often once, at the final review). **Stop any preview server you started before handing work back to an implementer**: a running server can hold the port the test suite needs.

**Dispatch.** Start the reviewer with the change path, range, task numbers, URL and items:

| Agent | Implementer | Intermediate review | Final review | Follow-up to the same subagent |
|---|---|---|---|---|
| Claude Code | `Agent(subagent_type: "harness:implementer", model: …)` | `Agent(subagent_type: "harness:reviewer-intermediate", model: <intermediate>)` | `Agent(subagent_type: "harness:reviewer", model: <final>)` | `SendMessage` |
| Codex | `spawn_agent {agent_type: "harness-implementer", task_name, message, fork_turns: "none"}` | `spawn_agent {agent_type: "harness-reviewer-intermediate", task_name, message, fork_turns: "none"}` | `spawn_agent {agent_type: "harness-reviewer", task_name, message, fork_turns: "none"}` | `followup_task {target: <task_name>, message}`, then `wait_agent` |
| Copilot CLI | `task(agent_type: "harness:implementer", model: …, reasoning_effort: …, mode: "background")` | `task(agent_type: "harness:reviewer-intermediate", model: <fast model>, reasoning_effort: …, mode: "background")` | `task(agent_type: "harness:reviewer", model: <final>, reasoning_effort: …, mode: "background")` | `write_agent {agent_id, message}`, then `read_agent {agent_id, wait: true}` |

Codex: without `fork_turns: "none"` the child inherits the parent's context, and the context that implemented something must never review it. `fork_turns: "none"` is verified with Codex CLI 0.160.0: the child starts without the parent's context (without it the child forks the parent). Copilot CLI: take `model` from the Copilot section of `docs/harness/models.md`; a dispatch without `model` fails (fallback `gpt-5.6-luna`).

**Mutation checks.** Their scope is owned by `harness:mutation-check`; every implementer dispatch states it (section 2). Record each result in the ledger.

**Fix round.** On "Needs fixes", send **all** Critical and Important findings to the implementer in **one** follow-up to the same subagent (table above): the reviewer's report path and a new report path; split messages get findings dropped. When the implementer reports back, verify every "fixed" claim yourself with the diff and `grep` before re-review. Then re-review by a follow-up to the same reviewer (history and prompt cache are kept; this also resumes a reviewer that hit its turn limit). For mechanical one-line fixes (a rename, wording, a single value), verify with diff and grep yourself and skip the re-review.

**Minor findings.** They never start a fix round and are not copied anywhere: they stay in the review report, and the Issue comment at the PR reports them (section 5). The same holds for an implementer's out-of-scope observations. A repository may keep an optional `docs/proposals.md` that only the PO adds to.

- A report with only Minor and over-engineering findings counts as **Approved**.
- Two exceptions: the PO asks for the fix, or someone shows why it is Important (an input that breaks, or a spec sentence it contradicts).

**Rebuild instead of fixing.** Stop the fix loop and start a **fresh** `harness:implementer` (new context, same change path, task numbers and BASE, plus the review report) when any of these holds:

1. spec compliance is ❌ and there is at least one Critical finding;
2. two fix rounds have passed without Approved;
3. the reviewer wrote "Re-implementation recommended".

Record the rebuild and its reason in the ledger (`tasks.md` holds the plan only); the Issue comment at the PR reports it (section 5).

## 4. Waiting

- **Wait for the completion notice; never poll.** After a dispatch, end your turn. No sleep loops, no reading a subagent's output file or transcript while it runs, no recurring check-ins: each costs a turn and fills your context.
- **Stalls.** Claude Code stops a subagent that streams nothing for 10 minutes and reports it. The plugin's watchdog covers the rest:

| Agent | Watchdog | On an alert |
|---|---|---|
| Claude Code | The plugin monitor `watchdog` starts with every interactive session and prints a `harness watchdog: STALL` line (no transcript write for 15 min) or `TIMEOUT` line (2 h since start) per subagent; it is silent otherwise. Limits: `HARNESS_WATCHDOG_IDLE`, `HARNESS_WATCHDOG_MAX` (seconds). Headless `claude -p` runs no monitors | Check for a pending permission prompt first. Otherwise `TaskStop` the agent id, then resume it with `SendMessage` (it keeps the cache when the rule below allows) or dispatch a fresh one with the same inputs and its report so far |
| Codex | none | — |
| Copilot CLI | none | — |

- **Never leave a subagent waiting.** Do not dispatch a subagent whose answer you will not read soon, and do not hold one open while you wait for CI or the PO. Only the controller waits for CI.
- A subagent's prompt cache expires after about five minutes (an hour for `harness:implementer` in Claude Code: its `experimental.cacheTtl`, so a fix round after a review still hits the cache). If more than that passed since its last turn, do **not** resume it with a follow-up (table above); dispatch a fresh one with the same inputs plus what it needs to continue. If your agent cannot send a follow-up to a finished subagent, dispatch a fresh one with the same inputs plus the findings.
- **Before re-dispatching,** check that the earlier subagent is not still running (list the running agents). A restarted or resumed session can find the previous subagent still working, and two on one worktree corrupt each other's state. Wait for it or stop it first.
- **Context limit.** When your context passes about 200k tokens, or you must wait for the PO for more than an hour, write a handoff into the ledger (state, next task, open findings, first file to read) and end the session. Do not rely on compaction: it is itself a large request. A new session resumes from the ledger and the change files.

## 5. Finish

1. **Final review.** After the last task, run **one** review of the whole branch with the final-review agent and the model of the "final review" row of `docs/harness/models.md` (heavier than the intermediate review). It is the only review that reads the whole change. It catches what batched reviews missed. Its report maps **every** delta-spec scenario of the change to a test (`file:line`) or a verification task; a scenario with neither is an Important finding. Handle its findings as in section 3.
2. **Pre-push checks.** Fix every Critical and Important finding of the final review (Minor findings stay in the report, as in section 3), then run the project's pre-commit and pre-push checks (its commands in `AGENTS.md` and its testing docs) once more.
3. **Open the PR only after** implementation and the final review are done. No draft PR along the way, and do not open the PR at the start of a stage.
4. **One push.** Collect fixes into a single push, so CI runs once per push; the archive commit after acceptance is the only planned second push. Intermediate state is not visible on GitHub; the ledger is where progress lives. If the PR needs more than a few CI runs, write the cause in the ledger.
5. **PR body** (pass it with `--body-file`). `Closes #<issue>` plus the evidence: commands and their results, the review verdict, the scenario-to-test map, and the CI run.
6. **Issue comment.** Write **one** comment on the change's Issue when the PR is created, with the contents `harness:workflow` ("Issue") lists.
7. **While CI runs,** prepare the archive commit: draft the new `docs/status.md` (current state only) in the ledger, so the commit is quick once the PO accepts. Record the CI result in the ledger. The CI result, not local green, is the final evidence.

After the PO accepts, the archive commit goes on the feature branch before the merge, and is reverted if the PR is sent back (`harness:workflow`, lifecycle step 5).
