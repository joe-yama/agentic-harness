---
name: adopt
description: Sets up the agentic-harness in a new or existing repository (Copier template, plugin, OpenSpec, branch ruleset) and verifies the guard hooks are live; also updates an adopted repository to a newer harness version. Use when asked to adopt, install, bootstrap or update the harness.
---

# Adopt the harness

Run the steps in order in the target repository and finish with the verification report. Steps marked **(PO)** are side effects outside the repository: explain them and let the PO confirm.

## 1. Preflight

```sh
claude --version        # 2.1.277 or later (AGENTS.md is read natively from 2.1.277)
jq --version && git --version && uv --version && openspec --version
gh auth status && gh api user --jq .login
```

The login must be the account that will own the repository. If it is not, stop and ask the PO to run `gh auth switch`.

## 2. Repository with a default branch (PO)

The PR in step 7 needs a base branch on GitHub. For a new repository:

```sh
git init -b main                      # use the chosen default branch name
git commit --allow-empty -m "chore: initial commit"
gh repo create <owner>/<repo> --private --source . --push    # or --public
```

For an existing repository, make sure the default branch exists on GitHub with at least one commit.

## 3. Render the template

Pick the harness version `<tag>` (latest `vX.Y.Z` at https://github.com/joe-yama/agentic-harness/releases). On a branch:

```sh
git switch -c fix/adopt-agentic-harness
uvx copier@9.18.2 copy --vcs-ref <tag> gh:joe-yama/agentic-harness .
```

Answer the questions: `project_name`, `project_summary` (may stay empty), `github_owner`, `default_branch`, `work_language`, `lint_cmd` / `lint_pattern` / `test_cmd` (leave empty when the stack is not chosen yet; the first change sets them), `ui_review`. Commit the result.

## 4. Branch ruleset (PO)

```sh
gh api -X POST repos/<owner>/<repo>/rulesets --input docs/harness/ruleset.json
```

It makes the default branch PR-only with the required status check `check` (the CI job name) and blocks deletion and force pushes. The PR in step 7 is the first one it applies to.

## 5. Install the plugin

Start an **interactive** Claude Code session in the repository and accept the workspace trust dialog. Trusting the folder registers the `agentic-harness` marketplace from `.claude/settings.json`, pinned to `<tag>`. Do **not** add the marketplace by hand with `claude plugin marketplace add`: that registers the unpinned default branch under the same name. Then install the plugin for the project:

```sh
claude plugin install harness@agentic-harness --scope project
```

This also installs the `superpowers@claude-plugins-official` dependency. Restart the session so hooks, agents and skills load. Plugins run with your user privileges; read `plugins/harness/scripts/` at `<tag>` before installing. Until a folder is trusted, `claude -p` also ignores the project's `permissions.allow` entries.

## 6. OpenSpec

```sh
openspec init --tools claude
```

It keeps the template's `openspec/config.yaml`. Replace the generated OpenSpec skills with pinned copies whose origin `gh skill` records (`<openspec-tag>` = the OpenSpec release matching the installed CLI, for example `v1.13.2`):

```sh
for s in openspec-propose openspec-apply-change openspec-archive-change openspec-explore openspec-sync-specs openspec-update-change; do
  gh skill install Fission-AI/OpenSpec "skills/$s" --agent claude-code --scope project --pin <openspec-tag> --force
done
```

Keep the `/opsx:*` commands `openspec init` created; call OpenSpec through them. Commit.

## 7. Open the PR (PO merges)

Push the branch and open a PR against the default branch. CI job `check` must be green (it checks the context budget). The PO merges.

## 8. Verify in a new session

In a new interactive session on the default branch, check:

- `rm -rf ./harness-guard-probe` is refused with `BLOCKED by harness guard (rm-rf)`;
- `git push origin <default branch>` asks for confirmation (`harness ask-gate (protected-push)`) — decline it;
- `/plugin` shows `harness` and `superpowers` enabled;
- `gh skill list --agent claude-code --scope project` lists the six OpenSpec skills with their pinned tag;
- `/agents` lists `harness:implementer` and `harness:reviewer`;
- `gh api repos/<owner>/<repo>/rulesets --jq '.[].name'` lists `default-branch`.

## 9. Record

Fill "Harness versions" in `docs/status.md`: agentic-harness tag, Superpowers version, OpenSpec CLI and skill tag, Claude Code version, and the results of step 8.

## Updating an adopted repository

On a branch:

```sh
uvx copier@9.18.2 update --vcs-ref <new tag>
grep -rnE '^(<<<<<<<|>>>>>>>) ' . --exclude-dir=.git     # Copier writes conflicts inline, not as .rej files
```

`copier update` three-way-merges template changes and moves the marketplace pin in `.claude/settings.json` to the new tag. Resolve every conflict marker (a conflicted `.claude/settings.json` is not valid JSON until you do). Under auto mode the agent cannot write `.claude/settings.json`; prepare the merged file in the scratchpad and ask the PO to place it. Then restart the session so the new pin is read, run `claude plugin update harness@agentic-harness`, run the checks and open a PR.
