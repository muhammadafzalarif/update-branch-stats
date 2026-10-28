# update-branch-stats

Count how often the **Update branch** button is used on pull requests in a GitHub repository, month by month, and write the result as a CSV.

Example, from a real run:

```
$ ./update-branch-stats.sh cli/cli 2025-01 2025-03 -o clicks.csv
Scanning 345 pull requests in cli/cli...
  PR 345/345 (#10163)
Wrote clicks.csv

$ cat clicks.csv
month,update_branch_clicks
2025-01,50
2025-02,20
2025-03,9
```

## How it works

GitHub doesn't record button clicks anywhere you can query. When someone clicks **Update branch**, though, GitHub creates a merge commit on the PR's branch that is:

- committed by the `web-flow` bot,
- a merge commit (two parents),
- titled `Merge branch '<base branch>' into <pr branch>`.

The script uses only the [GitHub CLI](https://cli.github.com/) (`gh api`):

1. It lists the repo's PRs, most recently updated first, and keeps those that could hold a commit in your date range.
2. It reads each PR's commits and keeps the ones that match the pattern above.
3. It counts matches by the month they were committed (UTC) and writes one row per month, including months with zero.

PR commits are read from `refs/pull/<n>/head`, so squash-merged PRs and deleted branches are still counted.

## Limitations

- **API calls count too.** `PUT /pulls/{n}/update-branch`, which bots and other tools use, creates the same commit, so the script can't tell it apart from a click.
- **"Update with rebase" isn't counted.** It rewrites the branch instead of creating a merge commit, so there's nothing to detect.
- **250 commits per PR.** GitHub's PR commits endpoint returns at most 250 commits.
- **API usage.** Each PR in range costs at least one API call. For large repos or long ranges, watch your [rate limit](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) (`gh api rate_limit`).

## Install

```sh
brew install gh jq      # or see https://cli.github.com and https://jqlang.github.io/jq
gh auth login
git clone https://github.com/muhammadafzalarif/update-branch-stats.git
cd update-branch-stats
```

## Usage

```
./update-branch-stats.sh <owner/repo> <start YYYY-MM> <end YYYY-MM> [-o out.csv]
```

| Argument      | Description                                 |
| ------------- | ------------------------------------------- |
| `owner/repo`  | Repository to scan, e.g. `cli/cli`          |
| `start`       | First month to include, e.g. `2025-01`      |
| `end`         | Last month to include, e.g. `2025-06`       |
| `-o out.csv`  | Write to a file instead of stdout           |

Progress goes to stderr, so you can also redirect stdout:

```sh
./update-branch-stats.sh my-org/my-repo 2024-01 2024-12 > 2024.csv
```

Private repos work as long as your `gh` login can read them.

## License

MIT
