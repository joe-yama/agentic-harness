# Testing rules

- No commit of implementation code without the matching new or updated tests.
- Red → green → refactor: write the failing test first, watch it fail for the expected reason, then implement.
- Never make tests pass by deleting, skipping or weakening them. If the specified behavior changes, update the OpenSpec spec first.
- Never report "done" with a failing test. Show the command and its output.
- A test written to guard a behavior must be proven with a mutation check (break the behavior, watch the test fail) — `harness:mutation-check`.
- Review and QA are done by a subagent with a context separate from the implementer's. UI is checked by the reviewer driving the running app over HTTP.
