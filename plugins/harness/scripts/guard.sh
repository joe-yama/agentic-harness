#!/usr/bin/env bash
# harness guard — PreToolUse hook (Bash, Monitor and file tools).
# Hard-blocks destructive commands and secret access: exit 2, reason on stderr.
# Each rule sits between "# rule:<id>" and "# end:<id>"; tests/hooks/mutate.sh disables
# one rule at a time and expects a test case to fail.
set -u
set -f # tokens are split on whitespace below; never glob-expand them

input=$(cat)
# rule:no-jq
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED by harness guard (no-jq): jq is required (brew install jq / apt-get install jq)" >&2
  exit 2
fi
# end:no-jq
# shellcheck source=lib/parse.sh
. "$(dirname "$0")/lib/parse.sh"

deny() {
  printf 'BLOCKED by harness guard (%s): %s\n' "$1" "$2" >&2
  exit 2
}

# rule:bad-input
printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || deny bad-input "the hook input is not a JSON object, so the command could not be checked"
# end:bad-input

check_path() {
  p=$1
  base=${p##*/}
  # rule:env-file-path
  case "$base" in
    .env.example) ;;
    .env | .env.*) deny env-file ".env files are off limits; read values from the environment: $p" ;;
  esac
  # end:env-file-path
  # rule:secrets-dir-path
  case "$p" in
    */.ssh | */.ssh/* | */.aws | */.aws/* | */.gnupg | */.gnupg/* | */.config/op | */.config/op/* | */.config/gh | */.config/gh/*)
      deny secrets-dir "credential directories are off limits: $p" ;;
  esac
  # end:secrets-dir-path
  return 0
}

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
case "$tool" in
  Bash | Monitor)
    raw=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
    # rule:too-large
    # the parser is quadratic in the length; a timed-out hook would let the command through
    [ "$(($(printf '%s' "$raw" | wc -c)))" -le 65536 ] \
      || deny too-large "the command is over 64 KiB; write it to a file and run the file"
    # end:too-large
    cmd=$(normalize "$raw")

    # rule:rm-rf
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      rec=0 force=0
      for tok in $seg; do
        case "$tok" in
          --) break ;;
          --recursive) rec=1 ;;
          --force) force=1 ;;
          --*) ;;
          -*)
            case "$tok" in *[rR]*) rec=1 ;; esac
            case "$tok" in *f*) force=1 ;; esac
            ;;
        esac
      done
      [ "$rec" = 1 ] && [ "$force" = 1 ] && deny rm-rf "recursive forced rm; ask the PO before deleting"
    done <<EOF
$(segments rm)
EOF
    # end:rm-rf

    # rule:force-push
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      for tok in $seg; do
        case "$tok" in
          --force | --force=* | --force-with-lease | --force-with-lease=* | --force-if-includes)
            deny force-push "force push rewrites shared history" ;;
          --*) ;;
          -*f*) deny force-push "force push rewrites shared history" ;;
          +?*) deny force-push "a +refspec is a force push" ;;
        esac
      done
    done <<EOF
$(git_segments push)
EOF
    # end:force-push

    # rule:discard
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      sub='' whole=0 staged=0 worktree=0 del=0 force=0
      for tok in $seg; do
        case "$tok" in reset | clean | checkout | restore | branch) [ -z "$sub" ] && sub=$tok && continue ;; esac
        [ -n "$sub" ] || continue
        case "$sub:$tok" in
          reset:--hard | reset:--merge) deny discard "git reset $tok discards work" ;;
          clean:--force | clean:-*f*) deny discard "git clean -f deletes untracked files" ;;
          checkout:. | checkout:./ | restore:. | restore:./) whole=1 ;;
          restore:--staged | restore:-S) staged=1 ;;
          restore:--worktree | restore:-W) worktree=1 ;;
          branch:--delete) del=1 ;;
          branch:--force) force=1 ;;
          branch:--*) ;;
          branch:-*D*) deny discard "git branch -D drops unmerged work" ;;
          branch:-*)
            case "$tok" in *d*) del=1 ;; esac
            case "$tok" in *f*) force=1 ;; esac
            ;;
        esac
      done
      [ "$sub" = checkout ] && [ "$whole" = 1 ] && deny discard "git checkout of the whole tree discards changes"
      if [ "$sub" = restore ] && [ "$whole" = 1 ] && { [ "$staged" = 0 ] || [ "$worktree" = 1 ]; }; then
        deny discard "git restore of the whole tree discards changes"
      fi
      [ "$del" = 1 ] && [ "$force" = 1 ] && deny discard "git branch --delete --force drops unmerged work"
    done <<EOF
$(git_segments '(reset|clean|checkout|restore|branch)')
EOF
    # end:discard

    # rule:no-verify
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      sub='' prev=''
      for tok in $seg; do
        case "$tok" in --no-verify | --no-gpg-sign) deny no-verify "skipping hooks or signing is not allowed" ;; esac
        if [ -z "$sub" ]; then
          # the subcommand is the first word after git that is neither an option nor an option's value
          case "$prev:$tok" in
            *:*git | *:-* | -C:* | -c:* | --git-dir:* | --work-tree:* | --namespace:* | --super-prefix:* | --config-env:*) ;;
            *) sub=$tok ;;
          esac
          prev=$tok
          continue
        fi
        case "$sub:$tok" in commit:--*) ;; commit:-*n*) deny no-verify "git commit -n skips hooks" ;; esac
      done
    done <<EOF
$(git_segments '[a-z][a-z-]*')
EOF
    # end:no-verify

    # rule:env-file
    # Split on whitespace, the quote marker, redirections and separators; judge each word's basename.
    for word in $(printf '%s' "$cmd" | tr "=<>();|&\`\001" '           '); do
      name=${word##*/}
      case "$name" in
        .env.example) ;;
        .env | .env.*)
          printf '%s' "$name" | grep -Eq '^\.env(\.[A-Za-z0-9_-]+)*$' \
            && deny env-file ".env files are off limits; read values from the environment" ;;
      esac
    done
    # end:env-file

    # rule:secrets-dir
    if printf '%s' "$cmd" | tr '\001' ' ' | grep -Eq "(~|\\\$HOME|\\\$\\{HOME\\}|/Users/[^/[:space:]]+|/home/[^/[:space:]]+)/\.(ssh|aws|gnupg|config/op|config/gh)([/[:space:]]|$)"; then
      deny secrets-dir "credential directories are off limits"
    fi
    # end:secrets-dir

    # rule:pipe-shell
    flat=$(printf '%s' "$cmd" | tr '\001' ' ')
    if printf '%s' "$flat" | grep -Eq "(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh([[:space:]]|$)" \
      || printf '%s' "$flat" | grep -Eq "(ba|z|da|k)?sh[[:space:]]+-c[[:space:]]+\\\$\((curl|wget)"; then
      deny pipe-shell "piping a download into a shell is not allowed"
    fi
    # end:pipe-shell
    ;;
  Read | Edit | Write | MultiEdit | NotebookEdit)
    check_path "$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
    ;;
esac
exit 0
