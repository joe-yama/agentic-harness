# agentic-harness — design

- Date: 2026-09-24
- Status: approved in conversation by the PO (2026-09-24); this document awaits written-spec review
- Origin: generalized from the harness of `joe-yama/portfolio` (CLAUDE.md, `.claude/rules/`, `.claude/agents/`, `.claude/hooks/`, `docs/harness/`), checked against current primary sources (Claude Code docs for v2.1.281, AGENTS.md, OpenSSF, GitHub Actions hardening guidance)

## 1. Goal

A public repository, `joe-yama/agentic-harness`, from which any new product repository of the PO can adopt, and later update, the product-development harness that was built and measured in `portfolio`:

- Roles: **PO = human** (decides what to build, priorities, acceptance), **Agent = Claude Code** (design proposals, implementation, tests, review, docs).
- Flow per change: brainstorming (Superpowers) → proposal/spec/design/tasks (OpenSpec) + one GitHub Issue → implementation plan → subagent-driven TDD implementation → adversarial review in a separate context → PR → PO acceptance → archive → status update.
- Enforcement by hooks and settings, not by prose alone.

Success criteria:

1. A new, empty repository reaches "harness ready" by following one documented procedure (the `adopt` skill), with the guard hooks demonstrably active.
2. Nothing in the distributed files is specific to `portfolio`, to one technology stack, or to one machine.
3. Hook behavior, template rendering and plugin manifests are verified automatically in CI (job `check`).
4. Updates reach adopting repositories through version tags: the plugin via `claude plugin update`, repo-scoped files via `copier update` as a reviewable PR.
5. An adversarial review by a context-free Opus subagent returns Approved before publishing.

## 2. Non-goals (v0.1.0)

- `claude plugin eval` suites (every run makes paid model calls; revisit once the skills stabilize).
- Migrating `portfolio` onto this harness.
- A gate that distinguishes personal from work GitHub accounts. That stays in the PO's user-level `~/.claude/permission-gate.sh`; the README documents the pattern.
- Support for agents other than Claude Code. `AGENTS.md` is written tool-neutrally so the door stays open, but plugins, hooks and subagents are Claude Code features.
- Stack presets. The template is stack-agnostic; the first change of each product introduces the stack (unchanged principle from portfolio: no dependencies or scaffolding before design approval).

## 3. Decisions

| # | Decision | Rationale | Source |
|---|---|---|---|
| D1 | Distribute as **one repository that is both a plugin marketplace and a Copier template**. | Plugins can carry skills, agents, hooks and MCP servers, but not `CLAUDE.md`, `.claude/rules/`, permissions, sandbox or `env`. Those must live in each repository; Copier is the mature tool that can later three-way-merge template updates (`copier update`). | code.claude.com/docs/en/plugins-reference ("A CLAUDE.md file at the plugin root is not loaded"; plugin `settings.json` supports only `agent` and `subagentStatusLine`), copier.readthedocs.io/en/stable/updating/ |
| D2 | **One version line.** Tag `vX.Y.Z` plus `harness--vX.Y.Z` (from `claude plugin tag`). The template pins the marketplace to the tag it was rendered from, so `copier update` moves the plugin pin and the repo files together. | Avoids version skew between the two channels. Version lives only in `plugin.json` (not also in the marketplace entry). | plugin-marketplaces (version pitfalls), plugin-dependencies (tag convention) |
| D3 | **`AGENTS.md` is the tool-neutral source of project facts; `CLAUDE.md` is `@AGENTS.md` plus Claude-specific notes.** Each stays under 200 lines. | Claude Code reads `AGENTS.md` natively only when no `CLAUDE.md` exists (v2.1.277+); an `@AGENTS.md` import works in every session and is never read twice. | code.claude.com/docs/en/memory#agents-md |
| D4 | English is canonical for everything the model reads; `README.ja.md` for humans. The working language of each product (commits, Issues, PRs, OpenSpec artifacts, status docs) is a template question, default `ja`. | PO decision (2026-09-24). | — |
| D5 | Stack-agnostic hooks configured through `env` in the product's `.claude/settings.json` (`HARNESS_*`, §5.2). Unset means the hook does nothing. | PO decision (stack-agnostic with a substitution point). `env` applies to the session and its subprocesses. | settings-reference (`env`) |
| D6 | Keep Superpowers + OpenSpec as the core. Superpowers is a **plugin dependency** on `superpowers@claude-plugins-official` (cross-marketplace allowlisted). OpenSpec comes from its CLI (`openspec init`), with its skills replaced by `gh skill install --pin` (PO instruction carried over from portfolio). | PO decision. Superpowers tags are `v6.4.1`, not `superpowers--v6.4.1`, so a semver range cannot resolve; the official marketplace already pins it by commit SHA. | plugin-dependencies ("Depend on a plugin from another marketplace") |
| D7 | Drop the `ponytail` dependency. The reviewer carries its own over-engineering pass, written in our words, crediting the idea. | Fewer third-party components in the trust chain; portfolio used only the review angle, not ponytail's always-on hooks. | Snyk ToxicSkills (2026-02), GitHub `gh skill` warning on unverified skills |
| D8 | Pin everything: GitHub Actions by full commit SHA (with Dependabot for `github-actions`), Copier / check-jsonschema / Claude Code CLI versions in CI, `@playwright/mcp` by exact version (portfolio used `@latest`), the plugin by tag. | Supply-chain hygiene; SHA pinning is "the only way to use an action as an immutable release". | docs.github.com/en/actions/reference/security/secure-use, OpenSSF Scorecard Pinned-Dependencies |
| D9 | Hooks are tested automatically with fixture JSON and a mutation test that disables each rule in turn. | Portfolio verified 60 cases by hand, and the PO had to run them because auto mode refused hook self-tests from the agent. In this repo the hooks are ordinary code under test. | hooks-guide (pipe sample JSON), portfolio `docs/harness/lessons.md` §2 ("green is not guardian") |
| D10 | Sandbox on by default in the template, `git` and `gh` excluded (commit signing agents and credential helpers live outside), credentials directories in `filesystem.denyRead`, narrow `network.allowedDomains`. `allowUnsandboxedCommands` stays at its default. | Permission rules that constrain Bash arguments are fragile; the sandbox is the OS-level boundary. Strict `allowUnsandboxedCommands: false` would leave the agent unable to proceed on any unlisted domain while it also cannot edit `.claude/settings.json` (auto mode classifier), so the escape goes through the normal permission / classifier path instead. | permissions ("Bash permission patterns that try to constrain command arguments are fragile"), sandboxing |
| D11 | Disable agent teams in the template `env` (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=""`) and dispatch ordinary subagents. | Portfolio measurement (2026-09-20): teammate notifications consumed 56–65 controller turns per session. | portfolio `docs/harness/README.md` §6 |
| D12 | Implementer and reviewer both run on `model: opus`; the controller always passes the model explicitly. | PO instruction (2026-09-17, 2026-09-23). | portfolio `.claude/rules/review.md` |

## 4. Repository layout

```
agentic-harness/
├─ .claude-plugin/marketplace.json       marketplace "agentic-harness", one plugin, allowCrossMarketplaceDependenciesOn: ["claude-plugins-official"]
├─ plugins/harness/
│  ├─ .claude-plugin/plugin.json         name "harness", version, dependencies: superpowers@claude-plugins-official
│  ├─ hooks/hooks.json
│  ├─ scripts/guard.sh                   hard blocks (exit 2)
│  ├─ scripts/ask-gate.sh                permissionDecision "ask"
│  ├─ scripts/lint-on-edit.sh            PostToolUse
│  ├─ scripts/test-on-stop.sh            Stop
│  ├─ agents/implementer.md
│  ├─ agents/reviewer.md
│  └─ skills/{workflow,review-loop,mutation-check,adopt}/SKILL.md
├─ copier.yml                            questions (§6.1), _subdirectory: template
├─ template/                             files rendered into each product repository (§6.2)
├─ tests/hooks/                          cases.tsv + run.sh + mutate.sh
├─ tests/template/run.sh                 render + assertions
├─ .github/workflows/ci.yml              job `check`
├─ .github/dependabot.yml
├─ AGENTS.md, CLAUDE.md                  instructions for maintaining this repository
├─ README.md (canonical), README.ja.md, CHANGELOG.md, LICENSE (MIT)
└─ docs/specs/, docs/plans/
```

## 5. The plugin (`harness@agentic-harness`)

### 5.1 Hooks (`hooks/hooks.json`)

| Event / matcher | Script | Behavior |
|---|---|---|
| PreToolUse `Bash` | `guard.sh`, then `ask-gate.sh` | see below |
| PreToolUse `Read\|Edit\|Write\|MultiEdit\|NotebookEdit` | `guard.sh` | path checks |
| PostToolUse `Edit\|Write\|MultiEdit` | `lint-on-edit.sh` | lint the edited file |
| Stop | `test-on-stop.sh` | run tests before the turn ends |

Commands use the documented form `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh"`. Scripts need `bash`, `jq` and `git`.

**`guard.sh`** blocks unconditionally (exit 2, reason on stderr). Each rule is a block tagged `# rule:<id>` so the mutation test can disable it:

| id | Blocks |
|---|---|
| `rm-rf` | `rm` with both recursive and force flags, in any flag order or long form |
| `force-push` | `git push` with `-f`, `--force`, `--force-with-lease`, `--force-if-includes`, or a `+refspec` |
| `discard` | `git reset --hard\|--merge`, `git clean` with `-f/-d/-x`, `git checkout -- .`, `git restore .`, `git branch -D` |
| `no-verify` | `--no-verify`, `--no-gpg-sign` on git commands |
| `env-file` | `.env` / `.env.*` access through Bash or file tools, except `.env.example` |
| `secrets-dir` | `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.config/op`, `~/.config/gh` through Bash (`~`, `$HOME`, absolute home path) or file tools |
| `pipe-shell` | `curl`/`wget` piped into a shell |

If `jq` is missing, `guard.sh` fails closed (exit 2 with an install hint). Blocking every tool call is loud but safe; a silent pass would not be.

**`ask-gate.sh`** returns `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask",...}}` and otherwise prints nothing (defers to permission rules and auto mode). Rules:

| id | Asks for |
|---|---|
| `protected-push` | `git push` naming a protected branch (`<b>`, `x:<b>`, `refs/heads/<b>`), deleting a remote branch (`--delete`, `-d`, `:ref`), `--all`, `--mirror`; and a refspec-less or `HEAD` push while the current branch (in the hook's `cwd`) is protected |
| `worktree-force` | `git worktree remove` with `-f`/`--force` |
| `lockfile-install` | installs that can change a lockfile: `pnpm install\|i` without `--frozen-lockfile`, `pnpm add`, `npm install\|i` (except `npm ci`), `yarn add` / `yarn install` without `--immutable`/`--frozen-lockfile`, `bun add` / `bun install` without `--frozen-lockfile`, `uv add`, `uv sync` without `--locked`/`--frozen`, `pip install`, `cargo add` |

If `jq` is missing, `ask-gate.sh` asks (fails toward the human). Known limitation, documented: heredoc bodies that contain a matching command trigger a false positive; long Issue/PR bodies go through `--body-file`.

**`lint-on-edit.sh`**: if `HARNESS_LINT_CMD` is unset, exit 0. Otherwise resolve the repository root from the edited file (`git -C "$(dirname "$file")" rev-parse --show-toplevel`, falling back to `CLAUDE_PROJECT_DIR`), compute the repo-relative path, skip it if it matches `HARNESS_DOC_PATTERN`, or if `HARNESS_LINT_PATTERN` is set and the path does not match it. Then run `HARNESS_LINT_CMD "<file>"` from the root; on failure exit 2 with the last 40 lines. The root comes from the file, not `CLAUDE_PROJECT_DIR`, because in a worktree session `CLAUDE_PROJECT_DIR` can point at the main checkout (portfolio lesson).

**`test-on-stop.sh`**: exit 0 when `stop_hook_active` is true, when `HARNESS_TEST_CMD` is unset, or when every uncommitted path matches `HARNESS_DOC_PATTERN`. Otherwise run `HARNESS_TEST_CMD` from the repository root of the hook's `cwd`; on failure print `{"decision":"block","reason":"..."}` with the last 30 lines and an instruction not to skip, delete or weaken tests.

### 5.2 Environment contract

| Variable | Default when unset | Used by |
|---|---|---|
| `HARNESS_LINT_CMD` | (no lint) | lint-on-edit; the file path is appended as the last argument |
| `HARNESS_LINT_PATTERN` | lint every non-doc file | lint-on-edit; extended regex on the repo-relative path |
| `HARNESS_TEST_CMD` | (no test) | test-on-stop |
| `HARNESS_DOC_PATTERN` | `\.(md\|txt)$\|^docs/\|^openspec/\|^\.claude/` | lint-on-edit, test-on-stop |
| `HARNESS_PROTECTED_BRANCHES` | `main` | ask-gate; space-separated |

Commands in `HARNESS_*_CMD` come from the repository's own committed settings, which is already trusted configuration; they are run with `bash -c`. This trust boundary is stated in the README.

### 5.3 Subagents

Both are plugin agents, so they are dispatched as `harness:implementer` and `harness:reviewer`. Plugin agents ignore `hooks`, `mcpServers` and `permissionMode`; neither uses them.

- **implementer** — `model: opus`, `tools: Read, Edit, Write, Bash, Glob, Grep`. Implements exactly one task brief with TDD (RED → GREEN → REFACTOR, never skip/delete/weaken tests), no scope additions (write them as "Proposals"), no new dependencies without asking, uses the commands in `AGENTS.md`, commits in the product's working language with a type prefix, checks the task in `tasks.md` in the same commit, never spawns subagents, never touches secrets. Returns its report as text (portfolio lesson: a report *file* was blocked by tooling) with real command output for RED, GREEN, lint and typecheck. In a fix round it fixes every Critical and Important finding in one pass and maps each to a commit.
- **reviewer** — `model: opus`, `effort: high`, `maxTurns: 80`, `tools: Read, Glob, Grep, Bash` plus the Playwright MCP browser tools (navigate, snapshot, take_screenshot, resize, evaluate, click, press_key, console_messages, network_requests, emulate_media, close). Adversarial: the implementer's report is an unverified claim; only the diff and execution results count. Never modifies the working tree, index, HEAD or branches. Report order: (1) spec compliance — Missing / Extra / Misunderstood with `file:line`, (2) code quality — Critical / Important / Minor with `file:line`, why, and fix, (3) over-engineering — one line per finding `<file>:L<line>: <delete|stdlib|native|yagni|shrink>: <what>. <replacement>.` ending with `net: -N lines possible.` or `Lean already. Ship.`, (4) verdict `Approved | Needs fixes | Re-implementation recommended`. Minor-only and over-engineering-only reports are Approved. Per the Claude Code best-practices caveat, it flags only correctness, security and requirement gaps as Critical/Important. For UI it drives the HTTP URL the controller gives it; when the Playwright tools are absent it states that UI checks were not performed.

### 5.4 Skills

All under 200 lines, English, `description` written for triggering.

- **`harness:workflow`** — the per-change lifecycle (§1), with: the small-change path (docs / `.claude/` / CSS only, or ≤5 files without new spec requirements: skip brainstorming, still create the Issue, one implementer run, one branch-wide review); harness-only edits without a change go through a `fix/<desc>` PR without an Issue; bundle work into as few changes as possible and split only for conflict zones with parallel worktrees (PO instruction 2026-09-21); during implementation, do not stop for judgment calls — rule by the spec and record "ruling / reason / cost if wrong" in the ledger and the Issue; stop only for destructive or irreversible actions, security, side effects outside the worktree (push, publish), or plan defects where every option is a guess; the six Issue milestones (design/proposal approval, implementation start, change of direction, blocker/question, final review result, PR created); definition of done (tests green with command and output, lint passes, `tasks.md` updated, committed; CI result is the final evidence, not local green); update `docs/status.md` after archive; before implementing, check whether `origin/main` moved and merge it (parallel worktrees drift); one implementer per worktree (shared index, build output, ports).
- **`harness:review-loop`** — the controller side: review units (per task only for shared interfaces, spec requirements, multi-file consistency; batch the rest; always one branch-wide review); build the review package (task brief, global constraints, implementer report, diff file with commit list, stat and full diff); for UI, start the preview server and pass the URL, and stop it again before handing work back to an implementer; send all Critical/Important findings in one message; verify "fixed" claims with diff/grep; re-review by `SendMessage` to the same reviewer; mechanical one-line fixes are verified by the controller without re-review; Minor findings go to `tasks.md` "Proposals" and never start a fix round unless the PO asks or a breaking input / spec contradiction is shown; rebuild with a fresh implementer when (1) spec compliance ❌ with ≥1 Critical, (2) two fix rounds without Approved, or (3) the reviewer recommends re-implementation, and record it; one summary comment on the Issue after the final review.
- **`harness:mutation-check`** — proving a test is a guardian: copy the repository outside the working tree (`git archive HEAD | tar -x`, then overlay uncommitted files), install dependencies inside the copy, run the control (unmutated: green), apply the mutation, run again (the targeted check must go red); confirm the run really executed in the copy (e.g. the runner's root line), never infer it from test counts; if the mutated run is still green, rebuild the copy with the mutation applied before install and try once more, then conclude "not a guardian" and fix the test. Includes the portfolio pitfalls in stack-neutral form (a config flag that silently runs the original tree; caches creating false greens).
- **`harness:adopt`** — agent-executable setup for a new repository, ending in a verification report: render the template (`uvx copier copy --vcs-ref <tag> gh:joe-yama/agentic-harness .`), install the plugin (`claude plugin install harness@agentic-harness --scope project`), `openspec init --tools claude`, replace OpenSpec skills with `gh skill install Fission-AI/OpenSpec skills/<name> --agent claude-code --scope project --pin <tag>`, apply the branch ruleset (`gh api` with `docs/harness/ruleset.json`; the PO confirms), prove the guard is active in a new session (`rm -rf <nonexistent path>` is blocked), and record versions and results in `docs/status.md`. Also covers `copier update` and plugin updates.

## 6. The template

### 6.1 Copier questions (`copier.yml`)

| Question | Type / default | Used for |
|---|---|---|
| `project_name` | str, required | AGENTS.md title, README |
| `project_summary` | str, default empty | AGENTS.md overview (filled at the first brainstorming if empty) |
| `github_owner` | str, required | "check `gh api user --jq .login` before gh writes" pitfall, ruleset instructions |
| `default_branch` | str, `main` | `HARNESS_PROTECTED_BRANCHES`, CI triggers, ruleset |
| `work_language` | `ja` \| `en`, `ja` | commits, Issues, PRs, OpenSpec `context`, status docs |
| `lint_cmd` / `lint_pattern` / `test_cmd` | str, empty | `HARNESS_*` env |
| `ui_review` | bool, `false` | `.mcp.json` with pinned `@playwright/mcp`, `enabledMcpjsonServers` |

`_subdirectory: template`, `_answers_file: .copier-answers.yml`. No `_tasks` (so no `--trust` is ever needed).

### 6.2 Rendered files

| Path | Content |
|---|---|
| `AGENTS.md` | overview, roles, stop conditions, definition of done, commands table (from answers, "set in the first change" when empty), pitfalls (default branch is PR-only with required check `check` — renaming the job blocks every merge; confirm the gh login before writes), index of docs |
| `CLAUDE.md` | `@AGENTS.md`, then Claude-specific: which plugin skills to use when, subagent types and explicit `model: opus`, `.claude/settings.json` cannot be written by the agent under auto mode (prepare the file in the scratchpad for the PO), agent definition changes need a new session, long runs use `/goal … or stop after N turns`, compact instructions |
| `.claude/rules/testing.md`, `git.md`, `security.md`, `scope.md` | always-on policies from portfolio, generalized (no pnpm, no Astro, language from answers). Procedures move to skills. Budget: `AGENTS.md` + `CLAUDE.md` + rules ≤ 16,000 bytes, checked in CI |
| `.claude/settings.json` | `$schema`; `env` (`HARNESS_*`, agent teams off); `permissions` (allow: read tools, read-only git, `git add/commit/push`, `gh issue list/view/create/comment`, `gh pr create/view/checks`, `gh run list/view/watch`, `gh api user`, `openspec`; deny: `.env` variants except `.env.example`, credential directories, force push, `git reset --hard`, `git clean`, `sudo`; ask: `rm`, `curl`, `wget`, `gh pr merge`, `gh repo create/delete`, `gh issue close/edit`, `gh release *`, `gh workflow run`); `sandbox` (D10); `extraKnownMarketplaces.agentic-harness` = `{source: github, repo: joe-yama/agentic-harness, ref: <rendered tag>}`; `enabledPlugins` `harness@agentic-harness: true` |
| `.mcp.json` (only if `ui_review`) | `@playwright/mcp@<exact version>` `--headless --isolated --output-dir .playwright-mcp` |
| `.github/workflows/ci.yml` | job `check`, `permissions: contents: read`, `timeout-minutes: 20`, SHA-pinned checkout, context-budget step; a marked place where the first change adds stack steps |
| `.github/dependabot.yml` | `github-actions` weekly |
| `.github/pull_request_template.md` | `Closes #`, test evidence, review verdict |
| `openspec/config.yaml` | `schema: spec-driven`, language context from `work_language` |
| `docs/status.md` | phase, in-progress change, PO to-dos, next candidates (skeleton) |
| `docs/changes.md` | ledger of change history and rulings (skeleton with the ruling format) |
| `docs/harness/lessons.md` | skeleton: "defects that only real data or real processes showed" and "green is not guardian" |
| `docs/harness/ruleset.json` | PR required, required status check `check`, no force push / deletion on the default branch |
| `.gitignore` | `.env*` except `.env.example`, `.claude/settings.local.json`, `.playwright-mcp/`, `.claude/worktrees/` |

## 7. Verification

CI job `check` in this repository (`permissions: contents: read`, timeout 15 min, all actions SHA-pinned):

1. `shellcheck` on all scripts.
2. `tests/hooks/run.sh`: every row of `tests/hooks/cases.tsv` (`script`, `input JSON`, `expected` = `block` | `ask` | `pass`, optional fake branch / env) passes. Portfolio's 60 manual cases are ported and extended to the new rules. `git` is replaced by a shim on `PATH` for branch-dependent cases.
3. `tests/hooks/mutate.sh`: for every `# rule:<id>` block in `guard.sh` and `ask-gate.sh`, a copy with that block disabled must make at least one case fail. A rule no case catches fails CI. The control run (no mutation) must pass first.
4. `tests/template/run.sh` with a pinned `uvx copier`: render (a) defaults, (b) a Node/pnpm answer set, (c) a Python/uv answer set with `ui_review=true`. Assert no leftover `{{`/`{%`, JSON parses, `.claude/settings.json` validates against the SchemaStore Claude Code settings schema fetched at a pinned commit (`uvx check-jsonschema`), the context budget holds, `.mcp.json` exists only with `ui_review`, the marketplace `ref` equals the rendered version. Also render at one commit, commit it, and run `copier update` to a newer commit without conflicts.
5. `claude plugin validate --strict` on the marketplace root and the plugin, with a pinned `@anthropic-ai/claude-code`.

Manual, recorded in the plan's ledger (cannot run in CI without credentials and a model):

- **First task of the plan (unverified premise):** in a rendered sample repository, run `claude -p` once and prove that a plugin hook sees `HARNESS_*` from the project's settings `env`, and that the guard blocks a destructive command. If `env` does not reach plugin hooks, fall back to reading the same keys from `.claude/settings.json` with `jq` inside the scripts; the plan records which path was taken.
- `claude plugin install` of `harness@agentic-harness` from the local marketplace resolves the Superpowers dependency.

## 8. Security

- The README states that plugins run with the user's privileges, that adopters should read the hooks before installing, and that `claude -p` over untrusted repositories should use `--bare`.
- No secrets anywhere; the harness has none to store.
- Workflow permissions read-only; no `pull_request_target`; untrusted input never interpolated into `run:`.
- Third-party components: Superpowers (MIT, pinned by the official marketplace's SHA), OpenSpec (MIT, pinned tag via `gh skill`), Playwright MCP (Apache-2.0, exact version). Each adoption records their versions in `docs/status.md`.

## 9. Mapping from portfolio

| portfolio item | Disposition |
|---|---|
| `CLAUDE.md` roles, workflow, small-change path, done, pitfalls, autonomy, compact instructions | split: facts → template `AGENTS.md`; Claude-specific → template `CLAUDE.md`; procedures → `harness:workflow` |
| `.claude/rules/testing.md`, `scope.md`, `security.md`, `git.md` | template rules, generalized (package manager, `joe-yama`, 1Password signing removed) |
| `.claude/rules/review.md` | principle (separate context, explicit `model: opus`) → template `CLAUDE.md`; procedure → `harness:review-loop` |
| `.claude/agents/implementer.md`, `reviewer.md` | plugin agents, stack-neutral; ponytail replaced by the built-in pass (D7) |
| `block-destructive.sh` | `guard.sh` (+ `~/.config/gh`, `+refspec` force push) |
| `ask-gate.sh` | `ask-gate.sh` (protected branches from env, more package managers) |
| `lint-on-edit.sh`, `test-on-stop.sh` | stack-neutral via `HARNESS_*` |
| `settings.json` permissions/sandbox | template, generalized; sandbox stays on (D10) |
| `.mcp.json` `@latest` | exact version, optional |
| context budget test (vitest) | CI step in the template |
| `docs/harness/README.md` §7 mutation procedure, `lessons.md` | `harness:mutation-check`; lessons skeleton |
| `docs/harness/README.md` measurements (§6) | cited as rationale (D11, review units); not copied |
| `HANDOFF.md` setup steps | `harness:adopt` |
| user-level `permission-gate.sh`, 1Password signing, `skillOverrides` for vendored Superpowers | not distributed (machine-specific, or no longer needed because Superpowers is not vendored) |
| Astro/pnpm/Biome specifics, port 4399, photo pipeline | not distributed |

## 10. Release

1. Build locally in `~/repo/github-personal/joe-yama/agentic-harness`.
2. Adversarial review by a context-free Opus subagent over the whole repository, including conformance to the sources in §3. Fix until Approved.
3. `gh repo create joe-yama/agentic-harness --public` (PO confirms), push, apply the ruleset, CI green on a PR, tag `v0.1.0` and `harness--v0.1.0`.
