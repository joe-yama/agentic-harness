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
| Plugin manifest / marketplace | reads `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`; `ref` and `sha` pins | reads `plugin.json` / `.codex-plugin/plugin.json`, Claude manifests as fallback; `.claude-plugin/marketplace.json` as "legacy-compatible"; `codex plugin marketplace add owner/repo --ref <ref>` **(spike: does our manifest install as is)** → F8 |
| What a plugin carries | agents, skills, commands, hooks, MCP | skills, hooks, MCP; not agents |
| Auto-install from repo settings | `enabledPlugins` / `extraKnownMarketplaces` in `.github/copilot/settings.json` and in `.claude/settings.json` | none; each user adds the marketplace and reviews plugin hooks (trust) |
| Hook format | Claude format when event names are PascalCase (`tool_name`, `tool_input`; tools reported as `Bash`, `Edit`, `Write`) **(spike: `tool_input` field names, exec-form `command`+`args`)** → F3, F4, F7 | Claude-like `hooks.json`; `Edit`/`Write` matchers alias `apply_patch`; plugin hooks get `CLAUDE_PLUGIN_ROOT` **(spike: shell tool name)** → F1, F2, F7 |
| Block (PreToolUse) | exit 2, or `permissionDecision: "deny"` | exit 2, or `hookSpecificOutput.permissionDecision: "deny"` |
| Ask (PreToolUse) | `permissionDecision: "ask"` **(spike: top-level only, or nested `hookSpecificOutput` too)** → F5 | not supported; `.codex/rules/*.rules` `prefix_rule(..., decision="prompt")` asks natively |
| PostToolUse feedback | `additionalContext` only; no block, exit 2 is a warning **(spike: nested or top-level)** → F6 | `decision: "block"` + `reason`, `additionalContext` |
| Edited file in PostToolUse | **(spike: `path` or `file_path`)** → F4 | none: `tool_input.command` holds the whole `apply_patch` text |
| Stop keeps working | `decision: "block"` + `reason`; `stop_hook_active`; at most 8 in a row | `decision: "block"` + `reason` |
| Subagents | plugin `agents/*.md` (Claude format); `model`, `reasoningEffort`, `tools`; dispatched by the `task` tool **(spike: is `model: sonnet` accepted or mapped)** → F10 | `.codex/agents/*.toml`: `name`, `description`, `developer_instructions`, `model`, `model_reasoning_effort`, `sandbox_mode`; no per-tool list |
| Skills | `.github/skills`, `.agents/skills`, `.claude/skills`, plugins; Claude frontmatter | `.agents/skills`, plugins; `name`/`description` frontmatter; invoked as `$name` **(spike: name of a plugin skill, e.g. `$harness:workflow`)** → F8 |
| Commands | `.claude/commands/*.md` as `/name` **(spike: does `opsx/propose.md` become `/opsx:propose`)** → F11 | none (custom prompts are deprecated and user-level) |
| Permissions and sandbox | not settable per repository (CLI flags `--allow-tool` / `--deny-tool`; sandbox is a user setting); `.claude/settings.json` `permissions` are not read | `.codex/config.toml` (`sandbox_mode`, `approval_policy`, network) and `.codex/rules/*.rules`, both only in trusted projects |
| Headless | `copilot -p … --allow-all-tools` / `--no-ask-user` | `codex exec …` |
| OpenSpec | `github-copilot` tool writes `.github/skills/openspec-*` and `.github/prompts/*.prompt.md` (the CLI does not read prompts) | `codex` tool writes `.agents/skills/openspec-*` only |

Known issue: openai/codex#19372 — Codex auto-imports `.claude-plugin/marketplace.json` files it finds, and Claude-only plugins can break its startup. Our plugin must load cleanly in Codex for that reason as well.

### Spike findings (2026-10-04)

Probed with Copilot CLI 1.0.91 and Codex CLI 0.160.0 in scratch repositories, with a capture plugin that logs each hook's stdin and environment. "Session log" means `~/.copilot/session-state/<id>/events.jsonl` or `~/.codex/sessions/…/rollout-*.jsonl`. Payload excerpts drop `session_id`, `transcript_path` and `turn_id`.

| Id | Finding | Evidence |
|---|---|---|
| F1 codex-shell-tool | `tool_name: "Bash"`, command in `tool_input.command`. PostToolUse adds `tool_response` as a string. Plugin hooks get `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `PLUGIN_ROOT`, `PLUGIN_DATA`; project hooks get none of these; neither kind gets `CLAUDE_PROJECT_DIR` (use the payload's `cwd`). | `codex exec 'Run: echo hi …'`: `{"cwd":"…/cdx","hook_event_name":"PreToolUse","model":"gpt-6-luna","permission_mode":"bypassPermissions","tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_use_id":"exec-…"}`; PostToolUse `"tool_response":"hi\n"` |
| F2 codex-patch-tool | `tool_name: "apply_patch"` (hooks see the real name), patch text in `tool_input.command`. A matcher `Edit\|Write` matches it. The model wrote an absolute path after `*** Update File:`, so paths are absolute or relative to `cwd`; parsers accept both. | `{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: /abs/…/cdx/notes.txt\n@@\n-y\n+z\n*** End Patch"}}`; PostToolUse `tool_response` `"Exit code: 0\n…Success. Updated the following files:\nM /abs/…/notes.txt\n"`; plugin PostToolUse hook with matcher `Edit\|Write` fired for it |
| F3 copilot-shell | Claude's shape: `tool_name: "Bash"`, `tool_input: {command, description}`. Hook env: `COPILOT_CLI=1`, `COPILOT_PLUGIN_ROOT`, `COPILOT_PLUGIN_DATA`, `COPILOT_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR`, `PLUGIN_ROOT`. | capture log: `{"tool_name":"Bash","tool_input":{"command":"echo hi; …","description":"…"}}` |
| F4 copilot-file | Copilot's `apply_patch` is reported as `tool_name: "Edit"` with `tool_input` **a JSON string** holding the patch text (no object, no path key); paths in it are relative to `cwd`. `view` is reported as `tool_name: "Read"`, `tool_input: {"path": "<absolute>"}`. PostToolUse adds `tool_result: {result_type, text_result_for_llm}` (not `tool_response`). Stop sends `stop_reason`, `stop_hook_active`. The hook-facing shape of a `create` tool is UNCONFIRMED: on this account `auto` resolves to gpt-6-luna, whose tool set has `apply_patch`, `view`, `bash`, `glob`, `rg` and no `create` or `edit`; a `task` subagent on `claude-haiku-4.5` had none either. In an earlier Copilot 1.0.63 session on claude-haiku-4.5 the internal `create` call carried an object `{path (absolute), file_text}`, but its hooks errored, so the name hooks see was not logged. The `task` tool reaches hooks as `tool_name: "Agent"`. | create probe: `copilot -p 'Using your create tool (not the shell, not a patch), create new.txt containing hello.'` → "I can't create new.txt because no dedicated create tool is available here", session tools list without `create`; `"tool_name":"Agent","tool_input":{"description":…,"agent_type":"general-purpose","model":"claude-haiku-4.5","mode":"sync"}`; `"tool_name":"Edit","tool_input":"*** Begin Patch\n*** Add File: notes.txt\n+x\n*** End Patch\n"`; `"tool_name":"Read","tool_input":{"path":"/abs/notes.txt"}`; `"tool_result":{"result_type":"success","text_result_for_llm":"Added 1 file(s): /abs/notes.txt"}` |
| F5 copilot-deny-nested | Yes: nested `hookSpecificOutput.permissionDecision: "deny"` with exit 0 blocks, and the reason reaches the model. Top-level `permissionDecision: "deny"` also blocks. Nested `"ask"` is honoured; under `-p` it becomes a deny even with `--allow-all-tools`. A PreToolUse hook that errors (exit other than 0/2) denies the tool (fails closed). | `└ Denied by preToolUse hook: cap-deny-nested` (file not created); `└ Denied by preToolUse hook: cap-deny-top`; `└ Denied by preToolUse hook (unable to ask user for confirmation): cap-ask-nested` |
| F6 copilot-context | Nested `hookSpecificOutput.additionalContext`: no (ignored). Top-level `additionalContext`: yes, appended to the tool result. `{"decision":"block","reason":R}` is honoured: the tool (already run) is reported as failed and its output is replaced by `Tool result blocked: R`; `additionalContext` in the same answer is dropped. | block+nested: `└ Tool result blocked: CAPWORD-1`, `CAPWORD-2` 0 times in the session log; nested alone: model saw nothing; top-level alone: tool result `"hi\n…Tool \"bash\" succeeded. Additional guidance from postToolUse hooks:\nCAPWORD-3"` |
| F7 exec-form | Neither CLI runs the exec form `"command":"bash","args":[…]`. Copilot ignores `args` and runs `bash` with the payload on stdin → exit 127 → every matched tool is denied. Codex reports `hook: PreToolUse Failed` and runs the tool anyway (fails open), so the guard is off. The string form `"command":"bash \"${CLAUDE_PLUGIN_ROOT}/scripts/x.sh\""` works in both (`${CLAUDE_PLUGIN_ROOT}` expanded). | Copilot: `Denied by preToolUse hook from "cap@capture" (hook errored)`, `Stderr: bash: line 1: hook_event_name:PreToolUse: command not found`; Codex with the installed harness: `hook: PreToolUse Failed` ×2, then `git push --force origin main` ran; capture plugin in string form: `hook: PreToolUse Completed` |
| F8 codex-manifest | Installs unchanged from a local path; no `.codex-plugin/` needed. Plugin skills are named `harness:<skill>` (invoked `$harness:workflow`). Plugin hooks run only once trusted: in `codex exec` untrusted plugin hooks are skipped silently; `--dangerously-bypass-hook-trust` runs them. | `codex plugin marketplace add <repo>` → `Added marketplace \`agentic-harness\``; `codex plugin add harness@agentic-harness --json` → `"version":"0.4.0-rc.1"`; skills listed: `harness:adopt`, `harness:design`, `harness:execute`, `harness:mutation-check`, `harness:workflow`; without the bypass flag no `hook:` line appeared |
| F9 codex-agents | `name` accepts hyphens and colons (`harness-probe`, `harness:probe2` both spawnable). The main agent calls `collaboration.spawn_agent {task_name, agent_type, message}` (also `model`, `reasoning_effort`, `fork_turns`); a model can be passed per spawn and is checked against the account's list. Follow-up: `followup_task {target: <task_name>, message}`, then `wait_agent {timeout_ms}`. A spawn without `fork_turns` forked the parent's context; `fork_turns` takes `none`, `all` or a number (from the binary's argument strings, not exercised). | session log: `spawn_agent {"task_name":"probe","agent_type":"harness-probe","message":…}`, `followup_task {"target":"probe",…}`; `Unknown model \`gpt-5.4-mini\` for spawn_agent. Available models: gpt-6-luna, gpt-5.6-terra, gpt-5.6-luna, gpt-5.5`; child `session_meta` `forked_from_id` = parent |
| F10 copilot-agents | `model: sonnet` is read as a literal id, not mapped. `copilot --agent cap:probe` warns `specifies model "sonnet" which is not available; using "auto" instead`; dispatch through `task` **fails** (`Model 'sonnet' is not available. Available models: …`). `task(description, prompt, agent_type, name, model, reasoning_effort, context_tier, mode)` takes a model per dispatch, which overrides the frontmatter. Follow-ups: start with `mode: "background"`, then `write_agent {agent_id, message}` and `read_agent {agent_id, wait: true}`; a `sync` agent rejects `write_agent`. Plugin agents are named `<plugin>:<name>`. | `task {"agent_type":"cap:probe","model":"gpt-5.6-luna","name":"probe1","prompt":"say ok","mode":"sync"}` → `ok`; `write_agent` on it → `Agent is not running in background mode`; background agent → `Message delivered`, `read_agent` → `ok2` |
| F11 copilot-opsx | UNCONFIRMED for interactive sessions (needs a TTY). Under `-p`, `/opsx:explore …` is not expanded: the command text is sent as a plain message. Copilot does load `.claude/skills/openspec-*` as skills. Fallback per plan: the skill route (`openspec-propose`, `openspec-archive-change`, `openspec-update-change`, …). | `openspec init --tools claude` (OpenSpec 1.13.1); `copilot -p '/opsx:explore …'`: user.message content is the literal text, the command body occurs 0 times in the session log; the system message lists `<name>openspec-explore</name>` … |
| F12 models | Codex (account list): `gpt-6-luna` (default, "Fast and affordable"), `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`; `model_reasoning_effort` low\|medium\|high\|xhigh\|max (terra adds `ultra`; gpt-5.5 stops at xhigh; the CLI default shows `none`). Chosen: strong and fast both `gpt-6-luna` (the account lists no larger current model), told apart by effort: strong `high`, fast `medium`. Copilot documents `claude-opus-5.5`, `claude-sonnet-5.5`, `claude-fable-5.1`, `gpt-6-sol`, `gpt-6-luna`, … (`copilot help config`); `--reasoning-effort` / `task.reasoning_effort` none\|minimal\|low\|medium\|high\|xhigh\|max. This account accepts only `--model auto`; `task` accepts its own list (claude-haiku-4.5, gpt-6-luna, gpt-5.6-luna, gpt-5-mini, mai-code-1.1-flash, kimi-k3, …). Chosen: strong `claude-opus-5.5`, fast `claude-sonnet-5.5` (documented, not usable on this account). Fallback on this account: `gpt-5.6-luna`, which `task` accepted (F10). | `~/.codex/models_cache.json`; `copilot --help`; `copilot --model claude-opus-5.5 -p …` → `Error: Model "claude-opus-5.5" from --model flag is not available.` (same for every explicit id tried); `task` error text in F10 |
| F13 codex-config | `.codex/config.toml` with `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`, `[sandbox_workspace_write] network_access = false` (plus `model`, `model_reasoning_effort`) loads without error, but only in a project trusted in `~/.codex/config.toml`; trust passed with `-c projects."<dir>".trust_level="trusted"` does not load it. `codex exec` ran with `approval: never` in every run, also in the trusted repository whose config sets `approval_policy = "on-request"` while its `model` and `sandbox_mode` did apply. `codex execpolicy check --rules <file> <cmd…>` prints JSON and exits 0 either way; `-r` repeats, `--pretty` indents. Rule precedence between overlapping rules was not probed. | header in the trusted repo: `model: gpt-5.5`, `sandbox: workspace-write [workdir, /tmp, $TMPDIR]`, `reasoning effort: low`, `approval: never`; `git push origin main` → `{"matchedRules":[{"prefixRuleMatch":{"matchedPrefix":["git","push"],"decision":"prompt"}}],"decision":"prompt"}`; `git status` → `{"matchedRules":[]}` |
| F14 copilot-double-load | Yes: with `CLAUDE.md` = `@AGENTS.md`, the AGENTS text is in Copilot's context twice. | session system message holds the marker twice: in `<custom_instruction>` from `AGENTS.md` and in `<imported_custom_instruction source=".../AGENTS.md">` under `CLAUDE.md` |
| F15 versions | Copilot CLI 1.0.91, Codex CLI 0.160.0 (OpenSpec 1.13.1). | `copilot --version` → `GitHub Copilot CLI 1.0.91.`; `codex --version` → `codex-cli 0.160.0` |

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
| `.codex/config.toml` | `codex` | `sandbox_mode = "workspace-write"`, `approval_policy = "on-request"`, network limited to the hosts in `.claude/settings.json` sandbox where Codex supports a host list (otherwise network off and the gap documented) |
| `.codex/rules/harness.rules` | `codex` | `prompt` for what ask-gate asks (pushes, remote branch deletion, `--all`/`--mirror`/`--prune`, lockfile-changing installs, `gh pr merge`, `gh release`, …); `forbidden` for the `deny` list of `.claude/settings.json` (`git push --force`, `git reset --hard`, `git clean`, `sudo`, …) |
| `.codex/agents/implementer.toml`, `reviewer.toml` | `codex` | generated (M5); `model` and `model_reasoning_effort` from `docs/harness/models.md`'s Codex column; reviewer `sandbox_mode = "read-only"` |
| `docs/harness/models.md` | always | the role table gains one model/effort column per selected agent; Codex and Copilot model names are chosen in the spike from what each CLI lists |
| `.github/workflows/ci.yml` | always | the OpenSpec step allows `.agents/skills/openspec-{propose,archive,update}` (plus `sync` if OpenSpec generates it) when `codex` is selected, and keeps refusing every other `openspec-*` skill and `opsx` command |
| `.gitignore` | always | unchanged unless the spike finds per-user files (for example `.codex/*.local.*`) |

`HARNESS_*` reach Claude Code hooks through `.claude/settings.json` `env`, as today. Codex and Copilot CLI have no per-repository environment for hooks, so when `codex` or `copilot` is selected the template also renders **`.harness/env.json`** (committed; `.gitignore` changes from `.harness/` to `.harness/*` plus `!.harness/env.json` in that case only) with `HARNESS_LINT_CMD`, `HARNESS_LINT_PATTERN`, `HARNESS_TEST_CMD`, `HARNESS_DOC_PATTERN` and `HARNESS_PROTECTED_BRANCHES`. A hook takes a variable from that file only when it is unset in its environment (set-but-empty counts as set), so a Claude Code session keeps reading `.claude/settings.json`. The two guard relaxations (`HARNESS_ALLOW_LEASE_PUSH`, `HARNESS_RM_RF_ALLOW`) are never read from the file: an agent can write repository files, and a relaxation must not be one write away. For the same reason `guard` refuses file-tool access, patches and shell commands that name `.harness/env.json` (new rule `harness-env`); the PO edits it, as with `.claude/settings.json`.

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
