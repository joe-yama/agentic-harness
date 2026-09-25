#!/usr/bin/env bash
# Proves every guarded rule is covered: for each "# rule:<id>" block in the hook scripts and lib/,
# delete the block in a copy and require at least one test to fail. Control run first.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
repo=$(cd "$here/../.." && pwd -P)
src=${HOOKS_SRC:-$repo/plugins/harness/scripts}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
suite() {
  HOOKS_DIR=$1 bash "$here/run.sh" >/dev/null 2>&1 && HOOKS_DIR=$1 bash "$here/lifecycle.sh" >/dev/null 2>&1
}

if ! suite "$src"; then
  echo "control run failed: fix the tests before mutating" >&2
  exit 1
fi
survivors=0 total=0
for script in "$src"/*.sh "$src"/lib/*.sh; do
  rel=${script#"$src"/}
  while IFS= read -r id; do
    total=$((total + 1))
    rm -r "$work/s" 2>/dev/null
    cp -R "$src" "$work/s"
    awk -v id="$id" '
      $0 ~ "# rule:" id "$" { skip = 1; next }
      $0 ~ "# end:" id "$" { skip = 0; next }
      !skip' "$script" > "$work/s/$rel"
    if suite "$work/s"; then
      echo "SURVIVED: $rel rule:$id (no test fails without it)" >&2
      survivors=$((survivors + 1))
    fi
  done < <(grep -oE '^[[:space:]]*# rule:[a-z0-9-]+' "$script" | sed 's/.*rule://')
done
echo "mutation: rules=$total survived=$survivors"
[ "$total" -gt 0 ] && [ "$survivors" -eq 0 ]
