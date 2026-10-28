#!/usr/bin/env bash
#
# update-branch-stats.sh - count GitHub "Update branch" clicks per month.
#
# GitHub doesn't expose button clicks, so this counts the merge commits that
# GitHub's web-flow bot creates on a PR branch when "Update branch" is used
# (message: "Merge branch '<base>' into <head>"). Calls to the
# PUT /repos/{owner}/{repo}/pulls/{n}/update-branch API produce the same commit
# and are counted too.
#
# Usage: update-branch-stats.sh <owner/repo> <start YYYY-MM> <end YYYY-MM> [-o out.csv]

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <owner/repo> <start YYYY-MM> <end YYYY-MM> [-o out.csv]" >&2
  exit 1
}

die() {
  echo "error: $*" >&2
  exit 1
}

# YYYY-MM -> months since year 0, so ranges can be compared and iterated
# without relying on GNU vs BSD `date`.
month_index() {
  local y=${1%-*} m=${1#*-}
  echo $(( 10#$y * 12 + 10#$m - 1 ))
}

index_month() {
  printf '%04d-%02d' $(( $1 / 12 )) $(( $1 % 12 + 1 ))
}

# --- args -------------------------------------------------------------------

[[ $# -ge 3 ]] || usage
repo=$1 start=$2 end=$3
shift 3
out=""
while getopts ":o:" opt; do
  case $opt in
    o) out=$OPTARG ;;
    *) usage ;;
  esac
done

[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "repo must look like owner/name"
[[ $start =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "start must be YYYY-MM"
[[ $end =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "end must be YYYY-MM"

start_idx=$(month_index "$start")
end_idx=$(month_index "$end")
(( start_idx <= end_idx )) || die "start must not be after end"

command -v gh >/dev/null || die "gh is not installed (brew install gh)"
command -v jq >/dev/null || die "jq is not installed (brew install jq)"
gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"

range_start="${start}-01T00:00:00Z"
range_end="$(index_month $(( end_idx + 1 )))-01T00:00:00Z"  # exclusive

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. find PRs that could contain an update in the range -------------------
#
# Page through PRs newest-updated first and stop once we pass the start of the
# range. A PR updated before the range can't have a commit inside it, and a PR
# created after the range can't either.

page=1
while :; do
  gh api "repos/$repo/pulls?state=all&sort=updated&direction=desc&per_page=100&page=$page" \
    > "$tmp/page.json" || die "failed to list pull requests for $repo"

  [[ $(jq length "$tmp/page.json") -gt 0 ]] || break

  jq -r --arg from "$range_start" --arg to "$range_end" \
    '.[] | select(.updated_at >= $from and .created_at < $to) | "\(.number)\t\(.base.ref)"' \
    "$tmp/page.json" >> "$tmp/prs.tsv"

  oldest=$(jq -r '.[-1].updated_at' "$tmp/page.json")
  [[ $oldest > $range_start ]] || break
  page=$(( page + 1 ))
done

touch "$tmp/prs.tsv"
total=$(wc -l < "$tmp/prs.tsv" | tr -d ' ')
echo "Scanning $total pull requests in $repo..." >&2

# --- 2. collect web-flow "Merge branch '<base>' into" commits ----------------

touch "$tmp/months.txt"
i=0
while IFS=$'\t' read -r number base; do
  i=$(( i + 1 ))
  printf '\r  PR %d/%d (#%s)' "$i" "$total" "$number" >&2

  gh api --paginate "repos/$repo/pulls/$number/commits?per_page=100" \
    | jq -r --arg base "$base" '
        .[]
        | select(.committer.login? == "web-flow")
        | select((.parents | length) == 2)
        | select(.commit.message | startswith("Merge branch '\''" + $base + "'\'' into"))
        | .commit.committer.date[0:7]' \
    >> "$tmp/months.txt" || die "failed to read commits for PR #$number"
done < "$tmp/prs.tsv"
(( total > 0 )) && echo >&2

# --- 3. write one row per month, zero-filled --------------------------------

write_csv() {
  echo "month,update_branch_clicks"
  local idx month count
  for (( idx = start_idx; idx <= end_idx; idx++ )); do
    month=$(index_month "$idx")
    count=$(grep -cx "$month" "$tmp/months.txt" || true)
    echo "$month,$count"
  done
}

if [[ -n $out ]]; then
  write_csv > "$out"
  echo "Wrote $out" >&2
else
  write_csv
fi
