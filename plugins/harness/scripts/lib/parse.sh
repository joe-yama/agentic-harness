#!/usr/bin/env bash
# shellcheck disable=SC2154 # $cmd is set by the script that sources this file
# Command parsing shared by guard.sh and ask-gate.sh. Source it; it defines functions only.
# The hooks match command text: they are a tripwire for agent mistakes, not a sandbox.

# normalize <command>
# Prints the command with backslash-newline continuations joined and quotes removed ($'...' too),
# where blanks inside quotes become \001 so a quoted argument stays one token ("my dir", "-m msg").
# A quoted string that follows `-c` (sh -c, bash -lc) or `eval` is a command itself: its content is
# normalized the same way (recursively, for nested quotes) and printed on extra lines, so it is
# checked like any other command. Other quoted strings (commit messages, grep patterns, Issue
# bodies) stay data. Quote state is tracked across newlines.
normalize() {
  local nl=$'\n' s=$1
  # rule:parse-continuation
  s=${s//\\$nl/ }
  # end:parse-continuation
  printf '%s\n' "$s" | awk -v sq="'" -v dq='"' '
    function norm(s, depth,    out, q, inner, extra, i, ch, w, prevw, lead) {
      out = ""; q = ""; inner = ""; extra = ""; w = ""; prevw = ""; lead = ""
      for (i = 1; i <= length(s); i++) {
        ch = substr(s, i, 1)
        if (q == "") {
          # rule:parse-dollar-quote
          if (ch == "$" && substr(s, i + 1, 1) == sq) continue
          # end:parse-dollar-quote
          if (ch == sq || ch == dq) { q = ch; inner = ""; lead = (w != "" ? w : prevw); continue }
          out = out ch
          if (ch == " " || ch == "\t" || ch == "\n" || ch == ";" || ch == "&" || ch == "|") {
            if (w != "") prevw = w
            w = ""
          } else w = w ch
        } else if (ch == q) {
          q = ""
          # rule:parse-command-string
          if (depth < 4 && (lead ~ /^-[A-Za-z]*c$/ || lead == "eval")) extra = extra "\n" norm(inner, depth + 1)
          # end:parse-command-string
          w = w "q"
        } else {
          inner = inner ch
          # rule:parse-quoted-blank
          if (ch == " " || ch == "\t" || ch == "\n") ch = "\001"
          # end:parse-quoted-blank
          out = out ch
        }
      }
      if (q != "" && depth < 4 && (lead ~ /^-[A-Za-z]*c$/ || lead == "eval")) extra = extra "\n" norm(inner, depth + 1)
      return out extra
    }
    { all = all $0 "\n" }
    END { printf "%s\n", norm(all, 0) }'
}

# Command-word boundary, and an optional path prefix on the command word (/bin/rm, /usr/bin/git).
B='' P='' GOPT=''
# rule:parse-word-boundary
B='(^|[;&|(`[:space:]\\])'
# end:parse-word-boundary
# rule:parse-path-prefix
P='([^[:space:];&|(`]*/)?'
# end:parse-path-prefix
# git global options that may precede the subcommand: -C <dir>, -c <k=v>, --git-dir <dir>, -P, --no-pager, --x=y.
# rule:parse-git-options
GOPT='([[:space:]]+(-[Cc][[:space:]]+[^[:space:];&|]+|--(git-dir|work-tree|namespace|super-prefix|config-env)[[:space:]]+[^[:space:];&|]+|-[A-Za-z]+|--[a-z-]+(=[^[:space:];&|]+)?))*'
# end:parse-git-options

# segments <word-regex>: each "<word> args..." up to the next ; & | separator, one per line. Reads $cmd.
segments() { printf '%s\n' "$cmd" | grep -oE "${B}${P}$1([[:space:]]+[^;&|]*)?" || true; }

# git_segments <subcommand-regex>: each "git [global options] <subcommand> args..." segment. Reads $cmd.
git_segments() { printf '%s\n' "$cmd" | grep -oE "${B}${P}git${GOPT}[[:space:]]+$1([[:space:]]+[^;&|]*)?" || true; }
