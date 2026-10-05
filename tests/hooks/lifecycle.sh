#!/usr/bin/env bash
# shellcheck disable=SC2016 # assertions are single-quoted on purpose: expect() evals them later
# Behavior tests for lint-on-edit.sh and test-on-stop.sh in throwaway git repositories,
# and for every hook when jq is missing.
# HOOKS_DIR overrides the script directory (used by mutate.sh).
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
# shellcheck source=../lib.sh
. "$repo/tests/lib.sh"
setup_git_env
HOOKS_DIR=${HOOKS_DIR:-$repo/plugins/harness/scripts}
HOOK_BASH=${HOOK_BASH:-bash} # e.g. /bin/bash to test macOS bash 3.2
R="$TMP_ROOT/proj"
git init -q "$R" && git -C "$R" commit -q --allow-empty -m init
mkdir -p "$R/src" "$R/docs"
LINTER="$TMP_ROOT/linter.sh"
cat > "$LINTER" <<'EOF'
#!/usr/bin/env bash
# fake linter: records its argument, fails when the file contains BAD
printf '%s\n' "$1" >> "$(dirname "$0")/lint.log"
! grep -q BAD "$1"
EOF
chmod +x "$LINTER"

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
stop() { # <extra-json> [env args: VAR=value | -u VAR ...] -> sets rc, out
  local extra=$1
  shift
  # shellcheck disable=SC2034 # read by the eval in expect()
  out=$(jq -nc --arg d "$R" --argjson x "$extra" '{hook_event_name:"Stop",cwd:$d} + $x' \
    | env "$@" "$HOOK_BASH" "$HOOKS_DIR/test-on-stop.sh" 2>/dev/null)
  rc=$?
}
expect() { if eval "$2"; then ok; else ng "$1 (rc=$rc)"; fi; }

echo ok > "$R/src/good.ts"
echo BAD > "$R/src/bad.ts"
echo BAD > "$R/docs/x.md"

lint "$R/src/bad.ts" -u HARNESS_LINT_CMD
expect l-unset '[ $rc = 0 ] && [ -z "$err" ] && [ -z "$out" ]'
lint "$R/src/bad.ts" HARNESS_LINT_CMD=
expect l-empty '[ $rc = 0 ] && [ -z "$out" ]'
lint "$R/src/good.ts" HARNESS_LINT_CMD="$LINTER"
expect l-good '[ $rc = 0 ] && [ -z "$out" ] && grep -q good.ts "$TMP_ROOT/lint.log"'
lint "$R/src/bad.ts" HARNESS_LINT_CMD="$LINTER"
expect l-bad '[ $rc = 0 ] && blocked "lint failed after editing src/bad.ts"'
lint "$R/docs/x.md" HARNESS_LINT_CMD="$LINTER"
expect l-doc-skip '[ $rc = 0 ] && [ -z "$out" ]'
lint "$R/src/bad.ts" HARNESS_LINT_CMD="$LINTER" HARNESS_LINT_PATTERN='\.py$'
expect l-pattern-skip '[ $rc = 0 ] && [ -z "$out" ]'
lint "$R/src/bad.ts" HARNESS_LINT_CMD="$LINTER" HARNESS_LINT_PATTERN='\.ts$'
expect l-pattern-hit '[ $rc = 0 ] && blocked "src/bad.ts"'
evil="$R/src/a\$(touch pwned) b.ts"
echo ok > "$evil"
lint "$evil" HARNESS_LINT_CMD="$LINTER"
expect l-no-injection '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$R/pwned" ] && [ ! -e "$R/src/pwned" ] && grep -qF "a\$(touch pwned) b.ts" "$TMP_ROOT/lint.log"'
echo BAD > "$TMP_ROOT/outside.ts"
lint "$TMP_ROOT/outside.ts" HARNESS_LINT_CMD="$LINTER"
expect l-outside-repo '[ $rc = 0 ] && [ -z "$out" ]'
# A path through a symlinked directory (e.g. macOS /tmp -> /private/tmp) must resolve to the
# repo-relative path (the anchored pattern only matches then).
ln -s "$R" "$TMP_ROOT/proj-link"
lint "$TMP_ROOT/proj-link/src/bad.ts" HARNESS_LINT_CMD="$LINTER" HARNESS_LINT_PATTERN="^src/"
expect l-symlinked-path '[ $rc = 0 ] && blocked "src/bad.ts"'
lint "$R/src/good.ts" HARNESS_LINT_CMD="$LINTER" HARNESS_LINT_PATTERN='('
expect l-bad-lint-pattern '[ $rc = 2 ] && printf "%s" "$err" | grep -q "invalid HARNESS_LINT_PATTERN"'
lint "$R/src/good.ts" HARNESS_LINT_CMD="$LINTER" HARNESS_DOC_PATTERN='('
expect l-bad-doc-pattern '[ $rc = 2 ] && printf "%s" "$err" | grep -q "invalid HARNESS_DOC_PATTERN"'
P='*** Begin Patch\n*** Update File: src/good.ts\n@@\n-a\n+ok\n*** Add File: src/bad.ts\n+BAD\n*** End Patch'
lintpatch "$R" "$P" HARNESS_LINT_CMD="$LINTER"
expect l-patch-multi '[ $rc = 0 ] && blocked "src/bad.ts" && ! printf "%s" "$out" | grep -q "good.ts" && grep -q "src/good.ts" "$TMP_ROOT/lint.log"'
lintpatch "$R" '*** Begin Patch\n*** Delete File: src/gone.ts\n*** End Patch' HARNESS_LINT_CMD="$LINTER"
expect l-patch-delete '[ $rc = 0 ] && [ -z "$out" ]'
lintpatch "$R" '*** Begin Patch\n*** Update File: src/x.ts\n*** Move to: src/bad.ts\n@@\n-a\n+b\n*** End Patch' HARNESS_LINT_CMD="$LINTER"
expect l-patch-move '[ $rc = 0 ] && blocked "src/bad.ts"'
lintpatch "$R" '*** Begin Patch\n*** Update File: docs/x.md\n@@\n-a\n+b\n*** End Patch' HARNESS_LINT_CMD="$LINTER"
expect l-patch-doc '[ $rc = 0 ] && [ -z "$out" ]'
# Codex writes absolute paths after the header
lintpatch "$R" "*** Begin Patch\\n*** Update File: $R/src/bad.ts\\n@@\\n-a\\n+b\\n*** End Patch" HARNESS_LINT_CMD="$LINTER"
expect l-patch-absolute '[ $rc = 0 ] && blocked "lint failed after editing src/bad.ts"'
lintj "$(jq -nc --arg p "$R/src/bad.ts" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{path:$p}}')" HARNESS_LINT_CMD="$LINTER"
expect l-copilot-path '[ $rc = 0 ] && blocked "src/bad.ts"'
# Copilot: PostToolUse carries tool_result; only a top-level additionalContext reaches the model, and decision:block would hide the output
lintj "$(jq -nc --arg p "$R/src/bad.ts" --arg d "$R" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{path:$p},tool_result:{resultType:"success"},cwd:$d}')" HARNESS_LINT_CMD="$LINTER"
expect l-copilot-context '[ $rc = 0 ] && printf "%s" "$out" | jq -e ".additionalContext | contains(\"lint failed after editing src/bad.ts\")" >/dev/null && printf "%s" "$out" | jq -e "(has(\"decision\") | not) and (has(\"hookSpecificOutput\") | not)" >/dev/null'
# Copilot's Edit sends tool_input as a string holding patch text, with paths relative to cwd
lintj "$(jq -nc --arg d "$R" --arg c "$(printf '*** Begin Patch\n*** Update File: src/bad.ts\n@@\n-a\n+b\n*** End Patch')" '{hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:$c,tool_result:{resultType:"success"},cwd:$d}')" HARNESS_LINT_CMD="$LINTER"
expect l-copilot-string-patch '[ $rc = 0 ] && printf "%s" "$out" | jq -e ".additionalContext | contains(\"src/bad.ts\")" >/dev/null && printf "%s" "$out" | jq -e "has(\"decision\") | not" >/dev/null'

M="$TMP_ROOT/ran"
T="touch $M"
stop '{}' -u HARNESS_TEST_CMD
expect s-unset '[ $rc = 0 ] && [ -z "$out" ]'
stop '{}' HARNESS_TEST_CMD=
expect s-empty '[ $rc = 0 ] && [ -z "$out" ]'
git -C "$R" add -A && git -C "$R" commit -q -m files
stop '{}' HARNESS_TEST_CMD="$T"
expect s-clean '[ $rc = 0 ] && [ ! -e "$M" ]'
echo more >> "$R/docs/x.md"
stop '{}' HARNESS_TEST_CMD="$T"
expect s-doc-only '[ ! -e "$M" ]'
echo more >> "$R/src/good.ts"
stop '{"stop_hook_active":true}' HARNESS_TEST_CMD="$T"
expect s-active '[ ! -e "$M" ]'
stop '{}' HARNESS_TEST_CMD="$T"
expect s-runs '[ -e "$M" ] && [ -z "$out" ]'
stop '{}' HARNESS_TEST_CMD="echo boom; exit 3"
expect s-fail-blocks '[ "$(printf "%s" "$out" | jq -r .decision)" = block ] && printf "%s" "$out" | jq -r .reason | grep -q boom'
rm -f "$M"
git -C "$R" add -A && git -C "$R" commit -q -m more
echo new > "$R/src/untracked.ts"
stop '{}' HARNESS_TEST_CMD="$T"
expect s-untracked '[ -e "$M" ]'
rm -f "$M"
stop '{}' HARNESS_TEST_CMD="$T" HARNESS_DOC_PATTERN='('
expect s-bad-doc-pattern '[ ! -e "$M" ] && [ "$(printf "%s" "$out" | jq -r .decision)" = block ] && printf "%s" "$out" | jq -r .reason | grep -q "invalid HARNESS_DOC_PATTERN" && printf "%s" "$out" | jq -r .reason | grep -qF ".claude/settings.json" && printf "%s" "$out" | jq -r .reason | grep -qF ".harness/env.json"'
# Copilot CLI Stop payloads carry stop_reason and stop_hook_active (spike F4)
echo change >> "$R/src/good.ts"
stop '{"hook_event_name":"Stop","stop_reason":"end_turn","stop_hook_active":false}' HARNESS_TEST_CMD=false
expect s-copilot-shape '[ $rc = 0 ] && printf "%s" "$out" | jq -e ".decision == \"block\" and (.reason | length > 0)" >/dev/null'
stop '{"hook_event_name":"Stop","stop_reason":"end_turn","stop_hook_active":true}' HARNESS_TEST_CMD=false
expect s-copilot-active '[ $rc = 0 ] && [ -z "$out" ]'
echo ok > "$R/src/good.ts"

# .harness/env.json supplies HARNESS_* for agents without a per-repository hook environment; the payload's cwd locates it
mkdir -p "$R/.harness"
printf '%s\n' "{\"HARNESS_LINT_CMD\":\"$LINTER\",\"HARNESS_TEST_CMD\":\"false\"}" > "$R/.harness/env.json"
envlint() { # [env args]: Write with cwd
  lintj "$(jq -nc --arg p "$R/src/bad.ts" --arg d "$R" '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$p},tool_response:{filePath:$p},cwd:$d}')" "$@"
}
envlint -u HARNESS_LINT_CMD
expect e-lint-from-file '[ $rc = 0 ] && blocked "src/bad.ts"'
envlint HARNESS_LINT_CMD=
expect e-empty-env-wins '[ $rc = 0 ] && [ -z "$out" ]'
echo change >> "$R/src/good.ts"
stop '{}' -u HARNESS_TEST_CMD
expect e-test-from-file '[ $rc = 0 ] && printf "%s" "$out" | jq -e ".decision == \"block\"" >/dev/null'
git -C "$R" checkout -q -- src/good.ts
rm -rf "$R/.harness"

# ask-gate looks up the current branch once per directory: 16 KiB of bare `git push;` on a
# feature branch took 8 s with one lookup per segment (29 s at 64 KiB, over the 10 s timeout).
F="$TMP_ROOT/feat"
git init -q "$F" && git -C "$F" commit -q --allow-empty -m init && git -C "$F" checkout -q -b feature/x
pushes=$(printf 'git push;%.0s' $(seq 1 1820))
start=$SECONDS
out=$(jq -nc --arg c "$pushes" --arg d "$F" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
  | "$HOOK_BASH" "$HOOKS_DIR/ask-gate.sh" 2>/dev/null)
rc=$?
took=$((SECONDS - start))
# MUTATE_NO_TIMING=1 (set by mutate.sh): mutants run in parallel, so wall-clock time says nothing
expect "a-push-cache (took ${took}s)" '[ $rc = 0 ] && [ -z "$out" ] && { [ "${MUTATE_NO_TIMING:-}" = 1 ] || [ "$took" -le 3 ]; }'

# lib/parse.sh missing, failing to source, or not defining the parser: guard blocks, ask-gate asks.
BP="$TMP_ROOT/bad-parser"
badparser() { # <missing|broken|empty> <script> -> sets rc, out, err
  rm -rf "$BP" && cp -R "$HOOKS_DIR" "$BP"
  case "$1" in
    missing) rm "$BP/lib/parse.sh" ;;
    broken) printf 'normalize() {\n' > "$BP/lib/parse.sh" ;;
    empty) : > "$BP/lib/parse.sh" ;;
  esac
  # shellcheck disable=SC2034 # read by the eval in expect()
  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | "$HOOK_BASH" "$BP/$2.sh" 2>"$TMP_ROOT/bp.err")
  rc=$?
  # shellcheck disable=SC2034 # read by the eval in expect()
  err=$(cat "$TMP_ROOT/bp.err")
}
for v in missing broken empty; do
  badparser "$v" guard
  expect "bp-guard-$v" '[ $rc = 2 ] && printf "%s" "$err" | grep -q "BLOCKED by harness guard (bad-parser)"'
  badparser "$v" ask-gate
  expect "bp-ask-gate-$v" '[ $rc = 0 ] && printf "%s" "$out" | grep -q "harness ask-gate (bad-parser)"'
done

# Copilot CLI form of a block (R14): exit 0, JSON with only the nested deny (top-level
# permissionDecision keys make Codex fail open when COPILOT_CLI=1 is inherited)
# shellcheck disable=SC2034 # cop and coprc are read by the eval in expect()
cop=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf build"},"cwd":"/"}' | COPILOT_CLI=1 "$(command -v "$HOOK_BASH")" "$HOOKS_DIR/guard.sh" 2>"$TMP_ROOT/cop.err")
# shellcheck disable=SC2034 # read by the eval in expect()
coprc=$?
expect cp-form-json '[ $coprc = 0 ] && printf "%s" "$cop" | jq -e "keys == [\"hookSpecificOutput\"] and .hookSpecificOutput.permissionDecision == \"deny\" and .hookSpecificOutput.hookEventName == \"PreToolUse\" and (.hookSpecificOutput.permissionDecisionReason | startswith(\"BLOCKED by harness guard (rm-rf)\"))" >/dev/null'

# Subagent monitoring: subagent-start records each subagent under $CLAUDE_PLUGIN_DATA/runs/<session>/<agent>/,
# subagent-stop marks it done and checks the reply contract of harness agents, watchdog reports stalls.
PD="$TMP_ROOT/pdata"
SESS="$TMP_ROOT/sessions/s1.jsonl" # the session transcript; the subagent's is s1/subagents/agent-<id>.jsonl
mkdir -p "$TMP_ROOT/sessions/s1/subagents"
rec() { printf '%s' "$PD/runs/s1/$1"; }
sub() { # <script> <json> [env args] -> sets rc, out
  local s=$1 j=$2
  shift 2
  # shellcheck disable=SC2034 # read by the eval in expect()
  out=$(printf '%s' "$j" | env CLAUDE_PLUGIN_DATA="$PD" "$@" "$HOOK_BASH" "$HOOKS_DIR/$s.sh" 2>/dev/null)
  rc=$?
}
start() { # <agent id> [extra json] [env args]
  local id=$1 x=${2:-'{}'}
  shift 2 2>/dev/null || shift $#
  sub subagent-start "$(jq -nc --arg id "$id" --arg tp "$SESS" --argjson x "$x" \
    '{hook_event_name:"SubagentStart",session_id:"s1",transcript_path:$tp,agent_id:$id,agent_type:"harness:implementer",cwd:"/"} + $x')" "$@"
}
start a1
expect sa-record '[ $rc = 0 ] && [ -z "$out" ] && [ "$(cat "$(rec a1)/transcript")" = "$TMP_ROOT/sessions/s1/subagents/agent-a1.jsonl" ] && grep -Eq "^[0-9]+$" "$(rec a1)/start" && [ "$(cat "$(rec a1)/type")" = harness:implementer ]'
start a2 '{}' CLAUDE_PLUGIN_DATA=
expect sa-no-data '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$(rec a2)" ]'
start '../../escape'
expect sa-unsafe-id '[ $rc = 0 ] && [ ! -e "$PD/escape" ] && [ ! -e "$PD/runs/escape" ]'
start a3 '{"transcript_path":null}'
expect sa-no-transcript '[ $rc = 0 ] && [ -e "$(rec a3)/start" ] && [ ! -s "$(rec a3)/transcript" ]'
echo stall > "$(rec a1)/alerted" && : > "$(rec a1)/done"
start a1
expect sa-restart-resets '[ ! -e "$(rec a1)/done" ] && [ ! -e "$(rec a1)/alerted" ]'

ART="$R/report.md"
: > "$ART"
good="STATUS: ok
ARTIFACT: report.md
SUMMARY:
- task 1 committed (abc123..def456), tests green"
stopj() { # <agent type> <message> [extra json] [env args]
  local t=$1 m=$2 x=${3:-'{}'}
  shift 3 2>/dev/null || shift $#
  sub subagent-stop "$(jq -nc --arg t "$t" --arg m "$m" --arg d "$R" --arg tp "$SESS" --argjson x "$x" \
    '{hook_event_name:"SubagentStop",session_id:"s1",transcript_path:$tp,agent_id:"a1",agent_type:$t,cwd:$d,stop_hook_active:false,last_assistant_message:$m,background_tasks:[]} + $x')" "$@"
}
sentback() { printf '%s' "$out" | jq -e --arg w "$1" '.decision == "block" and (.reason | contains($w))' >/dev/null 2>&1; }
stopj harness:implementer "$good"
expect sp-done '[ $rc = 0 ] && [ -z "$out" ] && [ -e "$(rec a1)/done" ]'
rm -f "$(rec a1)/done"
stopj harness:implementer "$good" '{}' CLAUDE_PLUGIN_DATA=
expect sp-done-needs-data '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$(rec a1)/done" ]'
# Claude Code also sends SubagentStop for internal agents that had no SubagentStart: no record for them
stopj general-purpose "x" '{"agent_id":"ghost"}'
expect sp-no-record '[ $rc = 0 ] && [ ! -e "$(rec ghost)" ]'
stopj general-purpose "Here is a long free-form answer."
expect sp-other-type '[ $rc = 0 ] && [ -z "$out" ] && [ -e "$(rec a1)/done" ]'
stopj harness:implementer "I implemented task 1. $good"
expect sp-first-line '[ $rc = 0 ] && sentback "STATUS:"'
stopj harness:implementer "STATUS: ok
SUMMARY:
- done"
expect sp-no-artifact '[ $rc = 0 ] && sentback "ARTIFACT:"'
stopj harness:implementer "STATUS: ok
ARTIFACT: missing.md
SUMMARY:
- done"
expect sp-artifact-missing '[ $rc = 0 ] && sentback "missing.md"'
stopj harness:implementer "STATUS: ok
ARTIFACT: $ART
SUMMARY:
- an absolute path counts"
expect sp-artifact-absolute '[ $rc = 0 ] && [ -z "$out" ]'
stopj harness:implementer "$good
- 2
- 3
- 4
- 5
- 6"
expect sp-too-long '[ $rc = 0 ] && sentback "8 lines"'
stopj harness:reviewer "$good"
expect sp-reviewer-verdict '[ $rc = 0 ] && sentback "VERDICT:"'
stopj harness:reviewer "STATUS: ok
VERDICT: Needs fixes
ARTIFACT: report.md
SUMMARY:
- Critical 0, Important 2, Minor 1"
expect sp-reviewer-ok '[ $rc = 0 ] && [ -z "$out" ]'
stopj harness:reviewer "STATUS: partial
ARTIFACT: report.md
SUMMARY:
- turn budget spent after spec compliance"
expect sp-reviewer-partial '[ $rc = 0 ] && [ -z "$out" ]'
stopj harness:implementer "free text" '{"stop_hook_active":true}'
expect sp-active '[ $rc = 0 ] && [ -z "$out" ]'
stopj harness:implementer "free text" '{"stop_hook_active":null}'
expect sp-active-absent '[ $rc = 0 ] && [ -z "$out" ]'
stopj harness:implementer "free text" '{"background_tasks":[{"id":"b1"}]}'
expect sp-background '[ $rc = 0 ] && [ -z "$out" ]'

# watchdog: one pass (--once) over the session's records, with small limits
wd() { # [env args] -> sets rc, out
  # shellcheck disable=SC2034 # read by the eval in expect()
  out=$(env CLAUDE_CODE_SESSION_ID=s1 HARNESS_WATCHDOG_IDLE=100 HARNESS_WATCHDOG_MAX=1000 "$@" "$HOOK_BASH" "$HOOKS_DIR/watchdog.sh" "$PD" --once 2>/dev/null)
  rc=$?
}
age() { perl -e 'my $t = time - shift; utime $t, $t, @ARGV' "$@"; } # <seconds ago> <file>...
mkrec() { # <session> <agent> <started seconds ago> [transcript]
  local d="$PD/runs/$1/$2"
  rm -rf "$d" && mkdir -p "$d"
  echo $(($(date +%s) - $3)) > "$d/start"
  printf '%s\n' "${4:-}" > "$d/transcript"
  echo harness:implementer > "$d/type"
}
rm -rf "$PD/runs"
TR="$TMP_ROOT/sessions/s1/subagents/agent-w1.jsonl"
: > "$TR"
mkrec s1 w1 300 "$TR"
wd
expect wd-quiet '[ $rc = 0 ] && [ -z "$out" ]'
age 200 "$TR"
wd
expect wd-stall '[ $rc = 0 ] && printf "%s" "$out" | grep -q "STALL harness:implementer w1" && [ "$(printf "%s\n" "$out" | wc -l)" -eq 1 ] && [ "$(cat "$PD/runs/s1/w1/alerted")" = stall ]'
wd
expect wd-once '[ -z "$out" ]'
: > "$TR"
wd
expect wd-rearm '[ -z "$out" ] && [ ! -e "$PD/runs/s1/w1/alerted" ]'
: > "$PD/runs/s1/w1/done"
age 200 "$TR"
wd
expect wd-skip-done '[ -z "$out" ]'
mkrec s1 w1 2000 "$TR"
: > "$TR"
wd
expect wd-timeout '[ $rc = 0 ] && printf "%s" "$out" | grep -q "TIMEOUT harness:implementer w1" && [ "$(cat "$PD/runs/s1/w1/alerted")" = timeout ]'
wd
expect wd-timeout-once '[ -z "$out" ]'
mkrec s1 w1 200 "$TMP_ROOT/sessions/s1/subagents/agent-none.jsonl"
wd
expect wd-no-transcript-file '[ $rc = 0 ] && printf "%s" "$out" | grep -q "STALL harness:implementer w1"'
mkrec s1 w1 10 "$TR"
age 500 "$TR"
wd
expect wd-resumed '[ -z "$out" ]' # an older transcript belongs to the run before the restart
mkrec s1 w1 200
wd
expect wd-unknown-transcript '[ -z "$out" ]' # without a transcript path only the run limit applies
echo soon > "$PD/runs/s1/w1/start"
wd
expect wd-bad-start '[ $rc = 0 ] && [ -z "$out" ]'
rm -rf "$PD/runs/s1/w1"
mkrec s2 x1 200 "$TR"
age 200 "$TR"
wd
expect wd-other-session '[ -z "$out" ]'
wd CLAUDE_CODE_SESSION_ID=
expect wd-all-sessions 'printf "%s" "$out" | grep -q "STALL harness:implementer x1"'
mkdir -p "$PD/runs/old"
perl -e 'my $t = time - 8 * 86400; utime $t, $t, @ARGV' "$PD/runs/old"
wd
expect wd-prune '[ ! -e "$PD/runs/old" ] && [ -e "$PD/runs/s2" ]'

# jq missing: a PATH with only the tools the hooks need, minus jq.
NOJQ="$TMP_ROOT/nojq-bin"
mkdir -p "$NOJQ"
for t in bash cat dirname basename git grep sed awk tr sort tail head env pwd; do
  p=$(command -v "$t") && ln -s "$p" "$NOJQ/$t"
done
hb=$(command -v "$HOOK_BASH")
if env PATH="$NOJQ" "$hb" -c 'command -v jq' >/dev/null 2>&1; then ng "nojq PATH still finds jq"; else ok; fi
nojq() { # <script> <stdin> [env args] -> sets rc, out, err
  local s=$1 in=$2
  shift 2
  # shellcheck disable=SC2034 # read by the eval in expect()
  out=$(printf '%s' "$in" | env PATH="$NOJQ" "$@" "$hb" "$HOOKS_DIR/$s.sh" 2>"$TMP_ROOT/nojq.err")
  rc=$?
  # shellcheck disable=SC2034 # read by the eval in expect()
  err=$(cat "$TMP_ROOT/nojq.err")
}
nojq guard '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
expect nj-guard-blocks '[ $rc = 2 ] && printf "%s" "$err" | grep -q "BLOCKED by harness guard (no-jq): jq is required"'
nojq guard '{"tool_name":"Bash","tool_input":{"command":"ls"}}' COPILOT_CLI=1
expect nj-guard-copilot-json '[ $rc = 0 ] && printf "%s" "$out" | jq -e "keys == [\"hookSpecificOutput\"] and .hookSpecificOutput.permissionDecision == \"deny\" and .hookSpecificOutput.hookEventName == \"PreToolUse\" and (.hookSpecificOutput.permissionDecisionReason | startswith(\"BLOCKED by harness guard (no-jq): jq is required\"))" >/dev/null'
nojq ask-gate '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
expect nj-ask-gate-asks '[ $rc = 0 ] && printf "%s" "$out" | grep -q "\"permissionDecision\":\"ask\"" && printf "%s" "$out" | grep -q "harness ask-gate (no-jq)"'
nojq lint-on-edit "{\"tool_input\":{\"file_path\":\"$R/src/bad.ts\"}}" HARNESS_LINT_CMD="$LINTER"
expect nj-lint-skips '[ $rc = 0 ] && printf "%s" "$err" | grep -q "jq not found; lint skipped"'
rm -f "$M"
nojq test-on-stop "{\"cwd\":\"$R\"}" HARNESS_TEST_CMD="$T"
expect nj-stop-skips '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$M" ] && printf "%s" "$err" | grep -q "jq not found; tests skipped"'
nojq subagent-start '{"session_id":"s1","agent_id":"nj","transcript_path":"/x.jsonl"}' CLAUDE_PLUGIN_DATA="$PD"
expect nj-subagent-start '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$PD/runs/s1/nj" ]'
nojq subagent-stop '{"session_id":"s1","agent_id":"nj","agent_type":"harness:implementer","stop_hook_active":false,"last_assistant_message":"x"}' CLAUDE_PLUGIN_DATA="$PD"
expect nj-subagent-stop '[ $rc = 0 ] && [ -z "$out" ]'

report "lifecycle"
