#!/usr/bin/env bash
# harness-metrics: measures what the harness itself costs this repository, each value against a threshold.
# Usage: scripts/harness-metrics.sh [--since YYYY-MM-DD] [--check]
#   --since  only PRs merged on or after that date count for CI minutes
#   --check  exit 1 when any metric is over its threshold (default: always exit 0)
# Prints TSV with a header: metric, scope, value, threshold, status (ok | over; over means value > threshold).
# Lines starting with "#" are notes (a metric that could not be measured). Needs bash, git and jq;
# CI minutes also need an authenticated gh and are skipped without it.
# Thresholds (HARNESS_METRIC_* overrides):
#   ci_minutes_per_pr       CI_MINUTES=20      sum of workflow run durations on the head branch of each of the
#                                              last PRS=10 merged PRs
#   dispatches_per_change   DISPATCHES=20      "dispatched" lines in the ledger .harness/<change>/progress.md
#   fix_rounds_per_unit     FIX_ROUNDS=2       highest k of .harness/<change>/reports/<unit>-review-r<k>.md
#   test_source_ratio       TEST_RATIO=1.5     lines of tracked test files / lines of other tracked code files;
#                                              TEST_PATTERN and CODE_PATTERN (extended regexes) pick them
#   always_loaded_bytes     CONTEXT_BYTES=14400  AGENTS.md, CLAUDE.md, .claude/rules/*.md and
#                                              .github/copilot-instructions.md (90% of the CI budget of 16000)
#   solo_review_share       SOLO_SHARE=40      percent of "Review:" lines saying solo rather than batch, in every
#                                              openspec/changes/**/tasks.md (archive included)
#   change_tasks            CHANGE_TASKS=15    checkbox tasks in tasks.md, per active change (not archive)
#   change_chars            CHANGE_CHARS=30000 characters of tasks.md + design.md, per active change
set -u

usage() {
  echo "usage: $0 [--since YYYY-MM-DD] [--check]" >&2
  exit 2
}
since='' check=''
while [ $# -gt 0 ]; do
  case "$1" in
    --since)
      [ $# -ge 2 ] || usage
      printf '%s' "$2" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || usage
      since=$2
      shift 2
      ;;
    --check) check=1 && shift ;;
    *) usage ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "harness-metrics: jq not found" >&2; exit 2; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "harness-metrics: not inside a git repository" >&2; exit 2; }
cd "$root" || exit 2

t_ci=${HARNESS_METRIC_CI_MINUTES:-20}
n_prs=${HARNESS_METRIC_PRS:-10}
t_disp=${HARNESS_METRIC_DISPATCHES:-20}
t_fix=${HARNESS_METRIC_FIX_ROUNDS:-2}
t_ratio=${HARNESS_METRIC_TEST_RATIO:-1.5}
t_ctx=${HARNESS_METRIC_CONTEXT_BYTES:-14400}
t_solo=${HARNESS_METRIC_SOLO_SHARE:-40}
t_tasks=${HARNESS_METRIC_CHANGE_TASKS:-15}
t_chars=${HARNESS_METRIC_CHANGE_CHARS:-30000}
test_re=${HARNESS_METRIC_TEST_PATTERN:-'(^|/)(tests?|__tests__|spec)/|[._-](test|spec)\.'}
code_re=${HARNESS_METRIC_CODE_PATTERN:-'\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte|astro|py|rb|go|rs|java|kt|kts|scala|swift|c|h|cc|cpp|hpp|cs|php|ex|exs|sh|sql)$'}
not_code_re='^(docs|openspec|\.claude|\.github|\.codex|\.harness|\.agents)/|^scripts/harness-metrics\.sh$'

over=0
row() { # <metric> <scope> <value> <threshold>
  local s=ok
  if awk -v v="$3" -v t="$4" 'BEGIN { exit !(v + 0 > t + 0) }'; then s=over && over=1; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$s"
}
note() { printf '# %s\n' "$*"; }

printf 'metric\tscope\tvalue\tthreshold\tstatus\n'

# CI minutes per merged PR
if ! command -v gh >/dev/null 2>&1; then
  note "ci_minutes_per_pr skipped: gh not found"
elif ! gh auth status >/dev/null 2>&1; then
  note "ci_minutes_per_pr skipped: gh is not authenticated"
elif ! prs=$(gh pr list --state merged --limit "$n_prs" --json number,headRefName ${since:+--search "merged:>=$since"} 2>/dev/null); then
  note "ci_minutes_per_pr skipped: gh pr list failed"
else
  while IFS="$(printf '\t')" read -r num branch; do
    [ -n "$num" ] || continue
    if ! runs=$(gh run list --branch "$branch" --limit 100 --json startedAt,updatedAt 2>/dev/null); then
      note "ci_minutes_per_pr #$num skipped: gh run list failed"
      continue
    fi
    min=$(printf '%s' "$runs" | jq -r '[.[] | select(.startedAt and .updatedAt and (.startedAt | startswith("0001") | not))
      | (.updatedAt | fromdateiso8601) - (.startedAt | fromdateiso8601) | select(. > 0)] | add // 0 | . / 60 * 10 | round / 10
      | if . == floor then "\(.).0" else tostring end')
    row ci_minutes_per_pr "#$num" "$min" "$t_ci"
  done <<EOF
$(printf '%s' "$prs" | jq -r '.[] | [.number, .headRefName] | @tsv')
EOF
fi

# Ledgers: dispatches per change, fix rounds per review unit
for led in .harness/*/; do
  [ -d "$led" ] || continue
  change=$(basename "$led")
  if [ -f "$led/progress.md" ]; then
    row dispatches_per_change "$change" "$(grep -cw dispatched "$led/progress.md")" "$t_disp"
  fi
  [ -d "$led/reports" ] || continue
  units=$(for r in "$led"/reports/*-review.md "$led"/reports/*-review-r*.md; do
    [ -f "$r" ] || continue
    basename "$r" .md
  done | sed -nE 's/-review(-r([0-9]+))?$/ \2/p' | awk '
    { k = $2 + 0; if (!($1 in m) || k > m[$1]) m[$1] = k }
    END { for (u in m) print u, m[u] }' | sort)
  while read -r unit k; do # not a pipe: row must set over in this shell
    [ -n "$unit" ] && row fix_rounds_per_unit "$change/$unit" "$k" "$t_fix"
  done <<EOF
$units
EOF
done

# Test and source lines over tracked files
lines() { # reads paths on stdin, prints their total line count
  local f n=0 c
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    c=$(awk 'END { print NR }' "$f")
    n=$((n + c))
  done
  echo "$n"
}
code=$(git ls-files | grep -E -- "$code_re" | grep -Ev -- "$not_code_re")
tl=$(printf '%s\n' "$code" | grep -E -- "$test_re" | lines)
sl=$(printf '%s\n' "$code" | grep -Ev -- "$test_re" | grep -v '^$' | lines)
if [ "$sl" -gt 0 ]; then
  row test_source_ratio repo "$(awk -v t="$tl" -v s="$sl" 'BEGIN { printf "%.2f", t / s }')" "$t_ratio"
else
  note "test_source_ratio skipped: no source lines (test lines: $tl)"
fi

# Always-loaded context
bytes=0
for f in AGENTS.md CLAUDE.md .claude/rules/*.md .github/copilot-instructions.md; do
  [ -f "$f" ] || continue
  bytes=$((bytes + $(wc -c < "$f")))
done
row always_loaded_bytes repo "$bytes" "$t_ctx"

# Solo-review share over every change's tasks.md
counts=$(find openspec/changes -name tasks.md -type f -print 2>/dev/null | while IFS= read -r f; do
  grep -oE 'Review:[^A-Za-z]*(solo|batch)' "$f" | grep -oE '(solo|batch)$'
done | sort | uniq -c)
solo=$(printf '%s\n' "$counts" | awk '$2 == "solo" { print $1 }')
batch=$(printf '%s\n' "$counts" | awk '$2 == "batch" { print $1 }')
solo=${solo:-0} batch=${batch:-0}
if [ $((solo + batch)) -gt 0 ]; then
  row solo_review_share repo "$((solo * 100 / (solo + batch)))" "$t_solo"
else
  note "solo_review_share skipped: no Review: lines in openspec/changes/**/tasks.md"
fi

# Size of each active change
for d in openspec/changes/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  [ "$name" = archive ] && continue
  tasks=0
  [ -f "$d/tasks.md" ] && tasks=$(grep -cE '^[[:space:]]*- \[[ xX]\] ' "$d/tasks.md")
  row change_tasks "$name" "$tasks" "$t_tasks"
  chars=$(cat "$d/tasks.md" "$d/design.md" 2>/dev/null | jq -Rrs 'length')
  row change_chars "$name" "$chars" "$t_chars"
done

[ -n "$check" ] && [ "$over" = 1 ] && exit 1
exit 0
