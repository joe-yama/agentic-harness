#!/usr/bin/env bash
# Static checks for shell scripts. Uses a pinned shellcheck through uvx.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repo" || exit 1
files=()
while IFS= read -r f; do files+=("$f"); done < <(git ls-files -co --exclude-standard '*.sh')
uvx --from shellcheck-py==0.11.0.1 shellcheck -x "${files[@]}" && echo "shellcheck: ${#files[@]} files clean"
