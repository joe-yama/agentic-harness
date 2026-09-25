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

lint() { # <file> [env args: VAR=value | -u VAR ...] -> sets rc, err
  local f=$1
  shift
  # shellcheck disable=SC2034 # read by the eval in expect()
  err=$(jq -nc --arg p "$f" '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$p},tool_response:{filePath:$p}}' \
    | env "$@" "$HOOK_BASH" "$HOOKS_DIR/lint-on-edit.sh" 2>&1 >/dev/null)
  rc=$?
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
expect l-unset '[ $rc = 0 ] && [ -z "$err" ]'
lint "$R/src/bad.ts" HARNESS_LINT_CMD=
expect l-empty '[ $rc = 0 ]'
lint "$R/src/good.ts" HARNESS_LINT_CMD="$LINTER"
expect l-good '[ $rc = 0 ] && grep -q good.ts "$TMP_ROOT/lint.log"'
lint "$R/src/bad.ts" HARNESS_LINT_CMD="$LINTER"
expect l-bad '[ $rc = 2 ] && printf "%s" "$err" | grep -q "lint failed"'
lint "$R/docs/x.md" HARNESS_LINT_CMD="$LINTER"
expect l-doc-skip '[ $rc = 0 ]'
lint "$R/src/bad.ts" HARNESS_LINT_CMD="$LINTER" HARNESS_LINT_PATTERN='\.py$'
expect l-pattern-skip '[ $rc = 0 ]'
lint "$R/src/bad.ts" HARNESS_LINT_CMD="$LINTER" HARNESS_LINT_PATTERN='\.ts$'
expect l-pattern-hit '[ $rc = 2 ]'
evil="$R/src/a\$(touch pwned) b.ts"
echo ok > "$evil"
lint "$evil" HARNESS_LINT_CMD="$LINTER"
expect l-no-injection '[ $rc = 0 ] && [ ! -e "$R/pwned" ] && [ ! -e "$R/src/pwned" ] && grep -qF "a\$(touch pwned) b.ts" "$TMP_ROOT/lint.log"'
echo BAD > "$TMP_ROOT/outside.ts"
lint "$TMP_ROOT/outside.ts" HARNESS_LINT_CMD="$LINTER"
expect l-outside-repo '[ $rc = 0 ]'
# macOS: /tmp and /var are symlinks into /private; a path through the link must still resolve.
case "$R" in
  /private/*)
    lint "${R#/private}/src/bad.ts" HARNESS_LINT_CMD="$LINTER"
    expect l-symlinked-path '[ $rc = 2 ]' ;;
esac

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
expect nj-guard-blocks '[ $rc = 2 ] && printf "%s" "$err" | grep -q "jq is required"'
nojq ask-gate '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
expect nj-ask-gate-asks '[ $rc = 0 ] && printf "%s" "$out" | grep -q "\"permissionDecision\":\"ask\"" && printf "%s" "$out" | grep -q "harness ask-gate (no-jq)"'
nojq lint-on-edit "{\"tool_input\":{\"file_path\":\"$R/src/bad.ts\"}}" HARNESS_LINT_CMD="$LINTER"
expect nj-lint-skips '[ $rc = 0 ] && printf "%s" "$err" | grep -q "jq not found; lint skipped"'
rm -f "$M"
nojq test-on-stop "{\"cwd\":\"$R\"}" HARNESS_TEST_CMD="$T"
expect nj-stop-skips '[ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$M" ] && printf "%s" "$err" | grep -q "jq not found; tests skipped"'

report "lifecycle"
