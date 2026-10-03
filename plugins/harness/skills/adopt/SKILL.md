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
git diff --exit-code .claude/settings.json
```

The plugin has no plugin dependencies. The template renders `.claude/settings.json` the way the install writes it, so the diff must be empty. A diff means this Claude Code version writes a different layout, or the file was edited after rendering; read it before committing. Restart the session so hooks, agents and skills load. Plugins run with your user privileges; read `plugins/harness/scripts/` at `<tag>` before installing. Until a folder is trusted, `claude -p` also ignores the project's `permissions.allow` entries.

## 6. OpenSpec

```sh
openspec init --tools claude
```

It keeps the template's `openspec/config.yaml`. The harness uses only `/opsx:propose`, `/opsx:archive` and `/opsx:update` (`opsx/sync.md` stays: `/opsx:archive` calls it). Delete what the default profile also generates, which CI job `check` rejects:

```sh
[ -d .claude/skills ] && find .claude/skills -mindepth 1 -maxdepth 1 -name 'openspec-*' -exec rm -r {} +
rm -f .claude/commands/opsx/apply.md .claude/commands/opsx/explore.md
```

`openspec update` brings them back under the default profile. Optionally (each person, once, outside the repository) set OpenSpec's global profile so they are never generated; it lives in `~/.config/openspec/config.json` and cannot be set per repository:

```sh
openspec config set profile custom
openspec config set workflows '["propose","archive","update"]'
openspec config set delivery commands
```

Run these before `openspec init` to skip the deletion above. Commit.

## 7. Open the PR (PO merges)

Push the branch and open a PR against the default branch. CI job `check` must be green (it checks the context budget and that no stripped OpenSpec file is present). The PO merges.

## 8. Verify in a new session

In a new interactive session on the default branch, check:

- `rm -rf ./harness-guard-probe` is refused with `BLOCKED by harness guard (rm-rf)`;
- `git push origin <default branch>` asks for confirmation (`harness ask-gate (protected-push)`) — decline it;
- `/plugin` shows `harness` enabled;
- the skill list shows `harness:design` and `harness:execute` and no `openspec-*` skill, and `.claude/commands/opsx/` holds only `propose.md`, `archive.md`, `update.md` and `sync.md`;
- `/agents` lists `harness:implementer` and `harness:reviewer`;
- `gh api repos/<owner>/<repo>/rulesets --jq '.[].name'` lists `default-branch`.

## 9. Record

Fill "Harness versions" in `docs/status.md`: agentic-harness tag, OpenSpec CLI version, Claude Code version, and the results of step 8.

## Updating an adopted repository

On a branch:

```sh
uvx copier@9.18.2 update --vcs-ref <new tag>
grep -rnE '^(<<<<<<<|>>>>>>>) ' . --exclude-dir=.git     # Copier writes conflicts inline, not as .rej files
```

`copier update` three-way-merges template changes and moves the marketplace pin in `.claude/settings.json` to the new tag. Before resolving conflicts, read the agentic-harness changelog entries between the old and the new tag (`https://github.com/joe-yama/agentic-harness/blob/<new tag>/CHANGELOG.md`, not the product's own changelog); they say how to resolve the conflicts a release is known to cause. Resolve every conflict marker (a conflicted `.claude/settings.json` is not valid JSON until you do). Under auto mode the agent cannot write `.claude/settings.json`; prepare the merged file in the scratchpad and ask the PO to place it. Then restart the session so the new pin is read, run `claude plugin update harness@agentic-harness`, run the checks and open a PR.

### From 0.3.x to 0.4.0 (no backward compatibility)

0.4.0 drops the Superpowers dependency and replaces the design document and plan document with the OpenSpec change itself. After `copier update`:

1. **Delete the files 0.3.x installed.** `.claude/skills/openspec-*` (including any that `gh skill install` added), `.claude/commands/opsx/apply.md` and `.claude/commands/opsx/explore.md`; the commands in step 6 do it. CI job `check` fails while they exist.
2. **`.claude/settings.json`.** The `enabledPlugins` entry for Superpowers becomes `false`. The template update brings this; keep it when resolving the conflict, and move the marketplace `ref` to the new tag. A user-scope Superpowers install would otherwise keep injecting its own instructions.
3. **Where the plan lives.** Design and plan are no longer separate documents: the OpenSpec change is both, and `tasks.md` is the plan (per task: files, tests first, review unit). The ledger is `.harness/<change>/progress.md` (gitignored). The separate review skill is merged into `harness:execute` (see the CHANGELOG). `harness:implementer` and `harness:reviewer` receive the change path and the task numbers or range, not a task brief. Old design and plan documents stay as history.
4. **`ci.yml` conflicts.** Keep the new OpenSpec-files step next to your own steps.
5. **`docs/harness/models.md`** is new: the role-to-model table. Keep any project-specific history below it and make `CLAUDE.md` refer to it instead of naming models.
