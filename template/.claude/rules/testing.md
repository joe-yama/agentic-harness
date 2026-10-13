# Testing rules

- No commit of implementation code without the matching new or updated tests.
- Red → green → refactor: write the failing test first, watch it fail for the expected reason, then implement.
- Test each behavior at one layer: `docs/harness/testing.md`.
- Never make tests pass by deleting, skipping or weakening them. If the specified behavior changes, update the OpenSpec spec first.
- Guardian tests are proven with `harness:mutation-check`, within the scope that skill states.
- Review and QA are done by a subagent with a context separate from the implementer's. UI is checked by the reviewer driving the running app over HTTP.
