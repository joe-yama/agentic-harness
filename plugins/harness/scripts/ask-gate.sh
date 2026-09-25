#!/usr/bin/env bash
# harness ask-gate — PreToolUse hook (Bash and Monitor).
# Routes policy-sensitive commands to the human with permissionDecision "ask".
# Prints nothing otherwise, deferring to permission rules and auto mode. Hooks can only
# tighten: an "ask" from here cannot be overridden by an allow rule.
# Each rule sits between "# rule:<id>" and "# end:<id>" (see tests/hooks/mutate.sh).
set -u
set -f

ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"harness ask-gate (%s): %s"}}\n' "$1" "$2"
  exit 0
}

input=$(cat)
# rule:no-jq
command -v jq >/dev/null 2>&1 || ask no-jq "jq is missing, so the command could not be checked"
# end:no-jq
# rule:bad-input
printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || ask bad-input "the hook input is not a JSON object, so the command could not be checked"
# end:bad-input
case "$(printf '%s' "$input" | jq -r '.tool_name // ""')" in Bash | Monitor) ;; *) exit 0 ;; esac
# shellcheck source=lib/parse.sh
. "$(dirname "$0")/lib/parse.sh"
raw=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
# rule:too-large
[ "$(($(printf '%s' "$raw" | wc -c)))" -le 65536 ] \
  || ask too-large "the command is over 64 KiB and was not checked; write it to a file and run the file"
# end:too-large
cmd=$(normalize "$raw")
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
[ -n "$cwd" ] || cwd=$(pwd)
protected=${HARNESS_PROTECTED_BRANCHES:-main}
Q=$(printf '\001')

is_protected() {
  for b in $protected; do [ "$1" = "$b" ] && return 0; done
  return 1
}

# rule:protected-push
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  dir=$cwd after=0 skip=0 prev='' npos=0 second=''
  for tok in $seg; do
    if [ "$after" = 0 ]; then
      if [ "$prev" = "-C" ]; then
        d=${tok//$Q/ }
        case "$d" in /*) dir=$d ;; *) dir=$cwd/$d ;; esac
      fi
      [ "$tok" = push ] && after=1
      prev=$tok
      continue
    fi
    if [ "$skip" = 1 ]; then
      skip=0
      continue
    fi
    case "$tok" in
      --delete | -d | --all | --mirror | --prune) ask protected-push "git push $tok needs the PO" ;;
      -o | --push-option | --repo | --receive-pack | --exec)
        skip=1
        continue ;;
      -*) continue ;;
      [0-9]\>* | \>* | [0-9]\<* | \<* | \&\>*) continue ;;
    esac
    npos=$((npos + 1))
    [ "$npos" = 2 ] && second=$tok
    [ "$npos" -ge 2 ] || continue
    case "$tok" in :*) ask protected-push "deleting a remote branch needs the PO" ;; esac
    target=${tok#*:}
    target=${target#refs/heads/}
    is_protected "$target" && ask protected-push "push to protected branch $target needs the PO"
  done
  if [ "$npos" -le 1 ] || [ "$second" = HEAD ] || [ "$second" = @ ]; then
    cur=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null || true)
    [ -n "$cur" ] && is_protected "$cur" && ask protected-push "push from protected branch $cur needs the PO"
  fi
done <<EOF
$(git_segments push)
EOF
# end:protected-push

# rule:worktree-force
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  rm=0 force=0
  for tok in $seg; do
    case "$tok" in
      remove) rm=1 ;;
      -f) force=1 ;;
      --*) is_abbrev "$tok" --force && force=1 ;;
    esac
  done
  [ "$rm" = 1 ] && [ "$force" = 1 ] && ask worktree-force "git worktree remove --force discards uncommitted work"
done <<EOF
$(git_segments worktree)
EOF
# end:worktree-force

# rule:lockfile-install
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  pm='' sub='' skip=0 frozen=0
  for tok in $seg; do
    if [ -z "$pm" ]; then
      pm=${tok##*[;&|(\`\\/]}
      continue
    fi
    if [ "$skip" = 1 ]; then
      skip=0
      continue
    fi
    case "$tok" in
      --frozen-lockfile | --immutable | --locked | --frozen) frozen=1 ;;
      -C | --dir | --prefix | --filter | -F | --cwd | --directory | --project | --manifest-path) skip=1 ;;
      -*) ;;
      *) [ -z "$sub" ] && sub=$tok ;;
    esac
  done
  why="$pm $sub can change the lockfile; dependency changes need the PO"
  case "$pm:$sub" in
    pnpm:install | pnpm:i | bun:install | bun:i | yarn:install | yarn: | uv:sync)
      [ "$frozen" = 1 ] || ask lockfile-install "$why" ;;
    pnpm:add | pnpm:update | pnpm:up | pnpm:upgrade | pnpm:remove | pnpm:rm | pnpm:un | pnpm:uninstall \
      | npm:install | npm:i | npm:add | npm:update | npm:up | npm:uninstall | npm:un | npm:rm | npm:remove \
      | yarn:add | yarn:remove | yarn:up | yarn:upgrade | bun:add | bun:remove | bun:rm | bun:update \
      | uv:add | uv:remove | uv:pip | pip:install | pip3:install | cargo:add | cargo:remove | cargo:update)
      ask lockfile-install "$why" ;;
  esac
done <<EOF
$(segments '(pnpm|npm|yarn|bun|uv|pip3?|cargo)')
EOF
# end:lockfile-install

exit 0
