---
name: adopt
description: Sets up the agentic-harness in a new or existing repository (Copier template, plugin, OpenSpec, branch ruleset) and verifies the guard hooks are live; also updates an adopted repository to a newer harness version. Use when asked to adopt, install, bootstrap or update the harness.
---

# Adopt the harness

Run the steps in order in the target repository and finish with the verification report. Steps marked **(PO)** are side effects outside the repository: explain them and let the PO confirm.

## 1. Preflight

```sh
claude --version        # 2.1.277 or later (AGENTS.md is read natively from 2.1.277)
jq --version && git --version && uv --version
gh auth status && gh api user --jq .login
```

The login must be the account that owns the repository. If it is not, stop and ask the PO to run `gh auth switch`.

## 2. Render the template

Pick the harness version tag `<tag>` (latest release at https://github.com/joe-yama/agentic-harness/releases). From the repository root:

```sh
uvx copier@9.18.2 copy --vcs-ref <tag> gh:joe-yama/agentic-harness .
```

Answer the questions: `project_name`, `project_summary` (may stay empty), `github_owner`, `default_branch`, `work_language`, `lint_cmd` / `lint_pattern` / `test_cmd` (leave empty when the stack is not chosen yet; the first change sets them), `ui_review`. Commit the result on a branch (`fix/adopt-agentic-harness`).

## 3. Install the plugin

```sh
claude plugin marketplace add joe-yama/agentic-harness
claude plugin install harness@agentic-harness --scope project
```

This also installs the `superpowers@claude-plugins-official` dependency. Plugins run with your user privileges; read `plugins/harness/scripts/` of the tag before installing.

## 4. OpenSpec

```sh
openspec init --tools claude
```

Replace the generated OpenSpec skills with pinned copies whose origin `gh skill` records (`<openspec-tag>` = the OpenSpec release matching the installed CLI, for example `v1.13.2`):

```sh
for s in openspec-propose openspec-apply-change openspec-archive-change openspec-explore openspec-sync-specs openspec-update-change; do
  gh skill install Fission-AI/OpenSpec "skills/$s" --agent claude-code --scope project --pin <openspec-tag> --force
done
```

Keep the `/opsx:*` commands `openspec init` created; call OpenSpec through them.

## 5. Branch ruleset (PO)

```sh
gh api -X POST repos/<owner>/<repo>/rulesets --input docs/harness/ruleset.json
```

It makes the default branch PR-only with the required status check `check` (the CI job name), and blocks deletion and force pushes.

## 6. Open a PR

Push the branch and open a PR. CI job `check` must be green (it checks the context budget).

## 7. Verify in a new session

Start a **new** Claude Code session in the repository (hooks, agents and plugins load at session start) and check:

- `rm -rf ./harness-guard-probe` is refused with `BLOCKED by harness guard (rm-rf)`;
- `git push origin <default branch>` asks for confirmation (`harness ask-gate (protected-push)`) — decline it;
- `/plugin` shows `harness` and `superpowers` enabled;
- `gh skill list --agent claude-code --scope project` lists the six OpenSpec skills with their pinned tag;
- `/agents` lists `harness:implementer` and `harness:reviewer`.

## 8. Record

Fill "Harness versions" in `docs/status.md`: agentic-harness tag, Superpowers version, OpenSpec CLI and skill tag, Claude Code version, and the verification results of step 7.

## Updating an adopted repository

On a branch:

```sh
uvx copier@9.18.2 update --vcs-ref <new tag>
claude plugin marketplace update agentic-harness
claude plugin update harness@agentic-harness
```

`copier update` three-way-merges template changes and moves the plugin pin in `.claude/settings.json` to the new tag. Resolve conflicts (look for `*.rej` files), run the checks, and open a PR. Under auto mode the agent cannot write `.claude/settings.json`; prepare the merged file in the scratchpad and ask the PO to place it.
