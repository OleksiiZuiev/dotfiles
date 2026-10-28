#!/bin/bash
# Tests for review-pr-tab.sh.
# Run: bash test_review_pr_tab.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/review-pr-tab.sh"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Fixtures live under $HOME so the paths round-trip through cygpath on Git Bash.
test_root="$HOME/.review-pr-tab-test.$$"
if command -v cygpath > /dev/null 2>&1; then test_root="$(cygpath -m "$test_root")"; fi
mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT

export CLAUDE_REPOS_FILE="$test_root/.claude_repos"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A teammate's PR #7: its head is a commit only refs/pull/7/head points at, as on GitHub.
origin="$test_root/origin.git"
repo="$test_root/repo"
git init -q --bare -b main "$origin"
git clone -q "$origin" "$repo" 2> /dev/null
git -C "$repo" checkout -q -b main 2> /dev/null
git -C "$repo" commit -q --allow-empty -m "initial"
git -C "$repo" push -q origin main
git -C "$repo" checkout -q -b teammate
git -C "$repo" commit -q --allow-empty -m "the PR"
pr_head="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" push -q origin "HEAD:refs/pull/7/head"
git -C "$repo" checkout -q main
git -C "$repo" branch -q -D teammate

worktree="$test_root/repo-worktrees/pr-7-${pr_head:0:7}"
url="https://github.com/Some-Org/some-repo/pull/7"

export CLAUDE_REPO_MAP="$test_root/repo-map.md"
cat > "$CLAUDE_REPO_MAP" <<EOF
| Repo | Org | Path | Summary |
|------|-----|------|---------|
| some-repo | some-org | $repo | A fixture. |
EOF

# Stands in for the tab: records its arguments, one per line, instead of opening one.
tab_args="$test_root/tab-args"
claude_tab() { printf '%s\n' "$@" > "$TAB_ARGS"; }
export -f claude_tab
export TAB_ARGS="$tab_args"

worktree_count() { git -C "$repo" worktree list --porcelain | grep -c '^worktree '; }
same_dir() { [[ -d "$1" && -d "$2" && "$(cd "$1" && pwd)" == "$(cd "$2" && pwd)" ]]; }
# The tab's directory: the argument after the title, which follows --then and its command.
tab_dir() { sed -n 4p "$tab_args"; }

# 1. A PR URL makes a detached worktree at the PR head and opens a tab there reviewing the PR,
# with the remaining arguments forwarded to the review
bash "$SCRIPT" "$url" +comment --bar low > /dev/null 2>&1
status=$?
head="$(git -C "$worktree" rev-parse HEAD 2> /dev/null)"
branch="$(git -C "$worktree" branch --show-current 2> /dev/null)"
if [[ $status -eq 0 && "$head" == "$pr_head" && -z "$branch" ]]; then
    pass "worktree is detached at the PR head"
else
    fail "status $status, head '$head' (want '$pr_head'), branch '$branch' (want none)"
fi
if same_dir "$(tab_dir)" "$worktree" && grep -Fxq "/ds:review 7 +comment --bar low" "$tab_args"; then
    pass "tab opens in the worktree running /ds:review on the PR number"
else
    fail "tab arguments: $(tr '\n' '|' < "$tab_args" 2> /dev/null)"
fi

# 2. The same PR head again: the tab opens in the existing worktree and none is added
before=$(worktree_count)
rm -f "$tab_args"
bash "$SCRIPT" "$url" > /dev/null 2>&1
if [[ $(worktree_count) -eq $before ]] && same_dir "$(tab_dir)" "$worktree"; then
    pass "same PR head reuses its worktree"
else
    fail "worktrees $before -> $(worktree_count), tab directory '$(tab_dir)'"
fi

# 3. The tab releases the worktree when its claude exits
if grep -Fq -- "--release" "$tab_args" && [[ "$(sed -n 1p "$tab_args")" == "--then" ]]; then
    pass "tab is opened with a release command"
else
    fail "no --then release command in tab arguments: $(tr '\n' '|' < "$tab_args")"
fi

# 4. Releasing one of two tabs keeps the worktree; releasing the last removes it
bash "$SCRIPT" --release "$worktree" > /dev/null 2>&1
if [[ -d "$worktree" ]]; then
    pass "worktree kept while another tab is open in it"
else
    fail "worktree removed with a tab still open in it"
fi
bash "$SCRIPT" --release "$worktree" > /dev/null 2>&1
if [[ ! -e "$worktree" ]] && ! git -C "$repo" worktree list | grep -Fq "pr-7-"; then
    pass "last release removes the worktree and its registration"
else
    fail "worktree left behind: $(git -C "$repo" worktree list | tr '\n' '|')"
fi

# 5. A repo missing from the repo map stops with one line, before any worktree or tab
rm -f "$tab_args"
before=$(worktree_count)
err="$(bash "$SCRIPT" "https://github.com/other-org/unknown/pull/3" 2>&1 > /dev/null)"
status=$?
if [[ $status -ne 0 && $(wc -l <<< "$err") -eq 1 && "$err" == *other-org/unknown* ]]; then
    pass "repo missing from the map stops with one line naming it"
else
    fail "status $status, stderr: $err"
fi
if [[ ! -e "$tab_args" && $(worktree_count) -eq $before ]]; then
    pass "repo missing from the map opens no tab and makes no worktree"
else
    fail "tab opened or worktree made for an unmapped repo"
fi

# 6. A URL that is not a PR URL opens no tab
rm -f "$tab_args"
issue_url="https://github.com/some-org/some-repo/issues/7"
err="$(bash "$SCRIPT" "$issue_url" 2>&1 > /dev/null)"
status=$?
if [[ $status -ne 0 && "$err" == *"$issue_url"* && ! -e "$tab_args" ]]; then
    pass "non-PR URL is refused, naming the URL"
else
    fail "status $status, stderr '$err', tab arguments: $(tr '\n' '|' < "$tab_args" 2> /dev/null)"
fi

echo ""
if [[ $failures -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
