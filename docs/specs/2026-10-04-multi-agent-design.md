# Multi-agent support (Codex, Copilot CLI) — design

- Date: 2026-10-04
- Status: approved in conversation by the PO (2026-10-04); this document awaits written-spec review
- Target release: 0.5.0 (0.4.0 stays a release of the Superpowers removal only)

## 1. Goal

An adopting repository can be worked by **Claude Code, OpenAI Codex (CLI) or GitHub Copilot CLI**:

1. **Single agent.** The PO picks any one of the three; the workflow (design → OpenSpec change + Issue → `harness:execute` → PR → archive), the guard hooks, the subagents and the skills work in it.
2. **Mixed by stage.** Each stage already runs in a new session and hands over only through committed files and the ledger (`.harness/<change>/progress.md`). Any stage may be opened in any of the three agents, for example design in Claude Code and `harness:execute` in Codex.

Success criteria:

1. A repository rendered with `agents: [codex]` or `agents: [copilot]` reaches "harness ready" through `harness:adopt`, and the adopt verification shows `guard` blocking a destructive command in that agent.
2. Every hook rule is covered by a test for each input dialect it accepts (`tests/hooks/cases.tsv`, `tests/hooks/lifecycle.sh`); `tests/hooks/mutate.sh` stays green.
3. `agents` defaults to `[claude]`, and a repository rendered with the default is byte-identical to a 0.4.0 render except for the marketplace `ref` and the `agents` entry in `.copier-answers.yml` (with only `claude` selected, `AGENTS.md`, `docs/harness/models.md` and `ci.yml` render as in 0.4.0).
4. Known gaps per agent are listed in the README (English and Japanese).

## 2. Non-goals

- **Cross-agent dispatch inside a stage** (for example a Claude Code controller running `codex exec` as the reviewer). Considered and declined by the PO for now.
- Copilot **cloud agent** (Issue-assigned), VS Code agent mode, Codex cloud and the Codex IDE extension. They may work partly as a side effect; nothing is designed or tested for them.
- Parity of enforcement. Where an agent lacks a mechanism, the harness does what that agent allows and documents the gap; CI job `check` and the branch ruleset stay the last line (PO decision, "best effort and documented").
- Running real agents in CI (each needs an authenticated account).

## 3. Facts this design rests on

Gathered from official documentation on 2026-10-04 (Codex: learn.chatgpt.com/docs, developers.openai.com/codex/plugins/build; Copilot: docs.github.com/en/copilot/reference: hooks-reference, cli-command-reference, cli-plugin-reference, cli-config-dir-reference; OpenSpec: docs/supported-tools.md). Items marked **(spike)** are not confirmed and are settled by task 1 (§8).

| Topic | Copilot CLI | Codex CLI |
|---|---|---|
| Instructions | `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.github/instructions/`, `.claude/rules/` (all merged) | `AGENTS.md` (and `AGENTS.override.md`) from the git root down; not `CLAUDE.md` |
| Plugin manifest / marketplace | reads `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`; `ref` and `sha` pins | reads `plugin.json` / `.codex-plugin/plugin.json`, Claude manifests as fallback; `.claude-plugin/marketplace.json` as "legacy-compatible"; `codex plugin marketplace add owner/repo --ref <ref>` **(spike: does our manifest install as is)** |
| What a plugin carries | agents, skills, commands, hooks, MCP | skills, hooks, MCP; not agents |
| Auto-install from repo settings | `enabledPlugins` / `extraKnownMarketplaces` in `.github/copilot/settings.json` and in `.claude/settings.json` | none; each user adds the marketplace and reviews plugin hooks (trust) |
| Hook format | Claude format when event names are PascalCase (`tool_name`, `tool_input`; tools reported as `Bash`, `Edit`, `Write`) **(spike: `tool_input` field names, exec-form `command`+`args`)** | Claude-like `hooks.json`; `Edit`/`Write` matchers alias `apply_patch`; plugin hooks get `CLAUDE_PLUGIN_ROOT` **(spike: shell tool name)** |
| Block (PreToolUse) | exit 2, or `permissionDecision: "deny"` | exit 2, or `hookSpecificOutput.permissionDecision: "deny"` |
| Ask (PreToolUse) | `permissionDecision: "ask"` **(spike: top-level only, or nested `hookSpecificOutput` too)** | not supported; `.codex/rules/*.rules` `prefix_rule(..., decision="prompt")` asks natively |
| PostToolUse feedback | `additionalContext` only; no block, exit 2 is a warning **(spike: nested or top-level)** | `decision: "block"` + `reason`, `additionalContext` |
| Edited file in PostToolUse | **(spike: `path` or `file_path`)** | none: `tool_input.command` holds the whole `apply_patch` text |
| Stop keeps working | `decision: "block"` + `reason`; `stop_hook_active`; at most 8 in a row | `decision: "block"` + `reason` |
| Subagents | plugin `agents/*.md` (Claude format); `model`, `reasoningEffort`, `tools`; dispatched by the `task` tool **(spike: is `model: sonnet` accepted or mapped)** | `.codex/agents/*.toml`: `name`, `description`, `developer_instructions`, `model`, `model_reasoning_effort`, `sandbox_mode`; no per-tool list |
| Skills | `.github/skills`, `.agents/skills`, `.claude/skills`, plugins; Claude frontmatter | `.agents/skills`, plugins; `name`/`description` frontmatter; invoked as `$name` **(spike: name of a plugin skill, e.g. `$harness:workflow`)** |
| Commands | `.claude/commands/*.md` as `/name` **(spike: does `opsx/propose.md` become `/opsx:propose`)** | none (custom prompts are deprecated and user-level) |
| Permissions and sandbox | not settable per repository (CLI flags `--allow-tool` / `--deny-tool`; sandbox is a user setting); `.claude/settings.json` `permissions` are not read | `.codex/config.toml` (`sandbox_mode`, `approval_policy`, network) and `.codex/rules/*.rules`, both only in trusted projects |
| Headless | `copilot -p … --allow-all-tools` / `--no-ask-user` | `codex exec …` |
| OpenSpec | `github-copilot` tool writes `.github/skills/openspec-*` and `.github/prompts/*.prompt.md` (the CLI does not read prompts) | `codex` tool writes `.agents/skills/openspec-*` only |

Known issue: openai/codex#19372 — Codex auto-imports `.claude-plugin/marketplace.json` files it finds, and Claude-only plugins can break its startup. Our plugin must load cleanly in Codex for that reason as well.

## 4. Decisions

| # | Decision | Rationale |
|---|---|---|
| M1 | **One plugin, one manifest.** `plugins/harness/` stays the only plugin source and `plugins/harness/.claude-plugin/plugin.json` the only manifest and version. No `.codex-plugin/` or `.github/plugin/` copies unless the spike shows Codex needs one; then it is generated and a test asserts it matches. | Keeps one version line (D2 of the 0.1.0 design) and one place for guard logic and its mutation test. PO chose this over per-agent generated plugins and over vendoring. |
| M2 | **Hooks accept every dialect; they branch on payload shape, not on a guess of which agent runs them.** Where an output form is understood by all three, use it; branch only where it is not. | A wrong agent guess must never make `guard` pass a command. Exit 2 blocks in all three, so `guard` needs no agent detection at all. |
| M3 | **Copier question `agents`** (multi-select: `claude`, `codex`, `copilot`; default `[claude]`). Only the selected agents' files are rendered; `copier update` can add an agent later. | PO decision. Avoids dead config and update conflicts. |
| M4 | **Agent specifics live in each agent's own instruction file**: Claude in `CLAUDE.md`, Copilot in `.github/copilot-instructions.md`, Codex in a "Codex specifics" section of `AGENTS.md` rendered only when `codex` is selected (Codex reads nothing else). `AGENTS.md` stays tool-neutral otherwise. | Each agent reads only what concerns it; the shared rules are written once. |
| M5 | **Plugin agents are the source of the Codex agents.** `scripts/gen-codex-agents.sh` (repository root, not shipped) renders `template/.codex/agents/{implementer,reviewer}.toml.jinja` from `plugins/harness/agents/*.md`; a test fails when the committed files differ from a fresh render. | Codex plugins cannot carry agents. One source avoids drift. |
| M6 | **Skills and agents are written agent-neutrally**, with a short per-agent table where the mechanics differ (dispatching a subagent with a model, calling OpenSpec, headless runs). Claude-only material (`/goal`, scratchpad, `claude -p` flags) moves to `CLAUDE.md`. | Every agent loads the same skill text. |
| M7 | **Mixed stages need no new mechanism.** `harness:workflow` states that any stage may run in any selected agent, and the PR evidence names the agent and model of each stage. | The stage hand-off is already file-based. |
| M8 | **Release 0.5.0**, after 0.4.0 final. Backward compatible for Claude-only repositories (default `agents: [claude]`). | Keeps the 0.4.0 breaking change and this feature apart. |

## 5. Plugin: hooks

`plugins/harness/hooks/hooks.json` stays one file. Matchers keep their Claude names; Copilot reports its tools under those names and Codex aliases `Edit`/`Write` to `apply_patch`. If the spike shows Codex's shell tool is not matched by `Bash`, its name is added to the matcher.

### 5.1 Input dialects

`lib/parse.sh` gains one function, `hook_input`, used by all four scripts. From the hook input it sets:

- `kind`: `shell` (a command string in `tool_input.command`), `patch` (`tool_name` is `apply_patch`), `file` (a file tool with a path), or `other`;
- `cmd` for `shell`;
- `paths` (newline-separated) for `patch` and `file`. For a patch: every path after `*** Add File: `, `*** Update File: `, `*** Delete File: ` and `*** Move to: `. For a file tool: `tool_input.file_path // tool_input.path // tool_response.filePath` (final field list per the spike).

Malformed input keeps today's behavior: `guard` blocks and `ask-gate` asks with `bad-input`. A patch with no file header is `bad-input` for `guard` (it cannot tell what is written).

### 5.2 Per hook

| Hook | Claude Code | Copilot CLI | Codex |
|---|---|---|---|
| `guard` | unchanged: exit 2, reason on stderr | same | `shell`: unchanged. `patch`: the patch text is **not** parsed as shell; each path goes through `check_path` (`.env`, credential directories) |
| `ask-gate` | unchanged: nested `hookSpecificOutput.permissionDecision: "ask"` | `ask` in the form the spike confirms (if both forms are accepted by both agents, emit both) | Codex ignores `ask`. The template's `.codex/rules/harness.rules` asks natively (§6.2). ask-gate itself emits nothing Codex would read as allow |
| `lint-on-edit` | unchanged: exit 2, reason on stderr | JSON with `additionalContext` (the lint output), exit 0 | `{"decision":"block","reason":…}` per failing file; every path of the patch is linted |
| `test-on-stop` | unchanged: `{"decision":"block","reason":…}` | same; `stop_hook_active` already ends the loop | same |

The output form of `lint-on-edit` depends on the agent, since exit 2 blocks in Claude Code but only warns in Copilot. The script picks it by payload shape: `patch` input means Codex; for `file` input, the agent is identified by a signal the spike confirms (for example a Copilot-only payload field or environment variable such as `COPILOT_PLUGIN_DATA`). With no signal, the Claude form is used. The worst case of a wrong pick is lint feedback that is shown as a warning instead of forcing a fix, never a skipped guard.

### 5.3 Tests

- `tests/hooks/run.sh`: new payload types `patch:<path>[,<path>...]` (an `apply_patch` envelope with those headers), `patchraw:<printf %b text>`, and `copilot-file:<Tool>:<path>` / `copilot-bash:<command>` in the Copilot shape the spike records.
- `tests/hooks/cases.tsv`: for every `guard` path rule, a `patch:` case; a `patch:` case whose body contains `rm -rf /` and `git push --force` and passes (body is data); `bad-input` for a header-less patch; Copilot-shape cases for at least one block, one ask and one pass rule.
- `tests/hooks/lifecycle.sh`: `lint-on-edit` with a multi-file patch (one failing file → one block naming it), with Copilot input (`additionalContext`, exit 0), with Claude input (unchanged); `test-on-stop` with Copilot input.
- `tests/hooks/mutate.sh`, `timing.sh`: unchanged; they now also cover the new rules (`# rule:patch-paths`, `# rule:lint-dialect`, …).
- Bash 3.2 compatibility as before.

## 6. Template

### 6.1 Copier

```yaml
agents:
  type: str
  multiselect: true
  default: [claude]
  choices:
    Claude Code: claude
    OpenAI Codex CLI: codex
    GitHub Copilot CLI: copilot
  help: Coding agents this repository is worked with (each gets its own settings)
  validator: "{% if not agents %}Pick at least one{% endif %}"
```

### 6.2 Files

| File | Rendered when | Content |
|---|---|---|
| `AGENTS.md` | always | as today, plus a "Codex specifics" section when `codex` is selected (skills `$harness:…`, subagent dispatch, OpenSpec skill names, `codex exec`, trust step). The line "Claude Code specifics are in `CLAUDE.md`" names each selected agent's file |
| `CLAUDE.md`, `.claude/settings.json` | `claude` | as today |
| `.claude/rules/` | `claude` or `copilot` | as today (Copilot reads `.claude/rules/`) |
| `.github/copilot-instructions.md` | `copilot` | Copilot specifics: dispatch with `task` / `--agent`, how OpenSpec is called, headless `copilot -p`, that `.claude/settings.json` permissions do not apply, compact instructions |
| `.github/copilot/settings.json` | `copilot` | `enabledPlugins` (`harness@agentic-harness: true`) and `extraKnownMarketplaces` pinned to the same ref as `.claude/settings.json` |
| `.codex/config.toml` | `codex` | `sandbox_mode = "workspace-write"`, `approval_policy = "on-request"`, network limited to the hosts in `.claude/settings.json` sandbox where Codex supports a host list (otherwise network off and the gap documented), `HARNESS_*` for hooks through `shell_environment_policy` (spike: hooks see these variables) |
| `.codex/rules/harness.rules` | `codex` | `prompt` for what ask-gate asks (pushes, remote branch deletion, `--all`/`--mirror`/`--prune`, lockfile-changing installs, `gh pr merge`, `gh release`, …); `forbidden` for the `deny` list of `.claude/settings.json` (`git push --force`, `git reset --hard`, `git clean`, `sudo`, …) |
| `.codex/agents/implementer.toml`, `reviewer.toml` | `codex` | generated (M5); `model` and `model_reasoning_effort` from `docs/harness/models.md`'s Codex column; reviewer `sandbox_mode = "read-only"` |
| `docs/harness/models.md` | always | the role table gains one model/effort column per selected agent; Codex and Copilot model names are chosen in the spike from what each CLI lists |
| `.github/workflows/ci.yml` | always | the OpenSpec step allows `.agents/skills/openspec-{propose,archive,update}` (plus `sync` if OpenSpec generates it) when `codex` is selected, and keeps refusing every other `openspec-*` skill and `opsx` command |
| `.gitignore` | always | unchanged unless the spike finds per-user files (for example `.codex/*.local.*`) |

`HARNESS_*` reach Claude Code hooks through `.claude/settings.json` `env`. For Copilot (no repository `env`), the hooks fall back to reading `HARNESS_*` from `.claude/settings.json` `env` or `.github/copilot/settings.json` when the variable is unset in the environment — whichever the spike shows is available; the template renders the values there. Codex as in the table above.

### 6.3 OpenSpec per agent

| Agent | Propose / archive / update | Setup in `harness:adopt` |
|---|---|---|
| Claude Code | `/opsx:propose`, `/opsx:archive`, `/opsx:update` | as today |
| Copilot CLI | `/opsx:propose` … if the spike shows `.claude/commands/opsx/*` work; otherwise the skills `openspec-propose` … under `.agents/skills` (shared with Codex) | `openspec init --tools claude` (commands) or the skill route |
| Codex | `$openspec-propose`, `$openspec-archive`, `$openspec-update` | `openspec init --tools codex`, then delete every generated skill except those three (and `sync` if archive needs it) |

## 7. Skills and agents

- `harness:execute`: "Dispatch" becomes agent-neutral ("start `harness:implementer` / `harness:reviewer` with the model in your agent's column of `docs/harness/models.md`") plus a table: Claude Code `Agent(subagent_type: "harness:reviewer", model: …)`; Codex: spawn the `reviewer` agent defined in `.codex/agents/`; Copilot CLI: the `task` tool with agent `harness:reviewer` (names per spike). Model overrides that an agent cannot pass per dispatch (Codex, possibly Copilot) come from the agent definition; the intermediate-review model then needs its own definition (`reviewer-light`) or the table records the limitation — decided in the spike.
- `harness:workflow`, `harness:design`: OpenSpec calls written as "OpenSpec propose (see your agent's instructions)" with the table of §6.3 in the skill; the headless section lists `claude -p`, `codex exec` and `copilot -p`; `/goal` and Claude flags move to `CLAUDE.md`. New paragraph "Mixed agents" (M7).
- `harness:adopt`: per-agent steps for install and pin (Claude as today; Copilot `copilot plugin marketplace add` + `copilot plugin install`, or auto-install from settings; Codex `codex plugin marketplace add joe-yama/agentic-harness --ref vX.Y.Z`, plugin install, hook trust review, project trust), OpenSpec per §6.3, and a verification per selected agent (a blocked `rm -rf`, the skills listed, the agents listed). `docs/status.md` "Harness versions" records each selected agent's version.
- `harness:implementer`, `harness:reviewer`: "Claude Code builds it" → "a coding agent builds it"; `tools:` stays (Copilot maps it; Codex uses the TOML's `sandbox_mode`).
- `harness:mutation-check`: no agent-specific text expected; checked.
- A test (extending `tests/lint.sh` or `tests/manifest.sh`) fails when a skill or agent body names a Claude-only mechanism outside a per-agent table (`subagent_type`, `/goal`, `claude -p`, scratchpad).

## 8. Order of work

1. **Spike** (throwaway code, findings committed into §3 of this spec): with Copilot CLI 1.0.63 (installed) and Codex CLI (to be installed by the PO), capture real hook payloads for shell, edit/patch and stop; confirm the ask and PostToolUse output forms; install the plugin from a local marketplace in each; check skill and agent names, model names, `.claude/commands` in Copilot, env-var delivery to hooks, and network keys in `.codex/config.toml`. Every **(spike)** mark is resolved or turned into a documented gap.
2. Hook dialects (§5) test-first.
3. Codex agent generator and its test (M5).
4. Template and Copier question (§6) with `tests/template/run.sh` cases for `[claude]`, `[codex]`, `[copilot]` and all three, including the byte-identity check of criterion 3.
5. Skills and agents text (§7) and its lint test.
6. README / README.ja, CHANGELOG 0.5.0, `harness:adopt`; manual smoke in each agent per the adopt verification.

## 9. Risks

| Risk | Mitigation |
|---|---|
| A spike finding contradicts the docs (for example Copilot drops nested hook output) | §5.2 already prefers forms all agents read; the spike runs before any implementation and updates this spec |
| Codex ignores ask, so ask-gate items run without the PO in Codex | `.codex/rules` `prompt` rules; ruleset blocks direct pushes to the default branch; documented gap |
| Copilot has no repository-level permissions or sandbox | `guard` is the only in-agent barrier; documented; the PO can add `--deny-tool` flags or a user-level sandbox |
| `copier update` to 0.5.0 conflicts in an adopted repository | default `[claude]` renders the same files; CHANGELOG notes |
| Copilot CLI loads both `CLAUDE.md` (`@AGENTS.md`) and `AGENTS.md`, so the shared rules may appear twice in its context | spike measures it; if they do appear twice and `claude` and `copilot` are both selected, `.github/copilot-instructions.md` says so, or Copilot's `CLAUDE.md` loading is turned off if a repository setting exists |
| Agent CLIs change fast | versions verified in the spike are recorded in the README and in `docs/status.md`; the adopt verification is re-run on update |
