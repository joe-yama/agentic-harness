---
name: review-loop
description: Controller procedure for adversarial review during subagent-driven development - choosing review units, building the review package, dispatching harness:reviewer, batching findings, handling Minor findings and deciding when to rebuild. Use whenever a task or branch reaches review.
---

# Review loop (controller side)

The reviewer's own rules live in the `harness:reviewer` agent. This skill is what the controller does. The controller distributes the plan, judges and records; it does not write code and does not review.

## Review units

- Review a task **on its own** only when it touches a shared interface (types, schemas, URL structure), a spec requirement, or consistency across several files.
- Batch the rest into one review: style-only tasks, test hardening, docs, single-file mechanical edits.
- **Always review the whole branch once** at the end.
- Write the chosen units into the implementation plan.

## Steps

1. **Package.** When a review unit is reached, write a review package: the task brief(s), the global constraints, the implementer's report, and a diff file with the commit list, `--stat` and the full diff (`git log --oneline BASE..HEAD`, `git diff --stat BASE..HEAD`, `git diff BASE..HEAD`).
2. **UI.** If the unit has UI, build and start the preview server yourself and pass its HTTP URL (for example `http://127.0.0.1:4321/`). The reviewer never builds (it must not change the working tree). List the UI items to check; the reviewer has 80 turns.
3. **Dispatch.** `Agent(subagent_type: "harness:reviewer", model: "opus", prompt: <package path, URL, items>)`. Always pass the model; an omitted model inherits the session's.
4. **Fix round.** On "Needs fixes", send **all** Critical and Important findings to the implementer in **one** `SendMessage`. Split messages get findings dropped. When the implementer reports back, verify every "fixed" claim yourself with the diff and `grep` before re-review. **Stop any preview server you started before handing work back to an implementer** — a running server can hold the port the test suite needs.
5. **Re-review** by `SendMessage` to the same reviewer (history and prompt cache are kept; this also resumes a reviewer that hit its turn limit). For mechanical one-line fixes (a rename, wording, a single value), verify with diff and grep yourself and skip the re-review.

After the final review, write **one** comment on the change's Issue: verdict per unit, number of findings, whether a rebuild happened, and the Minor findings moved to later.

## Minor findings

- Minor findings never start a fix round. Copy them to the "Proposals" section at the end of the change's `tasks.md`.
- A report with only Minor and over-engineering findings counts as **Approved**.
- Two exceptions: the PO asks for the fix, or someone shows why it is Important (an input that breaks, or a spec sentence it contradicts).

## When to rebuild instead of fixing

Stop the fix loop and start a **fresh** `harness:implementer` (new context, `model: "opus"`, same brief plus the review report) when any of these holds:

1. spec compliance is ❌ and there is at least one Critical finding;
2. two fix rounds have passed without Approved;
3. the reviewer wrote "Re-implementation recommended".

Record the rebuild and its reason in the ledger and on the Issue.
