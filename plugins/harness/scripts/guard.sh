#!/usr/bin/env bash
# harness guard — PreToolUse hook (Bash and file tools).
# Hard-blocks destructive commands and secret access: exit 2, reason on stderr.
# Each rule sits between "# rule:<id>" and "# end:<id>"; tests/hooks/mutate.sh disables
# one rule at a time and expects a test case to fail.
set -u
set -f # tokens are split on whitespace below; never glob-expand them

input=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED by harness guard: jq is required (brew install jq / apt-get install jq)" >&2
  exit 2
fi

deny() {
  printf 'BLOCKED by harness guard (%s): %s\n' "$1" "$2" >&2
  exit 2
}

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
B='(^|[;&|(`[:space:]])' # command-word boundary

# Print each "<word> ..." segment of the command up to the next ; & | separator.
segments() { printf '%s' "$cmd" | grep -oE "${B}$1([[:space:]]+[^;&|]*)?" || true; }
# Same for git subcommands, allowing global options (-C dir, -c k=v, --no-pager ...).
git_segments() {
  printf '%s' "$cmd" | grep -oE "${B}git([[:space:]]+(-[Cc][[:space:]]+[^[:space:];&|]+|--[a-z-]+(=[^[:space:];&|]+)?))*[[:space:]]+$1([[:space:]]+[^;&|]*)?" || true
}

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

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

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
      for tok in $seg; do
        case "$tok" in --hard | --merge) deny discard "git reset $tok discards work" ;; esac
      done
    done <<EOF
$(git_segments reset)
EOF
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      for tok in $seg; do
        case "$tok" in
          --force) deny discard "git clean --force deletes untracked files" ;;
          --*) ;;
          -*f*) deny discard "git clean -f deletes untracked files" ;;
        esac
      done
    done <<EOF
$(git_segments clean)
EOF
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      for tok in $seg; do
        case "$tok" in . | ./) deny discard "git checkout of the whole tree discards changes" ;; esac
      done
    done <<EOF
$(git_segments checkout)
EOF
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      whole=0 staged=0 worktree=0
      for tok in $seg; do
        case "$tok" in
          . | ./) whole=1 ;;
          --staged | -S) staged=1 ;;
          --worktree | -W) worktree=1 ;;
        esac
      done
      if [ "$whole" = 1 ] && { [ "$staged" = 0 ] || [ "$worktree" = 1 ]; }; then
        deny discard "git restore of the whole tree discards changes"
      fi
    done <<EOF
$(git_segments restore)
EOF
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      for tok in $seg; do
        case "$tok" in --*) ;; -*D*) deny discard "git branch -D drops unmerged work" ;; esac
      done
    done <<EOF
$(git_segments branch)
EOF
    # end:discard

    # rule:no-verify
    if printf '%s' "$cmd" | grep -Eq "${B}git[[:space:]][^;&|]*--no-(verify|gpg-sign)([[:space:]=]|$)"; then
      deny no-verify "skipping hooks or signing is not allowed"
    fi
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      for tok in $seg; do
        case "$tok" in --*) ;; -*n*) deny no-verify "git commit -n skips hooks" ;; esac
      done
    done <<EOF
$(git_segments commit)
EOF
    # end:no-verify

    # rule:env-file
    # Split on whitespace, quotes, redirections and separators; judge each word's basename.
    for word in $(printf '%s' "$cmd" | tr "=<>\"'();|&\`" '           '); do
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
    if printf '%s' "$cmd" | grep -Eq "(~|\\\$HOME|\\\$\\{HOME\\}|/Users/[^/[:space:]]+|/home/[^/[:space:]]+)/\.(ssh|aws|gnupg|config/op|config/gh)([/[:space:]\"']|$)"; then
      deny secrets-dir "credential directories are off limits"
    fi
    # end:secrets-dir

    # rule:pipe-shell
    if printf '%s' "$cmd" | grep -Eq "(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh([[:space:]]|$)" \
      || printf '%s' "$cmd" | grep -Eq "(ba|z|da|k)?sh[[:space:]]+-c[[:space:]]+[\"']?\\\$\((curl|wget)"; then
      deny pipe-shell "piping a download into a shell is not allowed"
    fi
    # end:pipe-shell
    ;;
  Read | Edit | Write | MultiEdit | NotebookEdit)
    check_path "$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // ""')"
    ;;
esac
exit 0
