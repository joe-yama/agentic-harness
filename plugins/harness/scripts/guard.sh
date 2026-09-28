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
deny() {
  printf 'BLOCKED by harness guard (%s): %s\n' "$1" "$2" >&2
  exit 2
}

# shellcheck source=lib/parse.sh
. "$(dirname "$0")/lib/parse.sh" 2>/dev/null
parsed=$?
# rule:bad-parser
if [ "$parsed" != 0 ] || ! declare -F normalize is_abbrev segments git_segments >/dev/null; then
  deny bad-parser "lib/parse.sh is missing or broken, so the command could not be checked; reinstall the plugin"
fi
# end:bad-parser

# rule:bad-input
printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || deny bad-input "the hook input is not a JSON object, so the command could not be checked"
# end:bad-input

check_path() {
  p=$1 lp=$1
  # rule:path-case
  # names match case-insensitively, as on macOS and Windows filesystems
  lp=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  # end:path-case
  base=${lp##*/}
  # rule:env-file-path
  case "$base" in
    .env.example) ;;
    .env | .env.*) deny env-file ".env files are off limits; read values from the environment: $p" ;;
  esac
  # end:env-file-path
  # rule:secrets-dir-path
  case "$lp" in
    */.ssh | */.ssh/* | */.aws | */.aws/* | */.gnupg | */.gnupg/* | */.config/op | */.config/op/* | */.config/gh | */.config/gh/*)
      deny secrets-dir "credential directories are off limits: $p" ;;
  esac
  # end:secrets-dir-path
  return 0
}

# resolve <absolute path without //>: sets res to the path with its deepest existing directory
# resolved by cd -P (symlinks followed) and the rest appended as written. One pass from the root:
# below a missing directory nothing exists, and cutting the path per segment from the end is
# quadratic. cd in this shell, not $(...): a fork per operand runs past the hook timeout on a long
# command. The caller restores the directory.
resolve() {
  local p=$1 cur='' s tail IFS=/
  case "$p" in /*) ;; *) return 1 ;; esac
  case "$p" in *//*) return 1 ;; esac
  for s in $p; do
    [ -n "$s" ] || continue
    [ -d "$cur/$s" ] || break
    cur=$cur/$s
  done
  tail=${p:${#cur}}
  tail=${tail%/}
  CDPATH='' cd -P -- "${cur:-/}" 2>/dev/null || return 1
  res=${PWD%/}$tail
  [ -n "$res" ] || res=/
}

# rm_ok <rm segment>: true when HARNESS_RM_RF_ALLOW allows the segment (rm_pre holds the resolved
# prefixes): at least one operand, and every operand a plain absolute path that, resolved, equals
# a prefix or lies under it.
rm_ok() {
  local first=1 ends=0 n=0 tok pre m
  [ -n "$rm_pre" ] || return 1
  for tok in $1; do
    if [ "$first" = 1 ]; then
      first=0 # the command word (rm, /bin/rm, \rm)
      continue
    fi
    if [ "$ends" = 0 ]; then
      case "$tok" in
        --) ends=1; continue ;;
        -*) continue ;;
      esac
    fi
    n=$((n + 1))
    # rule:rm-rf-allow-bsd
    # BSD rm (macOS) reads every word after the first operand as an operand (rm -rf /a -x)
    ends=1
    # end:rm-rf-allow-bsd
    # rule:rm-rf-allow-chars
    # no glob, ~, $, backtick, brace, backslash, quoted blank or redirection: the text is the path
    case "$tok" in *[!A-Za-z0-9._/@%+=,-]*) return 1 ;; esac
    # end:rm-rf-allow-chars
    # rule:rm-rf-allow-dotdot
    case "$tok/" in */../*) return 1 ;; esac
    case "$tok" in *//*) return 1 ;; esac
    # end:rm-rf-allow-dotdot
    # rule:rm-rf-allow-length
    # a very deep path costs time to resolve; a timed-out hook would let the whole command through
    [ "${#tok}" -le 1024 ] || return 1
    # end:rm-rf-allow-length
    # rule:rm-rf-allow-resolve
    # a symlink under the prefix may point anywhere: compare where the path really is
    resolve "$tok" || return 1
    tok=$res
    # end:rm-rf-allow-resolve
    m=0
    for pre in $rm_pre; do
      case "$tok" in "$pre" | "$pre"/*) m=1 ;; esac
    done
    [ "$m" = 1 ] || return 1
  done
  [ "$n" -gt 0 ]
}

# lease_push_ok <git push segment>: true when HARNESS_ALLOW_LEASE_PUSH=1 allows the segment's
# --force-with-lease: every refspec is <src>:refs/heads/<branch> with an unprotected branch, every
# lease is refs/heads/<branch>:<hex 7-40>, and leases and destinations name the same refs. Written
# in full: git resolves a short name its own way (heads/main is refs/heads/main, v1 may be a tag).
# No option that pushes more than the named branches.
lease_push_ok() {
  local tok prev='' sub=0 npos=0 skip=0 dests=' ' leased=' ' refs='' s d r e b protected
  protected=${HARNESS_PROTECTED_BRANCHES:-main} # space-separated, as in ask-gate
  for tok in $1; do
    if [ "$sub" = 0 ]; then
      # rule:lease-config
      # git -c / --config-env can turn on mirror or a forcing refspec for this push
      case "$tok" in -c | --config-env | --config-env=*) return 1 ;; esac
      # end:lease-config
      if [ "$tok" = push ]; then
        case "$prev" in -C | --git-dir | --work-tree | --namespace | --super-prefix) ;; *) sub=1 ;; esac
      fi
      prev=$tok
      continue
    fi
    if [ "$skip" = 1 ]; then
      skip=0
      continue
    fi
    case "$tok" in
      --force-with-lease=*)
        refs="$refs ${tok#--force-with-lease=}"
        continue ;;
      -o | --push-option | --receive-pack | --exec)
        skip=1
        continue ;;
      --*)
        # rule:lease-options
        is_abbrev "$tok" --all --mirror --tags --delete --prune --repo && return 1
        # end:lease-options
        continue ;;
      -*)
        # rule:lease-delete-flag
        case "$tok" in *d*) return 1 ;; esac
        # end:lease-delete-flag
        continue ;;
      [0-9]\>* | \>* | [0-9]\<* | \<*) continue ;;
    esac
    npos=$((npos + 1))
    [ "$npos" = 1 ] && continue # the remote
    # rule:lease-refspec
    # <src>:refs/heads/<branch>: no deletion (:x), no short or tag destination (tag v1, heads/main),
    # and no shell expansion in either side ($P can expand to +HEAD, {a,b} to two refspecs)
    case "$tok" in ?*:refs/heads/?*) ;; *) return 1 ;; esac
    s=${tok%%:*}
    d=${tok#*:}
    b=${d#refs/heads/}
    case "$s" in [~-]* | *[!A-Za-z0-9._/@^~-]*) return 1 ;; esac
    case "$b" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
    # end:lease-refspec
    # rule:lease-protected
    for e in $protected; do [ "$b" = "$e" ] && return 1; done
    # end:lease-protected
    dests="$dests$d "
  done
  # rule:lease-includes
  # --force-if-includes alone is not a lease
  [ -n "$refs" ] || return 1
  # end:lease-includes
  for r in $refs; do
    # rule:lease-shape
    case "$r" in *:*) ;; *) return 1 ;; esac
    e=${r#*:}
    case "$e" in '' | *[!0-9a-fA-F]*) return 1 ;; esac
    [ "${#e}" -ge 7 ] && [ "${#e}" -le 40 ] || return 1
    # end:lease-shape
    r=${r%%:*}
    # rule:lease-match
    # the lease's full ref is one of the destinations (all refs/heads/<branch>)
    case "$dests" in *" $r "*) ;; *) return 1 ;; esac
    # end:lease-match
    leased="$leased$r "
  done
  # rule:lease-cover
  # every destination has its own lease
  for d in $dests; do
    case "$leased" in *" $d "*) ;; *) return 1 ;; esac
  done
  # end:lease-cover
  return 0
}

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')
case "$tool" in
  Bash | Monitor)
    raw=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
    # rule:too-large
    # the parser is quadratic in the length; a timed-out hook would let the command through
    # bytes, not ${#raw}: in a UTF-8 locale that counts characters (3x the bytes for CJK), and awk is byte-based
    [ "$(($(printf '%s' "$raw" | wc -c)))" -le 65536 ] \
      || deny too-large "the command is over 64 KiB; write it to a file and run the file"
    # end:too-large
    cmd=$(normalize "$raw")

    # rule:rm-rf
    rm_pre='' pwd0=$PWD # resolve() changes directory; restored after the rule
    # rule:rm-rf-allow
    # HARNESS_RM_RF_ALLOW=<prefix>[:<prefix>...]: absolute directories where rm -rf may run
    rest=${HARNESS_RM_RF_ALLOW:-}
    while [ -n "$rest" ]; do
      pre=${rest%%:*}
      case "$rest" in *:*) rest=${rest#*:} ;; *) rest='' ;; esac
      pre=${pre%/}
      # rule:rm-rf-allow-shape
      # ignored: not absolute, /, fewer than 2 segments, a . / .. / empty segment, or an odd character
      case "$pre" in /*/?*) ;; *) continue ;; esac
      case "$pre/" in */./* | */../* | *//*) continue ;; esac
      case "$pre" in *[!A-Za-z0-9._/@%+=,-]*) continue ;; esac
      # end:rm-rf-allow-shape
      # rule:rm-rf-allow-resolve-prefix
      # operands are compared resolved, so the prefixes are too (/tmp is /private/tmp on macOS)
      resolve "$pre" || continue
      pre=$res
      # end:rm-rf-allow-resolve-prefix
      # rule:rm-rf-allow-resolved-shape
      # a prefix that resolves to / or to a single segment (a symlink to /usr) is ignored
      case "$pre" in /*/?*) ;; *) continue ;; esac
      case "$pre" in *[!A-Za-z0-9._/@%+=,-]*) continue ;; esac
      # end:rm-rf-allow-resolved-shape
      rm_pre="$rm_pre $pre"
    done
    # rule:rm-rf-allow-indirect
    # rm run by another command (xargs, find -exec, sudo, sh -c '…') gets operands the text does not
    # show: then no segment is allowed. Quoted blanks count as blanks here.
    if [ -n "$rm_pre" ] && printf '%s\n' "$cmd" | tr '\001' ' ' | awk '
      {
        n = split($0, pc, /[;&|(`]/)
        for (i = 1; i <= n; i++) {
          k = split(pc[i], w)
          for (j = 2; j <= k; j++) {
            c = w[j]
            sub(/.*\//, "", c)
            sub(/^\\+/, "", c)
            if (c == "rm") { found = 1; exit }
          }
        }
      }
      END { exit !found }'; then
      rm_pre=''
    fi
    # end:rm-rf-allow-indirect
    # rule:rm-rf-allow-ln
    # a link made in the same command (ln -s / <prefix>/x && rm -rf <prefix>/x/usr) does not exist
    # yet when the path is resolved: any ln word (/bin/ln, sudo ln, sh -c 'ln …') turns the allow off
    if [ -n "$rm_pre" ] && printf '%s\n' "$cmd" | tr '\001' ' ' | awk '
      {
        n = split($0, pc, /[;&|(`]/)
        for (i = 1; i <= n; i++) {
          k = split(pc[i], w)
          for (j = 1; j <= k; j++) {
            c = w[j]
            sub(/.*\//, "", c)
            sub(/^\\+/, "", c)
            if (c == "ln") { found = 1; exit }
          }
        }
      }
      END { exit !found }'; then
      rm_pre=''
    fi
    # end:rm-rf-allow-ln
    # end:rm-rf-allow
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      rec=0 force=0
      for tok in $seg; do
        case "$tok" in
          --) break ;;
          --*)
            is_abbrev "$tok" --recursive && rec=1
            is_abbrev "$tok" --force && force=1
            ;;
          -*)
            case "$tok" in *[rR]*) rec=1 ;; esac
            case "$tok" in *f*) force=1 ;; esac
            ;;
        esac
      done
      if [ "$rec" = 1 ] && [ "$force" = 1 ] && ! rm_ok "$seg"; then
        deny rm-rf "recursive forced rm; ask the PO before deleting"
      fi
    done <<EOF
$(segments rm)
EOF
    CDPATH='' cd -- "$pwd0" 2>/dev/null || :
    # end:rm-rf

    # rule:force-push
    lease_ok=0
    # rule:lease-push
    # HARNESS_ALLOW_LEASE_PUSH=1: --force-with-lease=refs/heads/<branch>:<sha> may pass (lease_push_ok)
    [ "${HARNESS_ALLOW_LEASE_PUSH:-}" = 1 ] && lease_ok=1
    # end:lease-push
    if [ "$lease_ok" = 1 ]; then
      # rule:lease-env-config
      # GIT_CONFIG_COUNT / _KEY_* / _PARAMETERS / _GLOBAL anywhere in the command can make the push
      # a mirror or forcing one, as can a git config in the same command
      case "$cmd" in *GIT_CONFIG*) lease_ok=0 ;; esac
      # end:lease-env-config
      # rule:lease-git-config
      [ -n "$(git_segments config)" ] && lease_ok=0
      # end:lease-git-config
    fi
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      lease=0
      for tok in $seg; do
        case "$tok" in
          --force-with-lease=* | --force-if-includes)
            [ "$lease_ok" = 1 ] || deny force-push "force push rewrites shared history"
            lease=1 ;;
          --force | --force=* | --force-with-lease)
            deny force-push "force push rewrites shared history" ;;
          --*)
            is_abbrev "$tok" --force --force-with-lease --force-if-includes \
              && deny force-push "force push rewrites shared history"
            ;;
          -*f*) deny force-push "force push rewrites shared history" ;;
          +?*) deny force-push "a +refspec is a force push" ;;
        esac
      done
      if [ "$lease" = 1 ] && ! lease_push_ok "$seg"; then
        deny force-push "force push rewrites shared history; HARNESS_ALLOW_LEASE_PUSH allows only --force-with-lease=<branch>:<sha> to named, unprotected branches"
      fi
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
          reset:--*) is_abbrev "$tok" --hard --merge && deny discard "git reset $tok discards work" ;;
          clean:--*) is_abbrev "$tok" --force && deny discard "git clean --force deletes untracked files" ;;
          clean:-*f*) deny discard "git clean -f deletes untracked files" ;;
          checkout:. | checkout:./ | restore:. | restore:./) whole=1 ;;
          restore:--staged | restore:-S) staged=1 ;;
          restore:--worktree | restore:-W) worktree=1 ;;
          branch:--*)
            is_abbrev "$tok" --delete && del=1
            is_abbrev "$tok" --force && force=1
            ;;
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
        is_abbrev "$tok" --no-verify --no-gpg-sign && deny no-verify "skipping hooks or signing is not allowed"
        if [ -z "$sub" ]; then
          if [ "$prev" = -c ]; then
            # git -c core.hooksPath=<dir> (keys are case-insensitive) replaces the hooks; a case
            # pattern, not a tr per value: a fork per word runs past the hook timeout on a long command
            case "${tok%%=*}" in
              [Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh])
                deny no-verify "git -c core.hooksPath skips the repository's hooks" ;;
            esac
            # rule:git-alias
            # git -c alias.<name>=!<command> defines a shell alias, which hides the command it runs
            case "$tok" in [Aa][Ll][Ii][Aa][Ss].*=!*) deny git-alias "git -c alias.<name>=!... hides the command it runs" ;; esac
            # end:git-alias
          fi
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
    # HUSKY=0 before a git command (among other assignments, or after env) turns husky's hooks off
    if printf '%s\n' "$cmd" | grep -Eq "(^|[;&|(\`[:space:]])HUSKY=0([[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*)*[[:space:]]+${P}git([[:space:]]|$)"; then
      deny no-verify "HUSKY=0 skips the repository's hooks"
    fi
    # end:no-verify

    # rule:env-file
    # Lowercase, split on whitespace, the quote marker, redirections, separators and ":" (HEAD:.env),
    # and judge each word's basename. A glob (.env*, .env.?) counts: the shell expands it to the file.
    ecmd=$cmd
    # rule:jq-filter
    # the first non-option argument of jq / yq / gojq is a filter (jq '.env' f), not a file; only
    # when jq is the command word (grep jq .env reads .env), and never across a separator
    ecmd=$(printf '%s\n' "$cmd" | sed -E "s#((^|[;&|(\`])[[:space:]]*${P}(jq|yq|gojq)([[:space:]]+-[^[:space:];&|<>()]*)*)[[:space:]]+[^[:space:];&|<>()]+#\1#g")
    # end:jq-filter
    # One pipeline, one word per line: a grep per word, or ${word##*/} on a long word (quadratic in
    # bash), runs past the hook timeout on a long command.
    # shellcheck disable=SC2020 # tr maps characters one by one on purpose
    printf '%s\n' "$ecmd" | tr '[:upper:]' '[:lower:]' \
      | tr "=<>();|&\`:\001 \t" '\n\n\n\n\n\n\n\n\n\n\n\n\n' | sed 's#.*/##' \
      | grep -Ev '^\.env\.example$' | grep -Eq '^\.env([.*?[][]a-z0-9_.*?!^[-]*)?$' \
      && deny env-file ".env files are off limits; read values from the environment"
    # end:env-file

    # rule:secrets-dir
    # Case-insensitive, after ~/, ~user/, $HOME/, ${HOME}/, /root/, /Users/<u>/, /home/<u>/, or at
    # the start of a word (cd ~ && cat .ssh/id_rsa). So a word starting with .aws/ inside a project
    # is refused too (accepted false positive); project/.aws/config passes.
    if printf '%s' "$cmd" | tr '\001' ' ' | grep -Eiq "(~[^/[:space:]]*/|\\\$HOME/|\\\$\\{HOME\\}/|/root/|/Users/[^/[:space:]]+/|/home/[^/[:space:]]+/|(^|[[:space:]=<>();|&\`]))\.(ssh|aws|gnupg|config/op|config/gh)([/[:space:]]|$)"; then
      deny secrets-dir "credential directories are off limits"
    fi
    # end:secrets-dir

    # rule:pipe-shell
    # A download (curl / wget) reaching a shell: a later pipe stage whose command word, after sudo
    # and its options and any path prefix, is a shell; <(download) given to a shell, source or .;
    # and `download` / $(download) given to sh -c or eval. Quoted blanks are still \001 here, so a
    # quoted "curl x | sh" (an Issue body) is data; inside sh -c '…' it is checked on its own line.
    Q=$(printf '\001')
    if printf '%s\n' "$cmd" | awk '
      {
        gsub(/\|\|/, ";")
        gsub(/\|&/, "|")
        n = split($0, cmds, /[;&]/)
        for (i = 1; i <= n; i++) {
          m = split(cmds[i], st, "|")
          dl = 0
          for (j = 1; j <= m; j++) {
            if (dl) {
              k = split(st[j], w)
              x = 1
              if (w[x] ~ /(^|\/)sudo$/) {
                x++
                while (x <= k && w[x] ~ /^-/) {
                  if (w[x] ~ /^-[A-Za-z]*[ugCDhprT]$/) x++
                  x++
                }
              }
              c = w[x]
              sub(/.*\//, "", c)
              if (c ~ /^(ba|z|da|k)?sh$/) { found = 1; exit }
            }
            if (st[j] ~ /(^|[ \t(`\/])(curl|wget)([ \t]|$)/) dl = 1
          }
        }
      }
      END { exit !found }' \
      || printf '%s\n' "$cmd" | grep -Eq "${B}${P}((ba|z|da|k)?sh|source|\.)([[:space:]]+[^;&|<]*)?[[:space:]]*<\([[:space:]$Q]*${P}(curl|wget)([[:space:]$Q]|\))" \
      || printf '%s\n' "$cmd" | grep -Eq "((ba|z|da|k)?sh[[:space:]]+-[A-Za-z]*c([[:space:]]+-[^[:space:]]*)*|eval)[[:space:]]+(\\\$\(|\`)[[:space:]$Q]*${P}(curl|wget)"; then
      deny pipe-shell "piping a download into a shell is not allowed"
    fi
    # end:pipe-shell
    ;;
  Read | Edit | Write | MultiEdit | NotebookEdit)
    check_path "$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
    ;;
esac
exit 0
