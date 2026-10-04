# Scope rules

- Implement only the items in the change's `tasks.md` (`openspec/changes/<name>/`).
- No features, options or "nice to have" improvements the spec does not ask for. Write them under "Proposals" at the end of `tasks.md` or in the report to the PO.
- Scope changes go through a new `/opsx:propose`, not through implementation.
- A contradiction or gap in the spec found during implementation: rule by the spec where one reading is clearly intended and record the ruling; where every reading is a guess, it is a blocker — ask the PO.
- No application code before the design and the proposal are approved.
- Refactor existing code only within what the change's tasks cover.
