#!/usr/bin/env bash
# Runs every check CI runs. Exits non-zero if any suite fails.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
status=0
for t in lint.sh hooks/run.sh hooks/lifecycle.sh hooks/timing.sh hooks/mutate.sh manifest.sh template/run.sh; do
  echo "== $t"
  bash "$here/$t" || status=1
done
[ "$status" -eq 0 ] && echo "all: ok" || echo "all: FAILED"
exit "$status"
