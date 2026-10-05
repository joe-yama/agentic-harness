# Multi-agent support (Codex, Copilot CLI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An adopting repository can be worked by Claude Code, OpenAI Codex CLI or GitHub Copilot CLI, alone or mixed by stage, with the same workflow, guard hooks, subagents and skills.

**Architecture:** One plugin (`plugins/harness/`) whose hooks accept every agent's input dialect and answer in forms all three read; one Copier question `agents` that renders only the selected agents' files (`.claude/`, `.codex/`, `.github/copilot/`); skills written agent-neutrally with per-agent tables.

**Tech Stack:** bash 3.2+, jq, git, sed -E, awk (mawk and BWK), Copier 9.18.2, shellcheck-py 0.11.0.1, check-jsonschema 0.38.2, OpenSpec CLI 1.13.1, Copilot CLI 1.0.63, Codex CLI (version recorded by Task 1).

**Spec:** `docs/specs/2026-10-04-multi-agent-design.md`

**Ledger:** `docs/plans/2026-10-04-multi-agent-ledger.md` (create in Task 1; one entry per task: BASE SHA, commit range, review verdict, rulings, deviations from this plan). Branch `feature/multi-agent`.

## Global Constraints

- `AGENTS.md` rules apply: before every commit `bash tests/lint.sh`, `bash tests/hooks/run.sh`, `bash tests/hooks/lifecycle.sh`, plus `bash tests/template/run.sh` when `template/` or `copier.yml` changed; `bash tests/all.sh` before review and before the PR. Never pipe a test script into `tail` in a chained command.
- Test-first: add the failing case, run it and see it fail for the expected reason, then change the script.
- Every hook rule sits between `# rule:<id>` and `# end:<id>` and needs a case in `tests/hooks/cases.tsv` or `tests/hooks/lifecycle.sh`; `tests/hooks/mutate.sh` must stay green.
- Hooks: bash + jq + git only; macOS `/bin/bash` 3.2 (`HOOK_BASH=/bin/bash bash tests/hooks/run.sh` and `lifecycle.sh`); `sed -E` (BSD and GNU), awk portable to mawk and BWK awk; no `\|` in BRE.
- One plugin manifest: `plugins/harness/.claude-plugin/plugin.json` is the only place for the version (M1). Do not bump the version or tag: add entries under `## [Unreleased]` in `CHANGELOG.md`. Release 0.5.0 happens after 0.4.0 final, outside this plan.
- Default `agents: [claude]` renders byte-identically to a 0.4.0-rc.1 render except the marketplace `ref` and the `agents` line of `.copier-answers.yml` (spec §1 criterion 3).
- `guard` never depends on guessing the agent (M2). Exit 2 with `BLOCKED by harness guard (<id>): …` on stderr stays its only block form.
- `HARNESS_ALLOW_LEASE_PUSH` and `HARNESS_RM_RF_ALLOW` are read from the environment only, never from `.harness/env.json`.
- English is canonical; `README.ja.md` is updated in the same commit as `README.md`.
- Commit prefixes `feat:` `fix:` `test:` `docs:` `chore:` `ci:`; end every commit message with the attribution lines the session gives.
- Pinned versions (Copier 9.18.2, check-jsonschema 0.38.2, shellcheck-py 0.11.0.1, SchemaStore commit, Actions SHAs) stay unchanged.
- No placeholder values in shipped files. Values the spike decides (model ids, tool names, field names) are read from spec §3 "Spike findings" (written by Task 1); a task that needs one names the finding it uses.

## Review Focus

1. **A Codex patch whose body mentions dangerous commands** (`rm -rf /`, `git push --force`) must pass `guard` — the body is file content — while a patch that writes `.env`, a credential directory or `.harness/env.json` anywhere in a multi-file patch is blocked. Pinned by Task 2 cases `g-patch-03`, `g-patch-04`.
2. **A patch that renames a file onto `.env`** (`*** Move to: .env`) must be blocked even though the `Update File` header names a harmless path. Pinned by Task 2 case `g-patch-05`.
3. **An agent rewriting `.harness/env.json`** (file tool, patch, `sed -i`, `echo >`) to drop `HARNESS_PROTECTED_BRANCHES` must be refused, and a relaxation variable written into that file must have no effect. Pinned by Task 2 `g-henv-*` and Task 4 `e-relax-ignored`.
4. **Claude Code behavior must not regress** when lint feedback moves from exit 2 to JSON `decision: block`: the reason still reaches Claude and the turn does not end with a failing file. Pinned by Task 3 `l-bad` (JSON shape) and the manual Claude check in Task 12.
5. **`agents` without `claude`** must not render a broken CI job (the context-budget step reads `CLAUDE.md` today). Pinned by Task 7/10 template checks `codex-ci-budget` and `copilot-ci-budget`.

---

### Task 1: Spike — confirm the unconfirmed facts in real CLIs

Throwaway code lives only in the scratchpad. The deliverable is a committed "Spike findings" section appended to spec §3 and the ledger file.

**Files:**
- Modify: `docs/specs/2026-10-04-multi-agent-design.md` (append `### Spike findings` at the end of §3)
- Create: `docs/plans/2026-10-04-multi-agent-ledger.md`

**Interfaces:**
- Produces (spec §3 "Spike findings", one row each; later tasks read these names exactly):
  - `F1 codex-shell-tool`: `tool_name` Codex sends for its shell tool, and the `tool_input` key holding the command.
  - `F2 codex-patch-tool`: `tool_name` and `tool_input` key for `apply_patch`; whether paths are relative to `cwd`.
  - `F3 copilot-shell`: `tool_name` / `tool_input` keys Copilot CLI sends to a Claude-format plugin hook for shell.
  - `F4 copilot-file`: `tool_name` / `tool_input` path key for Copilot's create, edit, view tools; and what its `apply_patch` (reported as `Edit`) sends.
  - `F5 copilot-deny-nested`: does Copilot honor `{"hookSpecificOutput":{"permissionDecision":"deny"}}` with exit 0 (yes/no); same for top-level `permissionDecision`.
  - `F6 copilot-context`: does PostToolUse `hookSpecificOutput.additionalContext` reach the model (yes/no); top-level `additionalContext`; does `{"decision":"block","reason":…}` break anything.
  - `F7 exec-form`: do Codex and Copilot run `"command":"bash","args":["${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"]`.
  - `F8 codex-manifest`: does `codex plugin marketplace add <local path>` + install accept `.claude-plugin/marketplace.json` and `plugins/harness/.claude-plugin/plugin.json` unchanged; skills listed as which names (`$harness:workflow`?).
  - `F9 codex-agents`: valid `name` charset in `.codex/agents/*.toml`; how the main agent starts one (tool name); can it pass a model per dispatch; how it sends a follow-up to a running subagent.
  - `F10 copilot-agents`: does `model: sonnet` / `opus` in plugin agent frontmatter load (mapped, ignored, or error); can the `task` tool pass a model per dispatch; how it resumes a subagent.
  - `F11 copilot-opsx`: does `.claude/commands/opsx/propose.md` appear in Copilot CLI as `/opsx:propose` (or another name).
  - `F12 models`: model ids each CLI lists; chosen ids for "strong" (decision, final review) and "fast" (implementation, intermediate review) per agent; effort/reasoning values accepted.
  - `F13 codex-config`: accepted keys in `.codex/config.toml` for sandbox and network (`[sandbox_workspace_write] network_access`), and `codex execpolicy check` usage for `.codex/rules/*.rules`.
  - `F14 copilot-double-load`: with `CLAUDE.md` = `@AGENTS.md` + `AGENTS.md`, does Copilot put the AGENTS text in context twice (check `/context` or the session log).
  - `F15 versions`: exact versions of Codex CLI and Copilot CLI used.

- [ ] **Step 1: Create the ledger**

```markdown
# Multi-agent support — ledger

Plan: `docs/plans/2026-10-04-multi-agent.md`. Spec: `docs/specs/2026-10-04-multi-agent-design.md`. Branch `feature/multi-agent`.

## Tasks

| Task | BASE | Range | Review | Notes |
|---|---|---|---|---|

## Rulings

## Proposals
```

- [ ] **Step 2: Ask the PO to install and log in to Codex CLI**

Codex is not installed on this machine. Ask the PO to run `! npm install -g @openai/codex` (or `brew install codex`) and `! codex login`. Record `codex --version` and `copilot --version` (F15). Do not continue with Codex probes until this is done; Copilot probes can run meanwhile.

- [ ] **Step 3: Build a capture plugin in the scratchpad**

```sh
S=$SCRATCH/capture   # $SCRATCH = the session scratchpad directory
mkdir -p "$S/.claude-plugin" "$S/plugins/cap/.claude-plugin" "$S/plugins/cap/hooks" "$S/plugins/cap/scripts"
cat > "$S/.claude-plugin/marketplace.json" <<'EOF'
{"name":"capture","owner":{"name":"x"},"plugins":[{"name":"cap","source":"./plugins/cap","description":"capture"}]}
EOF
cat > "$S/plugins/cap/.claude-plugin/plugin.json" <<'EOF'
{"name":"cap","version":"0.0.1","description":"capture hook payloads"}
EOF
cat > "$S/plugins/cap/scripts/cap.sh" <<'EOF'
#!/usr/bin/env bash
# Appends the hook input and the agent-identifying environment to $CAP_LOG, then prints $CAP_OUT if set.
{ printf '=== %s\n' "$(date +%s)"; cat; printf '\n'; env | grep -E '^(CLAUDE|COPILOT|CODEX|PLUGIN)_' | sort; } >> "${CAP_LOG:-/tmp/cap.log}"
[ -n "${CAP_OUT:-}" ] && printf '%s' "$CAP_OUT"
exit 0
EOF
cat > "$S/plugins/cap/hooks/hooks.json" <<'EOF'
{"hooks":{
 "PreToolUse":[{"matcher":".*","hooks":[{"type":"command","command":"bash","args":["${CLAUDE_PLUGIN_ROOT}/scripts/cap.sh"],"timeout":10}]}],
 "PostToolUse":[{"matcher":".*","hooks":[{"type":"command","command":"bash","args":["${CLAUDE_PLUGIN_ROOT}/scripts/cap.sh"],"timeout":10}]}],
 "Stop":[{"hooks":[{"type":"command","command":"bash","args":["${CLAUDE_PLUGIN_ROOT}/scripts/cap.sh"],"timeout":10}]}]}}
EOF
```

- [ ] **Step 4: Copilot probes (F3–F7, F10, F11, F14)**

In a scratch git repo with an `AGENTS.md` and a `CLAUDE.md` containing `@AGENTS.md`, install the capture plugin (`copilot plugin marketplace add "$S"` then `copilot plugin install cap@capture`; if the CLI needs a GitHub-hosted source, use `copilot plugin install "$S/plugins/cap"` and note it), then run with `CAP_LOG` exported:

```sh
copilot -p 'Run the shell command: echo hi. Then create notes.txt containing x. Then change x to y in notes.txt. Then read notes.txt.' --allow-all-tools
```

Read `$CAP_LOG` for F3, F4, F7. Repeat with `CAP_OUT='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"cap-deny-nested"}}'` (F5 nested: the shell command must not run), then with top-level `{"permissionDecision":"deny","permissionDecisionReason":"cap-deny-top"}`. For F6 set `CAP_OUT` (PostToolUse only — temporarily remove PreToolUse from the capture hooks.json) to `{"decision":"block","reason":"CAPWORD-1","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"CAPWORD-2"}}` and ask the model to "repeat any hook feedback you received verbatim"; record which words come back. For F10 add `plugins/cap/agents/probe.md` with frontmatter `name: probe`, `model: sonnet`, and check `copilot --agent cap:probe -p 'say ok'` (or the name the CLI lists). For F11 run `openspec init --tools claude` in the scratch repo and check whether `/opsx:propose` is listed in an interactive session (PO assists if interactive input is needed). For F14 inspect `/context` (or the session log) for the AGENTS text appearing twice.

- [ ] **Step 5: Codex probes (F1, F2, F7–F9, F12, F13)**

In a scratch git repo: `codex plugin marketplace add "$S"`, install `cap`, review/trust its hooks, then:

```sh
CAP_LOG=$SCRATCH/codex.log codex exec 'Run: echo hi. Then create notes.txt containing x, then change x to y with a patch.'
```

Record F1, F2, F7 from the log. F8: add this repository as a local marketplace (`codex plugin marketplace add "$PWD"` from the repo root) and install `harness`; record errors and the skill names listed (`/skills` or `codex exec 'list your skills'`). F9: put `.codex/agents/probe.toml` (`name = "harness-probe"`, `description = "probe"`, `developer_instructions = "Reply ok."`) in the scratch repo and ask `codex exec 'Start the harness-probe agent and report its answer.'`; record the tool name used, whether a model can be passed per call, and how a follow-up is sent. F12: list models (`codex` `/model`, Copilot `/model`), pick strong/fast ids per agent, record accepted effort values (`model_reasoning_effort`: `low|medium|high|xhigh`?, Copilot `reasoningEffort`). F13: write a `.codex/config.toml` with `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`, `[sandbox_workspace_write]` `network_access = false`; confirm Codex starts without a config error; run `codex execpolicy check --rules <file> git push origin main` on a one-line rules file `prefix_rule(pattern = ["git", "push"], decision = "prompt")` and record the output format.

- [ ] **Step 6: Write the findings into the spec and commit**

Append to spec §3:

```markdown
### Spike findings (2026-10-04)

| Id | Finding | Evidence |
|---|---|---|
| F1 codex-shell-tool | <observed value> | <log excerpt or command> |
...
```

Every **(spike)** mark in §3 gets "→ F<n>". Where a finding contradicts an assumption of this plan, write the change to the affected task under "Rulings" in the ledger before that task starts (for example: F5 says Copilot ignores nested `permissionDecision` → Task 5 adds a top-level copy). Commit:

```sh
git add docs/specs/2026-10-04-multi-agent-design.md docs/plans/2026-10-04-multi-agent-ledger.md
git commit -m "docs: record Codex and Copilot CLI spike findings"
```

---

### Task 2: guard — Codex patches, Copilot paths, `.harness/env.json`

**Files:**
- Modify: `plugins/harness/scripts/lib/parse.sh` (add `patch_paths`)
- Modify: `plugins/harness/scripts/guard.sh` (`check_path`, bad-parser check, file-tool branch, new shell rule `harness-env`)
- Modify: `plugins/harness/hooks/hooks.json` (file-tool matcher)
- Modify: `tests/hooks/run.sh` (payload types `patch:`, `patchraw:`, `cfile:`)
- Modify: `tests/hooks/cases.tsv`
- Modify: `tests/manifest.sh` (matcher check)

**Interfaces:**
- Consumes: F2 (`apply_patch` tool name and input key), F4 (Copilot path key).
- Produces: `patch_paths <patch text>` in `lib/parse.sh` — prints each path after `*** Add File: `, `*** Update File: `, `*** Delete File: `, `*** Move to: `, one per line, in order. Task 3 uses it.

- [ ] **Step 1: Add payload types to `tests/hooks/run.sh`**

Insert before the `raw:*)` branch:

```bash
    patch:* | patchraw:*)
      # patch:<Tool>:<path>[,<path>...] builds an apply_patch envelope (Codex) that updates each path
      # with a body full of dangerous command text; patchraw:<Tool>:<text with printf %b escapes>
      rest=${payload#*:}
      tool=${rest%%:*}
      rest=${rest#*:}
      if [ "${payload%%:*}" = patch ]; then
        body='*** Begin Patch\n'
        IFS=',' read -r -a ps <<<"$rest"
        for p in "${ps[@]}"; do body="$body*** Update File: $p\n@@\n-old\n+rm -rf / && git push --force origin main\n"; done
        body="$body*** End Patch"
      else
        body=$rest
      fi
      c=$(printf '%b' "$body")
      json=$(jq -nc --arg t "$tool" --arg c "$c" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{command:$c},cwd:$d}') ;;
    cfile:*)
      # cfile:<Tool>:<path> is a file tool in Copilot CLI's shape (tool_input.path, per F4)
      rest=${payload#cfile:}
      tool=${rest%%:*}
      path=${rest#*:}
      json=$(jq -nc --arg t "$tool" --arg p "$path" --arg d "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{path:$p},cwd:$d}') ;;
```

If F2 names a key other than `command`, or F4 a key other than `path`, use the recorded key in these two `jq` filters and in Step 4.

- [ ] **Step 2: Add the failing cases to `tests/hooks/cases.tsv`**

```text
g-patch-01	guard	none	-	block:env-file	patch:apply_patch:src/.env
g-patch-02	guard	none	-	block:secrets-dir	patch:apply_patch:/home/u/.ssh/config
g-patch-03	guard	none	-	pass	patch:apply_patch:src/app.ts
g-patch-04	guard	none	-	block:env-file	patch:apply_patch:src/a.ts,config/.env
g-patch-05	guard	none	-	block:env-file	patchraw:apply_patch:*** Begin Patch\n*** Update File: src/a.ts\n*** Move to: .env\n@@\n-a\n+b\n*** End Patch
g-patch-06	guard	none	-	block:bad-input	patchraw:apply_patch:*** Begin Patch\n*** End Patch
g-patch-07	guard	none	-	block:env-file	patch:Edit:.env
g-patch-08	guard	none	-	pass	patch:apply_patch:.env.example
g-patch-09	guard	none	-	block:env-file	patchraw:apply_patch:*** Begin Patch\n*** Add File: .ENV\n+X=1\n*** End Patch
g-patch-10	guard	none	-	block:secrets-dir	patchraw:apply_patch:*** Begin Patch\n*** Delete File: /root/.aws/credentials\n*** End Patch
g-cop-01	guard	none	-	block:env-file	cfile:Edit:.env
g-cop-02	guard	none	-	block:secrets-dir	cfile:Read:/Users/u/.aws/credentials
g-cop-03	guard	none	-	pass	cfile:Edit:src/app.ts
g-henv-01	guard	none	-	block:harness-env	file:Write:.harness/env.json
g-henv-02	guard	none	-	block:harness-env	file:Read:/repo/.harness/env.json
g-henv-03	guard	none	-	block:harness-env	patch:apply_patch:.harness/env.json
g-henv-04	guard	none	-	block:harness-env	bash:sed -i '' 's/main//' .harness/env.json
g-henv-05	guard	none	-	block:harness-env	bash:echo {} > .harness/env.json
g-henv-06	guard	none	-	pass	bash:mkdir -p .harness/my-change && touch .harness/my-change/progress.md
g-henv-07	guard	none	-	pass	file:Write:.harness/my-change/progress.md
```

- [ ] **Step 3: Run and watch them fail**

Run: `bash tests/hooks/run.sh`
Expected: FAIL lines for `g-patch-01`, `-02`, `-04`, `-05`, `-06`, `-07`, `-09`, `-10`, `g-cop-01`, `-02`, `g-henv-01`…`-05` (they currently pass or block for another reason); `g-patch-03`, `-08`, `g-cop-03`, `g-henv-06`, `-07` already pass.

- [ ] **Step 4: Implement**

In `plugins/harness/scripts/lib/parse.sh`, append:

```bash
# patch_paths <apply_patch text>
# Prints every path an apply_patch envelope (Codex; Copilot CLI's apply_patch) writes, deletes or
# renames to, one per line, in order: the text after "*** Add File: ", "*** Update File: ",
# "*** Delete File: " and "*** Move to: ". The rest of the patch is file content, not a command.
patch_paths() {
  # rule:patch-paths
  printf '%s\n' "$1" | sed -nE 's/^\*\*\* (Add File|Update File|Delete File|Move to): (.+)$/\2/p'
  # end:patch-paths
}
```

In `guard.sh`, extend `check_path` after `# end:secrets-dir-path`:

```bash
  # rule:harness-env-path
  # HARNESS_* for Codex and Copilot CLI hooks; the PO edits it, as with .claude/settings.json
  case "$lp" in
    .harness/env.json | */.harness/env.json) deny harness-env "the harness settings file is changed by the PO only: $p" ;;
  esac
  # end:harness-env-path
```

Add `patch_paths` to both `declare -F` lists (guard.sh and ask-gate.sh `bad-parser` rules):

```bash
if [ "$parsed" != 0 ] || ! declare -F normalize is_abbrev segments git_segments patch_paths >/dev/null; then
```

Replace the file-tool branch at the end of `guard.sh`:

```bash
  Read | Edit | Write | MultiEdit | NotebookEdit | apply_patch)
    # rule:patch-check
    # an apply_patch envelope (Codex sends tool_name apply_patch; Copilot reports its apply_patch as Edit)
    # carries its paths in headers; the body is file content and is not read as a command
    body=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.input // ""')
    case "$body" in
      '*** Begin Patch'*)
        paths=$(patch_paths "$body")
        [ -n "$paths" ] || deny bad-input "the patch names no file, so it could not be checked"
        while IFS= read -r p; do check_path "$p"; done <<EOF
$paths
EOF
        exit 0 ;;
    esac
    # end:patch-check
    [ "$tool" != apply_patch ] || deny bad-input "the patch could not be read, so it could not be checked"
    # rule:file-path-keys
    check_path "$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""')"
    # end:file-path-keys
    ;;
```

In the shell branch, directly after `# end:env-file`:

```bash
    # rule:harness-env
    printf '%s\n' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_])\.harness/env\.json' \
      && deny harness-env "the harness settings file is changed by the PO only"
    # end:harness-env
```

In `hooks/hooks.json`, change the second PreToolUse matcher to `"Read|Edit|Write|MultiEdit|NotebookEdit|apply_patch"`. In `tests/manifest.sh` add:

```bash
check h-patch-matcher '[ "$(jq -r "[.hooks.PreToolUse[] | select(.matcher == \"Read|Edit|Write|MultiEdit|NotebookEdit|apply_patch\")] | length" $h)" = 1 ]'
```

- [ ] **Step 5: Run the fast checks and the mutation test for the new rules**

Run: `bash tests/hooks/run.sh && HOOK_BASH=/bin/bash bash tests/hooks/run.sh && bash tests/hooks/lifecycle.sh && bash tests/lint.sh && bash tests/manifest.sh`
Expected: all pass. Then `bash tests/hooks/mutate.sh` — expected: no survivors (`patch-paths`, `patch-check`, `file-path-keys`, `harness-env-path`, `harness-env` each killed).

- [ ] **Step 6: Commit**

```sh
git add plugins/harness/scripts/lib/parse.sh plugins/harness/scripts/guard.sh plugins/harness/scripts/ask-gate.sh plugins/harness/hooks/hooks.json tests/hooks/run.sh tests/hooks/cases.tsv tests/manifest.sh
git commit -m "feat: guard checks Codex patches, Copilot file paths and the harness env file"
```

---

### Task 3: lint-on-edit — every edited path, one answer all agents read

**Files:**
- Modify: `plugins/harness/scripts/lint-on-edit.sh`
- Modify: `tests/hooks/lifecycle.sh`

**Interfaces:**
- Consumes: `patch_paths` (Task 2); F2 (patch paths relative to `cwd`), F4 (Copilot path key), F6 (which output fields reach the model).
- Produces: on failure, stdout `{"decision":"block","reason":R,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":R}}` and exit 0, where R holds one `lint failed after editing <rel> (exit <n>). Fix it before continuing:` block per failing file. If F6 shows Copilot reads only a top-level `additionalContext`, add `additionalContext:R` at the top level too (and assert it in Step 1). Invalid patterns still exit 2 with the message on stderr.

- [ ] **Step 1: Rewrite the lint helpers in `tests/hooks/lifecycle.sh` and add the failing cases**

Replace `lint()` and add two helpers:

```bash
lintj() { # <json> [env args] -> sets rc, out, err
  local j=$1
  shift
  # shellcheck disable=SC2034 # read by the eval in expect()
  out=$(printf '%s' "$j" | env "$@" "$HOOK_BASH" "$HOOKS_DIR/lint-on-edit.sh" 2>"$TMP_ROOT/lint.err")
  rc=$?
  # shellcheck disable=SC2034
  err=$(cat "$TMP_ROOT/lint.err")
}
lint() { # <file> [env args]: Claude Code's Write
  local f=$1
  shift
  lintj "$(jq -nc --arg p "$f" '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$p},tool_response:{filePath:$p}}')" "$@"
}
lintpatch() { # <cwd> <patch text with %b escapes> [env args]: Codex apply_patch
  local d=$1 t
  t=$(printf '%b' "$2")
  shift 2
  lintj "$(jq -nc --arg d "$d" --arg c "$t" '{hook_event_name:"PostToolUse",tool_name:"apply_patch",tool_input:{command:$c},cwd:$d}')" "$@"
}
blocked() { # <text the reason must contain>
  printf '%s' "$out" | jq -e --arg w "$1" '.decision == "block" and (.reason | contains($w)) and (.hookSpecificOutput.additionalContext | contains($w))' >/dev/null 2>&1
}
```

Change the existing expectations: `l-bad` → `'[ $rc = 0 ] && blocked "lint failed after editing src/bad.ts"'`; `l-pattern-hit` and `l-symlinked-path` → `'[ $rc = 0 ] && blocked "src/bad.ts"'`; every "passes" case (`l-unset`, `l-empty`, `l-good`, `l-doc-skip`, `l-pattern-skip`, `l-no-injection`, `l-outside-repo`) additionally asserts `[ -z "$out" ]`. `l-bad-lint-pattern` / `l-bad-doc-pattern` stay `rc = 2`.

Add after `l-bad-doc-pattern`:

```bash
P='*** Begin Patch\n*** Update File: src/good.ts\n@@\n-a\n+ok\n*** Add File: src/bad.ts\n+BAD\n*** End Patch'
lintpatch "$R" "$P" HARNESS_LINT_CMD="$LINTER"
expect l-patch-multi '[ $rc = 0 ] && blocked "src/bad.ts" && ! printf "%s" "$out" | grep -q "good.ts" && grep -q "src/good.ts" "$TMP_ROOT/lint.log"'
lintpatch "$R" '*** Begin Patch\n*** Delete File: src/gone.ts\n*** End Patch' HARNESS_LINT_CMD="$LINTER"
expect l-patch-delete '[ $rc = 0 ] && [ -z "$out" ]'
lintpatch "$R" '*** Begin Patch\n*** Update File: src/x.ts\n*** Move to: src/bad.ts\n@@\n-a\n+b\n*** End Patch' HARNESS_LINT_CMD="$LINTER"
expect l-patch-move '[ $rc = 0 ] && blocked "src/bad.ts"'
lintpatch "$R" '*** Begin Patch\n*** Update File: docs/x.md\n@@\n-a\n+b\n*** End Patch' HARNESS_LINT_CMD="$LINTER"
expect l-patch-doc '[ $rc = 0 ] && [ -z "$out" ]'
lintj "$(jq -nc --arg p "$R/src/bad.ts" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{path:$p}}')" HARNESS_LINT_CMD="$LINTER"
expect l-copilot-path '[ $rc = 0 ] && blocked "src/bad.ts"'
```

- [ ] **Step 2: Run and watch them fail**

Run: `bash tests/hooks/lifecycle.sh`
Expected: FAIL for `l-bad`, `l-pattern-hit`, `l-symlinked-path` (rc 2, no JSON), `l-patch-multi`, `l-patch-move`, `l-copilot-path`.

- [ ] **Step 3: Implement**

Replace everything in `lint-on-edit.sh` from `input=$(cat)` to the end with:

```bash
input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] || cwd=$(pwd)
# rule:lint-paths
# Claude Code: tool_input.file_path; Copilot CLI: tool_input.path
files=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // .tool_response.filePath // ""')
# end:lint-paths
# rule:lint-patch
# Codex apply_patch: every file the patch adds, updates or moves to (deleted files no longer exist)
if [ -z "$files" ]; then
  # shellcheck source=lib/parse.sh
  . "$(dirname "$0")/lib/parse.sh" 2>/dev/null && declare -F patch_paths >/dev/null || {
    echo "harness lint-on-edit: lib/parse.sh is missing or broken; reinstall the plugin" >&2
    exit 2
  }
  files=$(patch_paths "$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.input // ""')")
fi
# end:lint-patch
report=''
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in /*) ;; *) file=$cwd/$file ;; esac
  [ -f "$file" ] || continue
  dir=$(cd "$(dirname "$file")" && pwd -P) || continue
  abs="$dir/$(basename "$file")"
  # rule:lint-outside-repo
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
  # end:lint-outside-repo
  root=$(cd "$root" && pwd -P) || continue
  rel=${abs#"$root"/}
  # rule:lint-doc-skip
  printf '%s' "$rel" | grep -Eq -- "$doc" && continue
  # end:lint-doc-skip
  # rule:lint-pattern
  if [ -n "${HARNESS_LINT_PATTERN:-}" ]; then
    printf '%s' "$rel" | grep -Eq -- "$HARNESS_LINT_PATTERN" || continue
  fi
  # end:lint-pattern
  # rule:lint-run
  out=$(cd "$root" && bash -c "$HARNESS_LINT_CMD \"\$1\"" harness-lint "$abs" 2>&1)
  status=$?
  if [ "$status" -ne 0 ]; then
    report=$report$(printf 'lint failed after editing %s (exit %d). Fix it before continuing:\n%s' \
      "$rel" "$status" "$(printf '%s\n' "$out" | tail -40)")$'\n'
  fi
  # end:lint-run
done <<EOF
$files
EOF
# rule:lint-report
# decision:block reaches Claude Code and Codex; additionalContext reaches Copilot CLI, whose
# PostToolUse cannot block (exit 2 is only a warning there)
if [ -n "$report" ]; then
  jq -n --arg r "$report" '{decision:"block",reason:$r,hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$r}}'
fi
# end:lint-report
exit 0
```

Update the header comment: "On failure prints `decision: block` with the lint output (plus `additionalContext` for Copilot CLI) so the agent fixes it now."

- [ ] **Step 4: Run the checks**

Run: `bash tests/hooks/lifecycle.sh && HOOK_BASH=/bin/bash bash tests/hooks/lifecycle.sh && bash tests/hooks/run.sh && bash tests/lint.sh`
Expected: all pass. Then `bash tests/hooks/mutate.sh`: no survivors (`lint-paths`, `lint-patch`, `lint-report` killed).

- [ ] **Step 5: Commit**

```sh
git add plugins/harness/scripts/lint-on-edit.sh tests/hooks/lifecycle.sh
git commit -m "feat: lint-on-edit lints every patched file and answers in a form every agent reads"
```

---

### Task 4: hooks read `HARNESS_*` from `.harness/env.json` when unset

**Files:**
- Create: `plugins/harness/scripts/lib/env.sh`
- Modify: `plugins/harness/scripts/guard.sh`, `ask-gate.sh`, `lint-on-edit.sh`, `test-on-stop.sh` (source and call it)
- Modify: `tests/hooks/lifecycle.sh`, `tests/hooks/cases.tsv`, `tests/hooks/run.sh` (fixture repo with an env file), `tests/hooks/mutate.sh` only if it does not already iterate `lib/*.sh` (it does since 0.2.0; verify)

**Interfaces:**
- Produces: `harness_env <dir>` — for each of `HARNESS_LINT_CMD HARNESS_LINT_PATTERN HARNESS_TEST_CMD HARNESS_DOC_PATTERN HARNESS_PROTECTED_BRANCHES` that is unset, exports the string value of that key from `<git root of dir>/.harness/env.json`; ignores every other key; returns 0 always.

- [ ] **Step 1: Write the failing tests**

In `tests/hooks/run.sh`, after the `for b in main feature` loop, add a repository on `main` with an env file:

```bash
git init -q "$TMP_ROOT/envrepo"
git -C "$TMP_ROOT/envrepo" commit -q --allow-empty -m init
mkdir -p "$TMP_ROOT/envrepo/.harness"
printf '%s\n' '{"HARNESS_PROTECTED_BRANCHES":"release","HARNESS_RM_RF_ALLOW":"/tmp/x:/var/tmp/y","HARNESS_ALLOW_LEASE_PUSH":"1"}' > "$TMP_ROOT/envrepo/.harness/env.json"
```

Cases (`where` = `envrepo`):

```text
e-pb-01	ask-gate	envrepo	-	pass	bash:git push origin main
e-pb-02	ask-gate	envrepo	-	ask:protected-push	bash:git push origin release
e-pb-03	ask-gate	envrepo	HARNESS_PROTECTED_BRANCHES=main	ask:protected-push	bash:git push origin main
e-relax-ignored-01	guard	envrepo	-	block:rm-rf	bash:rm -rf /tmp/x/a
e-relax-ignored-02	guard	envrepo	-	block:force-push	bash:git push --force-with-lease=refs/heads/f:abcdef1 origin f:refs/heads/f
```

In `tests/hooks/lifecycle.sh`, add after the stop tests (the repo `$R` is reused; remove the file at the end):

```bash
mkdir -p "$R/.harness"
printf '%s\n' "{\"HARNESS_LINT_CMD\":\"$LINTER\",\"HARNESS_TEST_CMD\":\"false\"}" > "$R/.harness/env.json"
lint "$R/src/bad.ts" -u HARNESS_LINT_CMD
expect e-lint-from-file '[ $rc = 0 ] && blocked "src/bad.ts"'
lint "$R/src/bad.ts" HARNESS_LINT_CMD=
expect e-empty-env-wins '[ $rc = 0 ] && [ -z "$out" ]'
echo change >> "$R/src/good.ts"
stop '{}' -u HARNESS_TEST_CMD
expect e-test-from-file '[ $rc = 0 ] && printf "%s" "$out" | jq -e ".decision == \"block\"" >/dev/null'
git -C "$R" checkout -q -- src/good.ts 2>/dev/null || git -C "$R" restore src/good.ts 2>/dev/null || true
rm -rf "$R/.harness"
```

(`src/good.ts` may be untracked in this fixture; if so, restore it by rewriting `echo ok > "$R/src/good.ts"` instead of git.)

- [ ] **Step 2: Run and watch them fail**

Run: `bash tests/hooks/run.sh; bash tests/hooks/lifecycle.sh`
Expected: FAIL for `e-pb-01` (asks, `main` is the default), `e-pb-02` (passes), `e-lint-from-file`, `e-test-from-file`. `e-pb-03`, `e-relax-ignored-*`, `e-empty-env-wins` already pass.

- [ ] **Step 3: Implement `lib/env.sh`**

```bash
#!/usr/bin/env bash
# HARNESS_* for agents without a per-repository hook environment (Codex, Copilot CLI).
# Source it; it defines functions only.

# harness_env <dir>
# For each listed HARNESS_* variable that is unset (set-but-empty counts as set), exports its string
# value from <git root of dir>/.harness/env.json. Claude Code sets them through .claude/settings.json
# env, which therefore wins. The guard relaxations HARNESS_ALLOW_LEASE_PUSH and HARNESS_RM_RF_ALLOW
# are never read from the file: an agent can write repository files.
harness_env() {
  local root f n v
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  f=$root/.harness/env.json
  [ -f "$f" ] || return 0
  # rule:env-file-read
  for n in HARNESS_LINT_CMD HARNESS_LINT_PATTERN HARNESS_TEST_CMD HARNESS_DOC_PATTERN HARNESS_PROTECTED_BRANCHES; do
    eval "[ -n \"\${$n+x}\" ]" && continue # bash 3.2: no ${!n+x}; n comes from the fixed list above
    v=$(jq -r --arg n "$n" '.[$n] | strings' "$f" 2>/dev/null) || continue
    [ -n "$v" ] || continue
    printf -v "$n" '%s' "$v"
    export "${n?}"
  done
  # end:env-file-read
  return 0
}
```

- [ ] **Step 4: Call it from each hook**

- `guard.sh` and `ask-gate.sh`: after the `bad-parser` rule, source `lib/env.sh` and call `harness_env "$(printf '%s' "$input" | jq -r '.cwd // ""' | sed 's/^$/./')"`. In `ask-gate.sh` move the call before `protected=${HARNESS_PROTECTED_BRANCHES:-main}`. If `lib/env.sh` is missing, continue without it (the file only adds values; a missing file must not block every command).
- `lint-on-edit.sh`: move `# rule:lint-unset` below the computation of `cwd` (it must run after `harness_env "$cwd"`), keeping its behavior: `[ -n "${HARNESS_LINT_CMD:-}" ] || exit 0`. Keep the `no-jq` rule first (jq is needed to read `cwd`).
- `test-on-stop.sh`: after `cwd` is known, `harness_env "$cwd"`, then the `stop-unset` check (move it below).
- Add `lib/env.sh` to the `tests/lint.sh` shellcheck set automatically (it is a tracked `*.sh`).

- [ ] **Step 5: Run the checks and the mutation test**

Run: `bash tests/hooks/run.sh && bash tests/hooks/lifecycle.sh && HOOK_BASH=/bin/bash bash tests/hooks/run.sh && HOOK_BASH=/bin/bash bash tests/hooks/lifecycle.sh && bash tests/hooks/timing.sh && bash tests/lint.sh`
Expected: all pass; `timing.sh` still under 5 s per hook. `bash tests/hooks/mutate.sh`: `env-file-read` killed.

- [ ] **Step 6: Commit**

```sh
git add plugins/harness/scripts tests/hooks
git commit -m "feat: hooks read HARNESS_* from .harness/env.json when the agent cannot set them"
```

---

### Task 5: ask-gate and test-on-stop in Copilot's shape

**Files:**
- Modify: `tests/hooks/run.sh` (decision parsing), `tests/hooks/cases.tsv`, `tests/hooks/lifecycle.sh`
- Modify: `plugins/harness/scripts/ask-gate.sh` only if F5 shows Copilot ignores the nested `permissionDecision`

**Interfaces:**
- Consumes: F1 (Codex shell tool name), F3 (Copilot shell shape), F5.

- [ ] **Step 1: Cases**

Add (`copilot-bash:` is not needed when F3 shows Copilot sends Claude's shape `{tool_name:"Bash",tool_input:{command}}`; then the existing `bash:` payload already covers it — record that in the ledger). If F1 shows Codex's shell `tool_name` is not `Bash`, add a payload type `cshell:<command>` sending that name and these cases:

```text
x-codex-01	guard	none	-	block:rm-rf	cshell:rm -rf build
x-codex-02	ask-gate	main	-	ask:protected-push	cshell:git push origin main
x-codex-03	guard	none	-	pass	cshell:ls
```

and add the name to the `Bash | Monitor` case patterns in `guard.sh` and `ask-gate.sh` and to the `Bash|Monitor` matcher in `hooks.json` (then update `tests/manifest.sh` `h-monitor` to the new matcher string).

In `lifecycle.sh`, add a Copilot-shaped stop:

```bash
echo change >> "$R/src/good.ts"
stop '{"stop_hook_active":false}' HARNESS_TEST_CMD=false
expect s-copilot-shape '[ $rc = 0 ] && printf "%s" "$out" | jq -e ".decision == \"block\" and (.reason | length > 0)" >/dev/null'
echo ok > "$R/src/good.ts"
```

- [ ] **Step 2: If F5 says top-level only**

Change `ask()` in `ask-gate.sh` to print both forms, test-first: first change `run.sh` to require both (`decision` read from `.hookSpecificOutput.permissionDecision` and `.permissionDecision` must both equal `ask`), see every ask case fail, then:

```bash
ask() {
  jq -nc --arg r "harness ask-gate ($1): $2" \
    '{permissionDecision:"ask",permissionDecisionReason:$r,hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}
```

(`no-jq` cannot use jq: keep a `printf` variant for that one call.) Then verify by hand in Claude Code (`claude --plugin-dir plugins/harness`, run `git push origin main` in a scratch repo, expect the ask prompt) that the extra top-level fields are accepted; record the result in the ledger. If F5 says nested works, skip this step and note it.

- [ ] **Step 3: Run, then commit**

Run: `bash tests/hooks/run.sh && bash tests/hooks/lifecycle.sh && bash tests/hooks/mutate.sh`
Expected: pass, no survivors.

```sh
git add plugins/harness tests/hooks
git commit -m "test: cover Copilot CLI and Codex shell payloads in ask-gate and test-on-stop"
```

---

### Task 6: Codex agent definitions generated from the plugin agents

**Files:**
- Create: `scripts/gen-codex-agents.sh` (repository tool, not shipped in the plugin)
- Create (generated): `template/{% if use_codex %}.codex{% endif %}/agents/harness-implementer.toml`, `harness-reviewer.toml`, `harness-reviewer-intermediate.toml`
- Create: `tests/codex-agents.sh`; Modify: `tests/all.sh` (add it after `manifest.sh`)

**Interfaces:**
- Consumes: F9 (name charset; if hyphens are invalid, use underscores everywhere below and in Task 11), F12 (`codex` strong/fast model ids and effort values).
- Produces: three agents named `harness-implementer`, `harness-reviewer`, `harness-reviewer-intermediate`; Task 8 renders the directory, Task 11 names them in `harness:execute`.

- [ ] **Step 1: Write the test**

`tests/codex-agents.sh`:

```bash
#!/usr/bin/env bash
# The committed Codex agent files equal a fresh render from plugins/harness/agents/*.md.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd -P)
# shellcheck source=lib.sh
. "$repo/tests/lib.sh"
setup_git_env
out="$TMP_ROOT/agents"
mkdir -p "$out"
bash "$repo/scripts/gen-codex-agents.sh" "$out" || ng "generator failed"
dir="$repo/template/{% if use_codex %}.codex{% endif %}/agents"
for n in harness-implementer harness-reviewer harness-reviewer-intermediate; do
  if cmp -s "$out/$n.toml" "$dir/$n.toml"; then ok; else ng "$n.toml is stale: run scripts/gen-codex-agents.sh"; fi
  if uvx --from copier@9.18.2 python -c 'import sys, tomllib; d = tomllib.load(open(sys.argv[1], "rb")); sys.exit(0 if all(d.get(k) for k in ("name", "description", "developer_instructions", "model", "model_reasoning_effort")) else 1)' "$dir/$n.toml"; then ok; else ng "$n.toml is not valid TOML with the required keys"; fi
done
report "codex agents"
```

Run: `bash tests/codex-agents.sh` — Expected: FAIL (generator missing).

- [ ] **Step 2: Write the generator**

`scripts/gen-codex-agents.sh`:

```bash
#!/usr/bin/env bash
# Renders the Codex agent definitions (.codex/agents/*.toml) from the plugin's Claude-format agents.
# Codex plugins cannot carry agents, so the template ships these files; tests/codex-agents.sh fails
# when they differ from a fresh render. Usage: scripts/gen-codex-agents.sh [<out dir>]
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd -P)
out=${1:-"$repo/template/{% if use_codex %}.codex{% endif %}/agents"}
src=$repo/plugins/harness/agents
# Model ids and efforts from spec §3 Spike findings F12 (the Codex column of docs/harness/models.md).
STRONG_MODEL='<F12 codex strong id>' STRONG_EFFORT=high
FAST_MODEL='<F12 codex fast id>' FAST_EFFORT=medium
mkdir -p "$out"

field() { sed -n "2,/^---\$/s/^$1: //p" "$2" | head -n 1; }
body() { awk 'n >= 2 { print } /^---$/ { n++ }' "$1"; }

emit() { # <src md> <name> <model> <effort> <sandbox>
  local b
  b=$(body "$1")
  case "$b" in *"'''"*) echo "gen-codex-agents: $1 contains ''' and cannot be a TOML literal string" >&2; exit 1 ;; esac
  {
    printf '# Generated by scripts/gen-codex-agents.sh from plugins/harness/agents/%s. Do not edit.\n' "$(basename "$1")"
    printf 'name = "%s"\n' "$2"
    printf 'description = %s\n' "$(field description "$1" | jq -Rs 'rtrimstr("\n")')"
    printf 'model = "%s"\n' "$3"
    printf 'model_reasoning_effort = "%s"\n' "$4"
    printf 'sandbox_mode = "%s"\n' "$5"
    printf "developer_instructions = '''\n%s\n'''\n" "$b"
  } > "$out/$2.toml"
}

emit "$src/implementer.md" harness-implementer "$FAST_MODEL" "$FAST_EFFORT" workspace-write
emit "$src/reviewer.md" harness-reviewer "$STRONG_MODEL" "$STRONG_EFFORT" read-only
emit "$src/reviewer.md" harness-reviewer-intermediate "$FAST_MODEL" "$STRONG_EFFORT" read-only
```

Before running, replace the two `<F12 …>` markers with the ids recorded in spec §3 F12 (they are the only inputs this task takes from the spike). `jq -Rs` produces a JSON string, which is a valid TOML basic string for this text (no control characters). The intermediate reviewer keeps the reviewer's effort of high, as `docs/harness/models.md` says for Claude.

- [ ] **Step 3: Generate, test, commit**

Run: `bash scripts/gen-codex-agents.sh && bash tests/codex-agents.sh && bash tests/lint.sh`
Expected: `codex agents: pass=6 fail=0`, shellcheck clean.

```sh
git add scripts/gen-codex-agents.sh tests/codex-agents.sh tests/all.sh "template/{% if use_codex %}.codex{% endif %}"
git commit -m "feat: generate Codex agent definitions from the plugin agents"
```

---

### Task 7: Copier question `agents` and conditional Claude files

**Files:**
- Modify: `copier.yml`
- Rename: `template/CLAUDE.md.jinja` → `template/{% if use_claude %}CLAUDE.md{% endif %}.jinja`
- Rename: `template/.claude/` → `template/{% if use_claude or use_copilot %}.claude{% endif %}/`
- Rename: `…/.claude…/settings.json.jinja` → `…/{% if use_claude %}settings.json{% endif %}.jinja`
- Modify: `template/AGENTS.md.jinja`, `template/.github/workflows/ci.yml.jinja` (context-budget step)
- Modify: `tests/template/run.sh`

**Interfaces:**
- Produces: computed Copier variables `use_claude`, `use_codex`, `use_copilot` (bool) for every later template task.

- [ ] **Step 1: Failing template checks**

In `tests/template/run.sh`, keep `common` for Claude renders and add after the `D1` block:

```bash
check defaults-agents 'grep -qx "agents:" "$D1/.copier-answers.yml" && grep -qx -- "- claude" "$D1/.copier-answers.yml"'
check defaults-no-codex '[ ! -e "$D1/.codex" ] && [ ! -e "$D1/.github/copilot" ] && [ ! -e "$D1/.github/copilot-instructions.md" ] && [ ! -e "$D1/.harness" ]'

DC="$TMP_ROOT/codex-only"
render "$DC" v9.9.0 --data 'agents=[codex]'
check codex-no-claude '[ ! -e "$DC/CLAUDE.md" ] && [ ! -e "$DC/.claude" ]'
check codex-agents-md '! grep -qF "CLAUDE.md" "$DC/AGENTS.md"'
check codex-ci-budget '$CJS --builtin-schema vendor.github-workflows "$DC/.github/workflows/ci.yml" >/dev/null 2>&1 && ! grep -qF "CLAUDE.md" "$DC/.github/workflows/ci.yml"'

DP="$TMP_ROOT/copilot-only"
render "$DP" v9.9.0 --data 'agents=[copilot]'
check copilot-rules '[ -d "$DP/.claude/rules" ] && [ ! -e "$DP/.claude/settings.json" ] && [ ! -e "$DP/CLAUDE.md" ]'
check copilot-ci-budget '! grep -qF "CLAUDE.md" "$DP/.github/workflows/ci.yml" && grep -qF ".claude/rules" "$DP/.github/workflows/ci.yml"'

check none-rejected '! $COPIER copy --quiet --defaults --vcs-ref v9.9.0 --data project_name=S --data github_owner=o --data "agents=[]" "$SRC" "$TMP_ROOT/none" >/dev/null 2>&1'
```

(The "Codex specifics" section is checked in Task 8, which adds it.)

Run: `bash tests/template/run.sh` — Expected: FAIL for the new checks (`agents` unknown, files rendered).

- [ ] **Step 2: `copier.yml`**

Append:

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
use_claude:
  type: bool
  default: "{{ 'claude' in agents }}"
  when: false
use_codex:
  type: bool
  default: "{{ 'codex' in agents }}"
  when: false
use_copilot:
  type: bool
  default: "{{ 'copilot' in agents }}"
  when: false
```

- [ ] **Step 3: Renames**

```sh
git mv template/CLAUDE.md.jinja 'template/{% if use_claude %}CLAUDE.md{% endif %}.jinja'
git mv template/.claude 'template/{% if use_claude or use_copilot %}.claude{% endif %}'
git mv 'template/{% if use_claude or use_copilot %}.claude{% endif %}/settings.json.jinja' 'template/{% if use_claude or use_copilot %}.claude{% endif %}/{% if use_claude %}settings.json{% endif %}.jinja'
```

- [ ] **Step 4: `AGENTS.md.jinja` intro line and `ci.yml.jinja` budget step**

In `AGENTS.md.jinja`, replace "The rules below are tool-neutral; Claude Code specifics are in `CLAUDE.md`." with:

```jinja
{%- set where = [] -%}
{%- if use_claude %}{% set _ = where.append("Claude Code specifics are in `CLAUDE.md`") %}{% endif -%}
{%- if use_copilot %}{% set _ = where.append("Copilot CLI specifics are in `.github/copilot-instructions.md`") %}{% endif -%}
{%- if use_codex %}{% set _ = where.append("Codex specifics are in the last section of this file") %}{% endif %}
This repository is built with a harness in which a human **PO** steers and a coding agent executes. The rules below are tool-neutral; {{ where | join("; ") }}.
```

and the Commands paragraph sentence "…to `.claude/settings.json` (`HARNESS_LINT_CMD`, `HARNESS_TEST_CMD`)…" with `{{ "to `.claude/settings.json`" if use_claude }}{{ " and " if use_claude and (use_codex or use_copilot) }}{{ "to `.harness/env.json`" if use_codex or use_copilot }} (`HARNESS_LINT_CMD`, `HARNESS_TEST_CMD`)` — keeping the exact 0.4.0 wording when only `claude` is selected.

In `ci.yml.jinja`, render the budget step's file list from the selection:

```jinja
{%- set ctx = ["AGENTS.md"] + (["CLAUDE.md"] if use_claude else []) + ([".claude/rules/*.md"] if use_claude or use_copilot else []) + ([".github/copilot-instructions.md"] if use_copilot else []) %}
      - name: Context budget ({{ ctx | join(" + ") | replace("/*.md", "") }} <= 16000 bytes)
        run: |
          bytes=$(cat {{ ctx | join(" ") }} | wc -c)
```

For `[claude]` this must print exactly the 0.4.0 lines (`AGENTS.md + CLAUDE.md + .claude/rules <= 16000 bytes`, `cat AGENTS.md CLAUDE.md .claude/rules/*.md`).

In `tests/template/run.sh` `common`, change `-budget` to compute the same file set, and keep `common` for renders with `claude`; for `DC`/`DP` add `codex-rendered`/`copilot-rendered` checks for `AGENTS.md`, `-no-jinja`, `-workflow-schema`.

- [ ] **Step 5: Byte-identity check against 0.4.0-rc.1 (one-time, recorded)**

```sh
B=$SCRATCH/compat && rm -rf "$B" && mkdir -p "$B"
uvx copier@9.18.2 copy --quiet --defaults --vcs-ref v0.4.0-rc.1 --data project_name=Sample --data github_owner=octo . "$B/old"
uvx copier@9.18.2 copy --quiet --defaults --vcs-ref HEAD --data project_name=Sample --data github_owner=octo . "$B/new"
diff -r "$B/old" "$B/new"
```

(Commit first, or the HEAD render misses the working tree.) Expected differences: only `.copier-answers.yml` (`_commit`, `agents`) and the marketplace `ref` in `.claude/settings.json`. Paste the diff into the ledger.

- [ ] **Step 6: Run and commit**

Run: `bash tests/template/run.sh && bash tests/lint.sh`
Expected: pass.

```sh
git add -A copier.yml template tests/template/run.sh
git commit -m "feat: Copier question agents renders only the selected agents' files"
```

---

### Task 8: Codex template files

**Files:**
- Create: `template/{% if use_codex %}.codex{% endif %}/config.toml`
- Create: `template/{% if use_codex %}.codex{% endif %}/rules/harness.rules.jinja`
- Create: `template/{% if use_codex or use_copilot %}.harness{% endif %}/env.json.jinja`
- Modify: `template/.gitignore` → `template/.gitignore.jinja`; `template/AGENTS.md.jinja` (Codex specifics section)
- Modify: `tests/template/run.sh`

**Interfaces:**
- Consumes: F13 (config keys, `execpolicy check`), F8 (skill names), F9 (agent start/follow-up), Task 6 agents, Task 7 variables.

- [ ] **Step 1: Failing checks** (append to the `DC` block)

```bash
toml_ok() { uvx --from copier@9.18.2 python -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; }
check codex-config 'toml_ok "$DC/.codex/config.toml" && grep -qx "sandbox_mode = \"workspace-write\"" "$DC/.codex/config.toml" && grep -qx "approval_policy = \"on-request\"" "$DC/.codex/config.toml"'
check codex-agents '[ -f "$DC/.codex/agents/harness-implementer.toml" ] && [ -f "$DC/.codex/agents/harness-reviewer.toml" ] && [ -f "$DC/.codex/agents/harness-reviewer-intermediate.toml" ]'
check codex-rules 'grep -qF "prefix_rule(pattern = [\"git\", \"push\"], decision = \"prompt\"" "$DC/.codex/rules/harness.rules" && grep -qF "[\"git\", \"push\", \"--force\"], decision = \"forbidden\"" "$DC/.codex/rules/harness.rules"'
check codex-env 'jq -e ".HARNESS_PROTECTED_BRANCHES == \"main\" and (has(\"HARNESS_RM_RF_ALLOW\") | not) and (has(\"HARNESS_ALLOW_LEASE_PUSH\") | not)" "$DC/.harness/env.json" >/dev/null'
check codex-gitignore 'grep -qx ".harness/\*" "$DC/.gitignore" && grep -qx "!.harness/env.json" "$DC/.gitignore" && ! grep -qx ".harness/" "$DC/.gitignore"'
check codex-section 'grep -qF "## Codex specifics" "$DC/AGENTS.md" && grep -qF "harness-reviewer-intermediate" "$DC/AGENTS.md"'
check defaults-gitignore 'grep -qx ".harness/" "$D1/.gitignore"'
if command -v codex >/dev/null 2>&1; then
  check codex-execpolicy 'codex execpolicy check --rules "$DC/.codex/rules/harness.rules" git push --force origin x | grep -q forbidden'
else
  echo "template: codex CLI not found; execpolicy check skipped" >&2
fi
```

(Adjust the `execpolicy` invocation and its expected output to F13.) Run — Expected: FAIL.

- [ ] **Step 2: Files**

`.codex/config.toml`:

```toml
# harness: Codex settings for this repository. Codex reads this file only after you trust the project.
# Hooks come from the harness plugin; commands that ask or are refused are in rules/harness.rules.
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
# No host allowlist in Codex: network stays off and commands that need it (git push, gh, installs)
# ask for approval. The Claude Code sandbox allows GitHub and package registries instead.
network_access = false
```

`.codex/rules/harness.rules.jinja` (Starlark; one rule per prefix, decisions per spec §6.2):

```python
# harness: what ask-gate sends to the PO and what .claude/settings.json denies, for Codex.
# Codex hooks cannot ask, so these rules do. They match command prefixes only: every git push asks,
# not only pushes to {{ default_branch }}.
prefix_rule(pattern = ["git", "push", "--force"], decision = "forbidden", justification = "force pushes are refused (harness guard)")
prefix_rule(pattern = ["git", "push", "-f"], decision = "forbidden", justification = "force pushes are refused (harness guard)")
prefix_rule(pattern = ["git", "reset", "--hard"], decision = "forbidden", justification = "discards work (harness guard)")
prefix_rule(pattern = ["git", "clean"], decision = "forbidden", justification = "discards work (harness guard)")
prefix_rule(pattern = ["sudo"], decision = "forbidden", justification = "no privilege escalation")
prefix_rule(pattern = ["git", "push"], decision = "prompt", justification = "the PO confirms pushes")
prefix_rule(pattern = ["git", "worktree", "remove", "--force"], decision = "prompt", justification = "may discard work")
prefix_rule(pattern = ["rm"], decision = "prompt", justification = "deletions go to the PO")
prefix_rule(pattern = ["curl"], decision = "prompt", justification = "network download")
prefix_rule(pattern = ["wget"], decision = "prompt", justification = "network download")
prefix_rule(pattern = ["gh", "pr", "merge"], decision = "prompt", justification = "merging is the PO's")
prefix_rule(pattern = ["gh", "repo", "create"], decision = "prompt", justification = "side effect outside the repository")
prefix_rule(pattern = ["gh", "repo", "delete"], decision = "prompt", justification = "destructive")
prefix_rule(pattern = ["gh", "issue", "close"], decision = "prompt", justification = "the PO closes Issues")
prefix_rule(pattern = ["gh", "issue", "edit"], decision = "prompt", justification = "the PO edits Issues")
prefix_rule(pattern = ["gh", "release"], decision = "prompt", justification = "releases are the PO's")
prefix_rule(pattern = ["gh", "workflow", "run"], decision = "prompt", justification = "side effect outside the repository")
prefix_rule(pattern = ["pnpm", "add"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["pnpm", "install"], decision = "prompt", justification = "may change the lockfile")
prefix_rule(pattern = ["pnpm", "remove"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["npm", "install"], decision = "prompt", justification = "may change the lockfile")
prefix_rule(pattern = ["npm", "uninstall"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["yarn", "add"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["yarn", "remove"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["bun", "add"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["bun", "remove"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["uv", "add"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["uv", "remove"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["uv", "lock"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["pip", "install"], decision = "prompt", justification = "installs packages")
prefix_rule(pattern = ["cargo", "add"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["cargo", "remove"], decision = "prompt", justification = "changes the lockfile")
prefix_rule(pattern = ["cargo", "update"], decision = "prompt", justification = "changes the lockfile")
```

(`-uf`, `--force-with-lease` and `+refspec` stay with `guard`, which reads the whole command; this file is the ask channel. If F13 shows the most specific rule does not win over `git push` → `prompt`, record the precedence and order accordingly.)

`.harness/env.json.jinja` (only the five readable keys, same values as `.claude/settings.json` `env`):

```jinja
{%- set env = {"HARNESS_PROTECTED_BRANCHES": default_branch} -%}
{%- if lint_cmd %}{% set _ = env.update({"HARNESS_LINT_CMD": lint_cmd}) %}{% endif -%}
{%- if lint_pattern %}{% set _ = env.update({"HARNESS_LINT_PATTERN": lint_pattern}) %}{% endif -%}
{%- if test_cmd %}{% set _ = env.update({"HARNESS_TEST_CMD": test_cmd}) %}{% endif -%}
{{ env | to_json(ensure_ascii=False, indent=2, sort_keys=True) }}
```

`template/.gitignore` → `.gitignore.jinja`, replacing the `.harness/` line with:

```jinja
{% if use_codex or use_copilot -%}
.harness/*
!.harness/env.json
{%- else -%}
.harness/
{%- endif %}
```

(`git mv template/.gitignore template/.gitignore.jinja` first; check the `[claude]` render keeps the file byte-identical.)

AGENTS.md "Codex specifics" section, appended at the end of `AGENTS.md.jinja` inside `{% if use_codex %}…{% endif %}`:

```markdown
## Codex specifics

The `harness` plugin (installed with `codex plugin marketplace add joe-yama/agentic-harness --ref <tag>`, see `harness:adopt`) supplies the hooks and the skills; `.codex/` holds the rest.

| Situation | Use |
|---|---|
| Starting, resuming or finishing a change | skill `<F8 name of harness:workflow>` |
| Design session | `<F8 name of harness:design>` |
| Proposal, archive, update | `$openspec-propose`, `$openspec-archive-change`, `$openspec-update-change` |
| Implementing `tasks.md` | `<F8 name of harness:execute>` |

- Subagents: `harness-implementer`, `harness-reviewer` (final review) and `harness-reviewer-intermediate` in `.codex/agents/`; their models are fixed there (see `docs/harness/models.md`). Start them as F9 records; the context that implemented something never reviews it.
- Hooks: the plugin's hooks block destructive commands and secret access, lint edited files and run tests before the turn ends; they read `HARNESS_*` from `.harness/env.json`, which only the PO edits. Codex hooks cannot ask: `.codex/rules/harness.rules` sends pushes, deletions, merges, releases and lockfile changes to the PO instead.
- Project trust: Codex reads `.codex/config.toml`, `.codex/rules/` and the plugin hooks only after you trust the project and review the hooks.
- Headless: `codex exec "<prompt>"`; give it a completion condition and stop after N turns.
```

Replace each `<F8 …>` with the skill invocation recorded in F8 (for example `$harness:workflow`) before committing.

- [ ] **Step 3: Run and commit**

Run: `bash tests/template/run.sh && bash tests/lint.sh`
Expected: pass.

```sh
git add -A template tests/template/run.sh
git commit -m "feat: template renders Codex settings, rules, agents and env file"
```

---

### Task 9: Copilot CLI template files

**Files:**
- Create: `template/.github/{% if use_copilot %}copilot{% endif %}/settings.json.jinja`
- Create: `template/.github/{% if use_copilot %}copilot-instructions.md{% endif %}.jinja`
- Modify: `tests/template/run.sh`

**Interfaces:**
- Consumes: F10 (dispatch and resume), F11 (`/opsx:*` or skills), F14 (double load), Task 7 variables, Task 8 env file. The marketplace pin uses the same `ref` logic as `.claude/settings.json`; move that logic into a shared include so both files compute it once.

- [ ] **Step 1: Failing checks** (append to the `DP` block, plus an all-agents render)

```bash
check copilot-settings 'jq -e ".enabledPlugins[\"harness@agentic-harness\"] == true and .extraKnownMarketplaces[\"agentic-harness\"].source.ref == \"v9.9.0\" and .extraKnownMarketplaces[\"agentic-harness\"].source.repo == \"joe-yama/agentic-harness\"" "$DP/.github/copilot/settings.json" >/dev/null'
check copilot-instructions 'grep -qF "Copilot CLI specifics" "$DP/.github/copilot-instructions.md"'
check copilot-env '[ -f "$DP/.harness/env.json" ]'
DA="$TMP_ROOT/all-agents"
render "$DA" v9.9.0 --data 'agents=[claude, codex, copilot]'
common all "$DA"
check all-files '[ -f "$DA/CLAUDE.md" ] && [ -f "$DA/.codex/config.toml" ] && [ -f "$DA/.github/copilot/settings.json" ] && [ -f "$DA/.harness/env.json" ]'
check all-same-ref '[ "$(jq -r ".extraKnownMarketplaces[\"agentic-harness\"].source.ref" "$DA/.github/copilot/settings.json")" = "$(settings "$DA" ".extraKnownMarketplaces[\"agentic-harness\"].source.ref")" ]'
```

Run — Expected: FAIL.

- [ ] **Step 2: Shared ref include**

Move the `{%- set c = … -%}` … `{%- set ref = … -%}` block (and its comment) from the top of `.claude/settings.json.jinja` into a new file `template/includes/marketplace_ref.jinja`, and put in its place:

```jinja
{%- from "includes/marketplace_ref.jinja" import ref with context -%}
```

Jinja exports a template's top-level `set` names to `from … import`, and `with context` gives the include `_commit`. Keep the directory out of renders in `copier.yml`. A custom `_exclude` replaces Copier's default list, so repeat it:

```yaml
_exclude:
  - copier.yml
  - copier.yaml
  - "~*"
  - "*.py[co]"
  - __pycache__
  - .git
  - .DS_Store
  - .svn
  - includes
```

Run `bash tests/template/run.sh` (the `defaults-ref`, `untagged-ref` and rc checks cover the moved logic) and repeat the Task 7 Step 5 byte-identity diff.

- [ ] **Step 3: Files**

`.github/copilot/settings.json.jinja`:

```jinja
{%- from "includes/marketplace_ref.jinja" import ref with context -%}
{
  "enabledPlugins": {
    "harness@agentic-harness": true
  },
  "extraKnownMarketplaces": {
    "agentic-harness": {
      "source": {
        "source": "github",
        "repo": "joe-yama/agentic-harness",
        "ref": {{ ref | to_json(ensure_ascii=False) }}
      }
    }
  }
}
```

`.github/copilot-instructions.md.jinja`:

```markdown
# Copilot CLI specifics

`AGENTS.md` holds the rules; this file adds what differs in GitHub Copilot CLI. The `harness@agentic-harness` plugin (installed from `.github/copilot/settings.json`, see `harness:adopt`) supplies the hooks, the subagents and the skills.

| Situation | Use |
|---|---|
| Starting, resuming or finishing a change | `harness:workflow` |
| Design session | `harness:design` |
| Proposal, archive, update | <F11: `/opsx:propose`, `/opsx:archive`, `/opsx:update`, or the skills `openspec-propose`, `openspec-archive-change`, `openspec-update-change`> |
| Implementing `tasks.md` | `harness:execute` |

- Subagents: start `harness:implementer` and `harness:reviewer` with the `task` tool <F10: "and pass the model from the Copilot CLI table in `docs/harness/models.md`" or "; their models come from the agent definitions, see `docs/harness/models.md`">. The context that implemented something never reviews it.
- Permissions: Copilot CLI does not read the `permissions` or `sandbox` of `.claude/settings.json`. The plugin's `guard` hook is the barrier inside the agent; CI job `check` and the branch ruleset are the barrier outside. Start interactive sessions without `--allow-all-tools`.
- Hooks read `HARNESS_*` from `.harness/env.json`, which only the PO edits. A hook refusal is a policy decision: do not rephrase the command to get around it; ask the PO.
- Headless: `copilot -p "<prompt>" --allow-all-tools --no-ask-user`; prompting operations are denied, so list them in the final report.
{% if use_claude %}- `CLAUDE.md` is Claude Code's file; ignore its Claude-only instructions.{% endif %}
```

Resolve the `<F10 …>` and `<F11 …>` alternatives with the recorded findings before committing. If F14 shows the shared text is loaded twice when `claude` is also selected, add one line under the table: "`CLAUDE.md` imports `AGENTS.md`, so Copilot CLI may show the rules twice; they are the same rules."

- [ ] **Step 4: Run and commit**

Run: `bash tests/template/run.sh && bash tests/lint.sh`
Expected: pass.

```sh
git add -A copier.yml template tests/template/run.sh
git commit -m "feat: template renders Copilot CLI settings and instructions"
```

---

### Task 10: models per agent and the OpenSpec CI step

**Files:**
- Modify: `template/docs/harness/models.md` → `models.md.jinja`
- Modify: `template/.github/workflows/ci.yml.jinja` (OpenSpec step)
- Modify: `tests/template/run.sh` (`models_ok`, OpenSpec checks)

**Interfaces:**
- Consumes: F12 (ids and efforts per agent), F10 (Copilot per-dispatch model), F11, Task 6 names.

- [ ] **Step 1: Failing checks**

Change `models_ok` to read only the rows of the first table (stop at the first `## ` line), and add:

```bash
# rows of the table under "## <heading>": four roles, a model, an effort, no Haiku
agent_models_ok() { awk -F'|' -v h="## $2" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return tolower(s) }
  $0 == h { on = 1; next }
  on && /^## / { on = 0 }
  on && /^\|/ { m = trim($3); if (m == "model" || m ~ /^[-: ]+$/) next; n++; if (m == "" || trim($4) == "" || tolower($0) ~ /haiku/) bad = 1 }
  END { exit (bad || n != 4) }' "$1"; }
check codex-models 'agent_models_ok "$DC/docs/harness/models.md" Codex'
check copilot-models 'agent_models_ok "$DP/docs/harness/models.md" "Copilot CLI"'
check all-models 'models_ok "$DA/docs/harness/models.md" && agent_models_ok "$DA/docs/harness/models.md" Codex && agent_models_ok "$DA/docs/harness/models.md" "Copilot CLI"'
check codex-openspec-skills 'os_run "$DC" .agents/skills/openspec-propose/SKILL.md .agents/skills/openspec-archive-change/SKILL.md .agents/skills/openspec-update-change/SKILL.md .agents/skills/openspec-sync-specs/SKILL.md .agents/skills/.openspec-target'
check codex-openspec-extra '! os_run "$DC" .agents/skills/openspec-explore/SKILL.md && grep -q "openspec-explore" "$TMP_ROOT/os.log"'
```

Run — Expected: FAIL.

- [ ] **Step 2: `models.md.jinja`**

`git mv template/docs/harness/models.md template/docs/harness/models.md.jinja`. Wrap the existing Claude table and its "How the model and effort are set" section in `{% if use_claude %}…{% endif %}` without changing a byte inside (the `[claude]` render stays identical), and append:

```jinja
{% if use_codex %}
## Codex

| Role | Model | Effort | Agent |
|---|---|---|---|
| Decision: the design session | <F12 codex strong> | high | the session itself |
| Final review of the whole branch | <F12 codex strong> | high | `harness-reviewer` |
| Implementation | <F12 codex fast> | medium | `harness-implementer` |
| Intermediate review | <F12 codex fast> | high | `harness-reviewer-intermediate` |

Codex sets the model in each agent file (`.codex/agents/*.toml`, generated from the plugin agents); pick the agent, not a model, when you start one.
{% endif %}
{% if use_copilot %}
## Copilot CLI

| Role | Model | Effort |
|---|---|---|
| Decision: the design session | <F12 copilot strong> | high |
| Final review of the whole branch | <F12 copilot strong> | high |
| Implementation | <F12 copilot fast> | medium |
| Intermediate review | <F12 copilot fast> | high |

<F10: how the model is passed per dispatch, or that the agent definition fixes it and the intermediate review then uses the final-review model.>
{% endif %}
```

Replace every `<F…>` with the recorded values before committing (the efforts follow the Claude table: intermediate review keeps the reviewer's high). When `claude` is not selected, keep the file's first two paragraphs (title and "Which model and effort each role uses…") outside the `if`.

- [ ] **Step 3: OpenSpec step**

In `ci.yml.jinja`, add one `find` line, rendered only when `use_codex or use_copilot`, so the `[claude]` render stays byte-identical:

```jinja
            find .claude/commands/opsx -mindepth 1 ! -name propose.md ! -name archive.md ! -name update.md ! -name sync.md
{%- if use_codex or use_copilot %}
            find .agents/skills -mindepth 1 -maxdepth 1 -name 'openspec-*' ! -name openspec-propose ! -name openspec-archive-change ! -name openspec-update-change ! -name openspec-sync-specs
{%- endif %}
```

The step name stays as in 0.4.0 for `[claude]`; when Codex or Copilot is selected it reads "OpenSpec agent files (only propose, archive, update and sync stay)" (`os_step` matches the `OpenSpec` prefix). `.agents/skills/.openspec-target` is not matched (`-name 'openspec-*'`).

- [ ] **Step 4: Run and commit**

Run: `bash tests/template/run.sh`
Expected: pass.

```sh
git add -A template tests/template/run.sh
git commit -m "feat: per-agent model tables and OpenSpec skill allowlist for Codex"
```

---

### Task 11: skills and agents written agent-neutrally

**Files:**
- Modify: `plugins/harness/skills/execute/SKILL.md`, `workflow/SKILL.md`, `design/SKILL.md`, `mutation-check/SKILL.md` (check only)
- Modify: `plugins/harness/agents/implementer.md`, `reviewer.md`
- Modify: `template/{% if use_claude %}CLAUDE.md{% endif %}.jinja` (receives Claude-only material)
- Modify: `tests/manifest.sh` (neutrality check)
- Regenerate: Codex agent files (Task 6 generator)

**Interfaces:**
- Consumes: F8, F9, F10, F11 names; Task 6 agent names; Task 10 models tables.

- [ ] **Step 1: Failing neutrality check** in `tests/manifest.sh`:

```bash
# Skills and agents are agent-neutral: Claude-only mechanisms appear only in table rows (per-agent tables).
# Offending lines (path:line:text) print on stdout.
check neutral-skills '! grep -rnE "subagent_type|/goal|claude -p|scratchpad|SendMessage|Claude Code builds" plugins/harness/skills plugins/harness/agents | grep -vE "^[^:]+:[0-9]+:\|"'
```

Run: `bash tests/manifest.sh` — Expected: FAIL listing `execute/SKILL.md` (Dispatch, Fix round, Waiting), `workflow/SKILL.md` (Long and unattended runs), `implementer.md:9`.

- [ ] **Step 2: Edit `harness:execute`**

- Replace the paragraph "Models and effort for every role … Always pass `model` explicitly on each dispatch, per that table; an omitted model inherits the session's." with: "Models and effort for every role are in the project's `docs/harness/models.md`, in your agent's section. Where your agent passes a model per dispatch, always pass it; an omitted model inherits the session's."
- Replace the **Dispatch** line with:

```markdown
**Dispatch.** Start the reviewer with the change path, range, task numbers, URL and items:

| Agent | Implementer | Intermediate review | Final review | Follow-up to a running subagent |
|---|---|---|---|---|
| Claude Code | `Agent(subagent_type: "harness:implementer", model: …)` | `Agent(subagent_type: "harness:reviewer", model: <intermediate>)` | `Agent(subagent_type: "harness:reviewer", model: <final>)` | `SendMessage` |
| Codex | <F9: start `harness-implementer`> | <F9: start `harness-reviewer-intermediate`> | <F9: start `harness-reviewer`> | <F9 follow-up> |
| Copilot CLI | <F10: `task` with `harness:implementer`> | <F10> | <F10> | <F10 follow-up> |
```

- In **Fix round** and **Waiting**, replace "`SendMessage`" with "a follow-up to the same subagent (table above)"; add: "If your agent cannot send a follow-up to a finished subagent, dispatch a fresh one with the same inputs plus the findings."
- In section 5 and the last line, replace `/opsx:archive` with "OpenSpec archive".

- [ ] **Step 3: Edit `harness:workflow` and `harness:design`**

- Every `/opsx:propose` / `/opsx:archive` / `/opsx:update` becomes "OpenSpec propose / archive / update", and `harness:workflow` gains:

```markdown
## OpenSpec and agents

| Agent | Propose | Archive | Update |
|---|---|---|---|
| Claude Code | `/opsx:propose` | `/opsx:archive` | `/opsx:update` |
| Codex | `$openspec-propose` | `$openspec-archive-change` | `$openspec-update-change` |
| Copilot CLI | <F11> | <F11> | <F11> |

## Mixed agents

Any stage may run in any agent the repository selected (`.copier-answers.yml` `agents`): for example the design session in Claude Code and `harness:execute` in Codex. Nothing else changes: the hand-off is still the committed change files and the ledger. The PR evidence names the agent and model of each stage.
```

- Replace "Long and unattended runs" with:

```markdown
## Long and unattended runs

Always give a completion condition and a turn limit. Headless, operations that would prompt are denied and skipped, so list them in the final report:

| Agent | Headless |
|---|---|
| Claude Code | `claude -p --permission-mode auto --permission-prompts none --max-turns N` (interactive: `/goal <condition> or stop after N turns`) |
| Codex | `codex exec "<prompt>"` |
| Copilot CLI | `copilot -p "<prompt>" --allow-all-tools --no-ask-user` |

Wait for long jobs with background commands (`gh run watch`, a file appearing), not with polling loops that consume turns.
```

- "Models" section: "…in the project's `docs/harness/models.md`, in your agent's section."
- In `harness:design`, "run `/opsx:propose`" → "run OpenSpec propose (see the table in `harness:workflow`)"; small-change text "`.claude/`" → "agent settings (`.claude/`, `.codex/`, `.github/copilot/`)" in both skills.

- [ ] **Step 4: Agents**

`implementer.md:9`: "…a human PO decides what to build and Claude Code builds it." → "…a human PO decides what to build and a coding agent builds it." Check `reviewer.md` for the same. Then run `bash scripts/gen-codex-agents.sh` (the Codex files must follow).

- [ ] **Step 5: Run and commit**

Run: `bash tests/manifest.sh && bash tests/codex-agents.sh && bash tests/template/run.sh && bash tests/lint.sh`
Expected: pass.

```sh
git add -A plugins/harness template tests/manifest.sh
git commit -m "feat: skills and agents name each agent's mechanics in per-agent tables"
```

---

### Task 12: adopt skill, README, CHANGELOG, manual smoke

**Files:**
- Modify: `plugins/harness/skills/adopt/SKILL.md`
- Modify: `README.md`, `README.ja.md` (same commit), `CHANGELOG.md`, `AGENTS.md` (maintainer layout table: `scripts/`)

- [ ] **Step 1: `harness:adopt`**

- Preflight: per selected agent, `claude --version` (≥ 2.1.277), `codex --version` (≥ F15), `copilot --version` (≥ F15).
- Step 3 questions: add `agents`.
- Step 5 becomes "Install the plugin" with one subsection per agent: Claude Code (unchanged text); Copilot CLI (`.github/copilot/settings.json` registers the marketplace pinned to `<tag>` on trust — or, per F-findings, `copilot plugin marketplace add joe-yama/agentic-harness` + `copilot plugin install harness@agentic-harness`; never add the unpinned default branch); Codex (`codex plugin marketplace add joe-yama/agentic-harness --ref <tag>`, install `harness`, trust the project, review the plugin hooks; note openai/codex#19372).
- Step 6 OpenSpec: Claude as today; Codex `openspec init --tools codex`, then keep only `.agents/skills/openspec-{propose,archive-change,update-change,sync-specs}` and `.openspec-target`:

```sh
find .agents/skills -mindepth 1 -maxdepth 1 -name 'openspec-*' ! -name openspec-propose ! -name openspec-archive-change ! -name openspec-update-change ! -name openspec-sync-specs -exec rm -r {} +
```

  Copilot per F11.
- Step 8 verification: per selected agent, `rm -rf ./harness-guard-probe` is refused with `BLOCKED by harness guard (rm-rf)`; Claude and Copilot: `git push origin <default branch>` asks (decline); Codex: it prompts through `.codex/rules` (decline); the agent lists the harness skills and the two (Codex: three) subagents.
- Step 9: record each selected agent's version.
- "Updating": from 0.4.x, `copier update` asks `agents` (default `[claude]`); `.gitignore` and `ci.yml` change when another agent is added.

- [ ] **Step 2: README (English) and README.ja.md**

- Intro: "A product-development harness for Claude Code, OpenAI Codex CLI and GitHub Copilot CLI …".
- "What you get" table: Copier column lists `.codex/`, `.github/copilot/`, `.github/copilot-instructions.md`, `.harness/env.json` per selected agent.
- New section "Agents" after "What the hooks do": the support matrix (rows guard, ask-gate, lint-on-edit, test-on-stop, subagents, skills, OpenSpec, permissions/sandbox, auto-install; columns Claude Code, Codex, Copilot CLI) with the gaps from spec §5.2 and §6: Codex hooks cannot ask (rules prompt for every `git push`, not only protected branches); Codex network is off with no host allowlist; Copilot CLI has no repository permissions or sandbox; Copilot PostToolUse cannot block (lint feedback is context); `.harness/env.json` only the PO edits and never carries the guard relaxations; versions verified (F15).
- Configuration: `HARNESS_*` for Codex and Copilot come from `.harness/env.json`; environment wins.
- Quick start: `--data` / question `agents`; per-agent install pointer to `harness:adopt`.
- Security notes: Codex and Copilot plugin hooks run with your privileges too; trust review in Codex.
- `README.ja.md`: the same changes in Japanese, same commit.

- [ ] **Step 3: CHANGELOG**

Add at the top:

```markdown
## [Unreleased]

### Added

- Codex CLI and GitHub Copilot CLI support. Copier question `agents` (`claude`, `codex`, `copilot`; default `claude`) renders each selected agent's files: `.codex/config.toml`, `.codex/rules/harness.rules`, `.codex/agents/harness-*.toml` (generated from the plugin agents by `scripts/gen-codex-agents.sh`), `.github/copilot/settings.json`, `.github/copilot-instructions.md`, and `.harness/env.json` for hook settings.
- Hooks accept Codex `apply_patch` and Copilot CLI payloads: `guard` checks every path a patch writes (its body is not a command), `lint-on-edit` lints every patched file; new guard rule `harness-env` refuses access to `.harness/env.json`.
- `docs/harness/models.md` has a section per agent; `harness:execute`, `harness:workflow` and `harness:design` name each agent's mechanics in per-agent tables.

### Changed

- `lint-on-edit` reports failures as JSON `decision: block` with `additionalContext` instead of exit 2 (Claude Code behavior is the same: the agent must fix the file).
- Template CI job `check`: with Codex or Copilot selected, the OpenSpec step also rejects `.agents/skills/openspec-*` other than the four the harness uses; the context-budget step counts the selected agents' instruction files.
- `.claude/` and `CLAUDE.md` render only when `claude` (`.claude/rules/` also for `copilot`) is selected.
```

- [ ] **Step 4: Maintainer `AGENTS.md`**

Add a layout row: `| scripts/ | maintainer tools (gen-codex-agents.sh); not shipped |`, and a rule line: "After editing `plugins/harness/agents/*.md`, run `bash scripts/gen-codex-agents.sh`; `tests/codex-agents.sh` fails otherwise."

- [ ] **Step 5: Full suite**

Run: `bash tests/all.sh`
Expected: `all: ok`.

- [ ] **Step 6: Manual smoke per agent (PO present for prompts)**

Render `agents=[claude, codex, copilot]` into a scratch repo with `lint_cmd` and `test_cmd` set to a fake linter / `false`, install the plugin from this working tree in each agent (local marketplace path), and record in the ledger, per agent: guard blocks `rm -rf ./probe`; `git push origin main` asks (Claude, Copilot) or prompts via rules (Codex); writing a file the fake linter rejects makes the agent fix it; a failing test keeps the agent working; the harness skills and subagents are listed; Claude Code still shows the ask prompt with the Task 5 output (if changed). Any failure becomes a fix task before the PR.

- [ ] **Step 7: Commit**

```sh
git add -A plugins/harness/skills/adopt README.md README.ja.md CHANGELOG.md AGENTS.md
git commit -m "docs: adopt, README and CHANGELOG for Codex and Copilot CLI support"
```

---

## Self-review notes

- Spec coverage: §5.1/5.2 → Tasks 2–5; §5.3 → Tasks 2–5 tests; §6.1 → Task 7; §6.2 files → Tasks 7–10; `.harness/env.json` → Tasks 4, 8; §6.3 → Tasks 8–10, 12; §7 → Tasks 11–12; M5 → Task 6; M8 / CHANGELOG → Task 12; criterion 3 → Task 7 Step 5, repeated in Task 9 Step 2; Task 10 Step 3 keeps the `[claude]` CI step unchanged.
- Values from the spike are named F1–F15 and are the only deferred inputs; each consuming step says which finding it reads and that the marker must be replaced before commit.
