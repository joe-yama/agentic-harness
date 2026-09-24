#!/usr/bin/env bash
# Shared helpers for the test scripts. Source it; do not execute it.
set -u
PASS=0
FAIL=0

# Isolated git config so tests never read the user's global config (signing, hooks).
setup_git_env() {
  TMP_ROOT=$(mktemp -d)
  TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
  trap 'rm -rf "$TMP_ROOT"' EXIT
  export GIT_CONFIG_GLOBAL="$TMP_ROOT/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  git config --global user.name "harness-test"
  git config --global user.email "harness-test@example.invalid"
  git config --global commit.gpgsign false
  git config --global tag.gpgsign false
  git config --global init.defaultBranch main
}

ok() { PASS=$((PASS + 1)); }
ng() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$*" >&2
}

report() {
  printf '%s: pass=%d fail=%d\n' "${1:-tests}" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
