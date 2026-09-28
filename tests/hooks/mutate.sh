#!/usr/bin/env bash
# Proves every guarded rule is covered: for each "# rule:<id>" block in the hook scripts and lib/,
# delete the block in a copy and require at least one test to fail. Control run first.
# A mutant that does not finish within MUTATE_TIMEOUT seconds (default 300) is reported as
# TIMED OUT, not counted as killed, and fails the run.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
src=${HOOKS_SRC:-$repo/plugins/harness/scripts}
limit=${MUTATE_TIMEOUT:-300}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# suite <hooks dir> [1]: both suites pass. A mutant only needs one failing case, so with the
# fail-fast argument each suite stops at its first failure; the verdict is the same.
suite() {
  HOOKS_DIR=$1 MUTATE_FAIL_FAST=${2:-} bash "$here/lifecycle.sh" >/dev/null 2>&1 \
    && HOOKS_DIR=$1 MUTATE_FAIL_FAST=${2:-} bash "$here/run.sh" >/dev/null 2>&1
}
# with_timeout <seconds> <command>...: runs the command in its own process group and, after
# <seconds>, sends TERM to the whole group (a hung hook included) and exits 124, like timeout(1).
# perl, because macOS has no timeout(1).
with_timeout() {
  perl -e '
    my $t = shift;
    setpgrp(0, 0);
    my $pid = fork();
    defined $pid or exit 125;
    if (!$pid) { exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { $SIG{TERM} = "IGNORE"; kill "TERM", -$$; exit 124 };
    alarm $t;
    waitpid($pid, 0);
    exit($? >> 8)' "$@"
}

if ! suite "$src"; then
  echo "control run failed: fix the tests before mutating" >&2
  exit 1
fi
# Mutants run in parallel, MUTATE_JOBS at a time (default: the CPU count): most are killed only by
# a case late in cases.tsv, so one at a time runs past the CI job's timeout. Under that load
# wall-clock assertions mean nothing, so MUTATE_NO_TIMING=1 turns them off.
max=${MUTATE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
total=0
for script in "$src"/*.sh "$src"/lib/*.sh; do
  rel=${script#"$src"/}
  while IFS= read -r id; do
    total=$((total + 1))
    m="$work/s$total"
    cp -R "$src" "$m"
    awk -v id="$id" '
      $0 ~ "# rule:" id "$" { skip = 1; next }
      $0 ~ "# end:" id "$" { skip = 0; next }
      !skip' "$script" > "$m/$rel"
    (
      # shellcheck disable=SC2016 # $0 expands in the inner bash: it is $here
      with_timeout "$limit" env HOOKS_DIR="$m" MUTATE_FAIL_FAST=1 MUTATE_NO_TIMING=1 bash -c '
        bash "$0/lifecycle.sh" >/dev/null 2>&1 && bash "$0/run.sh" >/dev/null 2>&1' "$here"
      rc=$?
      case "$rc" in
        0) echo "SURVIVED: $rel rule:$id (no test fails without it)" > "$work/survived$total" ;;
        124) echo "TIMED OUT: $rel rule:$id (the suite did not finish in ${limit}s)" > "$work/timedout$total" ;;
      esac
    ) &
    while [ "$(jobs -pr | wc -l)" -ge "$max" ]; do sleep 0.2; done
  done < <(grep -oE '^[[:space:]]*# rule:[a-z0-9-]+' "$script" | sed 's/.*rule://')
done
wait
survivors=0 timedout=0
for f in "$work"/survived* "$work"/timedout*; do
  [ -f "$f" ] || continue
  cat "$f" >&2
  case "$f" in */survived*) survivors=$((survivors + 1)) ;; *) timedout=$((timedout + 1)) ;; esac
done
echo "mutation: rules=$total survived=$survivors timedout=$timedout"
[ "$total" -gt 0 ] && [ "$survivors" -eq 0 ] && [ "$timedout" -eq 0 ]
