# Lessons

Read this when tests or CI fail in an unexpected way, when writing a new guardian test, or when touching CI.

A lesson is temporary. Head each one `### <YYYY-MM-DD> <title>`, the date it was written. It then ends one of two ways:

- **It becomes a check** (a CI step, a hook or a test). Cut the lesson to one line that names the check.
- **30 days after its date,** if it is still prose, it moves to `docs/harness/lessons-archive.md`. The periodic retro (`harness:workflow`) moves it.

Budget: 8,000 bytes (CI warns above).

## 1. Defects that only real data or real processes showed

<!-- For each: the change, what broke, why the unit tests could not see it, and the fix. -->

## 2. Green is not guardian

<!-- For each: the test that stayed green under a mutation, why it did, and how it was fixed. -->
