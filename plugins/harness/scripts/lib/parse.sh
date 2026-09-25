#!/usr/bin/env bash
# shellcheck disable=SC2154 # $cmd is set by the script that sources this file
# Command parsing shared by guard.sh and ask-gate.sh. Source it; it defines functions only.
# The hooks match command text: they are a tripwire for agent mistakes, not a sandbox.

# normalize <command>
# Prints the command with backslash-newline continuations joined and quotes removed, where
# blanks inside quotes become \001 so a quoted argument stays one token ("my dir", "-m msg").
# Then prints the content of every quoted string on its own line, so command strings passed
# to `sh -c '...'` or `bash -c "..."` are checked like commands too.
normalize() {
  local nl=$'\n'
  printf '%s\n' "${1//\\$nl/ }" | awk -v sq="'" -v dq='"' '
    {
      out = ""; q = ""; inner = ""; extra = ""
      for (i = 1; i <= length($0); i++) {
        ch = substr($0, i, 1)
        if (q == "") {
          if (ch == sq || ch == dq) { q = ch; inner = ""; continue }
          out = out ch
        } else if (ch == q) {
          q = ""
          extra = extra inner "\n"
        } else {
          inner = inner ch
          out = out ((ch == " " || ch == "\t") ? "\001" : ch)
        }
      }
      if (q != "") extra = extra inner "\n"
      printf "%s\n%s", out, extra
    }'
}

# Command-word boundary, and an optional path prefix on the command word (/bin/rm, /usr/bin/git).
B='(^|[;&|(`[:space:]\\])'
P='([^[:space:];&|(`]*/)?'
# git global options that may precede the subcommand: -C <dir>, -c <k=v>, --git-dir <dir>, -P, --no-pager, --x=y.
GOPT='([[:space:]]+(-[Cc][[:space:]]+[^[:space:];&|]+|--(git-dir|work-tree|namespace|super-prefix|config-env)[[:space:]]+[^[:space:];&|]+|-[A-Za-z]+|--[a-z-]+(=[^[:space:];&|]+)?))*'

# segments <word-regex>: each "<word> args..." up to the next ; & | separator, one per line. Reads $cmd.
segments() { printf '%s\n' "$cmd" | grep -oE "${B}${P}$1([[:space:]]+[^;&|]*)?" || true; }

# git_segments <subcommand-regex>: each "git [global options] <subcommand> args..." segment. Reads $cmd.
git_segments() { printf '%s\n' "$cmd" | grep -oE "${B}${P}git${GOPT}[[:space:]]+$1([[:space:]]+[^;&|]*)?" || true; }
