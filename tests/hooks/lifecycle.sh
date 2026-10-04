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
expect s-bad-doc-pattern '[ ! -e "$M" ] && [ "$(printf "%s" "$out" | jq -r .decision)" = block ] && printf "%s" "$out" | jq -r .reason | grep -q "invalid HARNESS_DOC_PATTERN"'
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

# Copilot CLI form of a block: exit 0, JSON with top-level and nested deny, nothing on stderr
# shellcheck disable=SC2034 # cop and coprc are read by the eval in expect()
cop=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf build"},"cwd":"/"}' | COPILOT_CLI=1 "$(command -v "$HOOK_BASH")" "$HOOKS_DIR/guard.sh" 2>"$TMP_ROOT/cop.err")
# shellcheck disable=SC2034 # read by the eval in expect()
coprc=$?
expect cp-form-json '[ $coprc = 0 ] && printf "%s" "$cop" | jq -e ".permissionDecision == \"deny\" and .hookSpecificOutput.permissionDecision == \"deny\" and .hookSpecificOutput.hookEventName == \"PreToolUse\" and (.permissionDecisionReason | startswith(\"BLOCKED by harness guard (rm-rf)\")) and (.hookSpecificOutput.permissionDecisionReason == .permissionDecisionReason)" >/dev/null'

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
expect nj-guard-copilot-json '[ $rc = 0 ] && printf "%s" "$out" | jq -e ".permissionDecision == \"deny\" and .hookSpecificOutput.permissionDecision == \"deny\" and .hookSpecificOutput.hookEventName == \"PreToolUse\" and (.permissionDecisionReason | contains(\"(no-jq)\"))" >/dev/null'
nojq ask-gate '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
expect nj-ask-gate-asks '[ $rc = 0 ] && printf "%s" "$out" | grep -q "\"permissionDecision\":\"ask\"" && printf "%s" "$out" | grep -q "harness ask-gate (no-jq)"'
nojq lint-on-edit "{\"tool_input\":{\"file_path\":\"$R/src/bad.ts\"}}" HARNESS_LINT_CMD="$LINTER"
expect nj-lint-skips '[ $rc = 0 ] && printf "%s" "$err" | grep -q "jq not found; lint skipped"'
rm -f "$M"
nojq test-on-stop "{\"cwd\":\"$R\"}" HARNESS_TEST_CMD="$T"
expect nj-stop-skips '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$M" ] && printf "%s" "$err" | grep -q "jq not found; tests skipped"'

report "lifecycle"
