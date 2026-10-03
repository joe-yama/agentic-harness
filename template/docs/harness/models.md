# Models and effort

Which model and effort each role uses. This is the only place that names them: `CLAUDE.md`, `AGENTS.md`, `.claude/rules/` and the skills refer here instead of writing a model name.

| Role | Model | Effort | Why |
|---|---|---|---|
| Decision: the design session, including writing `design.md` and `tasks.md` as the plan | Opus | high | A wrong decision costs every later step. The session that decides also breaks the work into tasks, so the split is written once. |
| Final review of the whole branch | Opus | high | It catches what the batched reviews missed, and it is the last check before the PR. |
| Implementation | Sonnet | medium | The task is already specified in `tasks.md`; the work is writing the tests and the code the task names. |
| Intermediate review | Sonnet | medium | It checks a few tasks against the change; the final review covers the rest. |

No role uses Haiku.

## How the model and effort are set

- The `model` of an Agent call is set per role on every dispatch. An omitted `model` inherits the session's, so always pass it.
- Effort is not an Agent parameter. It comes from the session or from the agent's frontmatter. The `harness:implementer` frontmatter is `sonnet` / `medium`. The `harness:reviewer` frontmatter is `opus` / `high`. An intermediate review passes `model: "sonnet"` in the call and keeps the reviewer's effort of high.
