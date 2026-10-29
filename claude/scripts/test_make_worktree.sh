#!/bin/bash
# Tests for make-worktree.sh.
# Run: bash test_make_worktree.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/make-worktree.sh"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Fixtures live under $HOME so the paths round-trip through cygpath on Git Bash.
test_root="$HOME/.make-worktree-test.$$"
if command -v cygpath > /dev/null 2>&1; then test_root="$(cygpath -m "$test_root")"; fi
mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT

export CLAUDE_REPOS_FILE="$test_root/.claude_repos"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

origin="$test_root/origin.git"
repo="$test_root/repo"
git init -q --bare -b main "$origin"
git clone -q "$origin" "$repo" 2> /dev/null
git -C "$repo" checkout -q -b main 2> /dev/null
git -C "$repo" commit -q --allow-empty -m "initial"
git -C "$repo" push -q origin main

worktrees="$test_root/repo-worktrees"

# origin moves ahead of the clone, which has not pulled
other="$test_root/other"
git clone -q "$origin" "$other" 2> /dev/null
git -C "$other" commit -q --allow-empty -m "second"
git -C "$other" push -q origin main
origin_tip="$(git -C "$other" rev-parse HEAD)"

# 1. New branch without a base: worktree from the up-to-date origin/main, path on stdout
out="$(bash "$SCRIPT" "$repo" feat/new-thing 2> /dev/null)"
status=$?
tip="$(git -C "$worktrees/new-thing" rev-parse HEAD 2> /dev/null)"
if [[ $status -eq 0 && "$tip" == "$origin_tip" && "$(cd "$out" && pwd)" == "$(cd "$worktrees/new-thing" && pwd)" ]]; then
    pass "new branch is created from origin/main and the path is printed"
else
    fail "status $status, tip '$tip' (want '$origin_tip'), stdout '$out'"
fi

# 1b. A new branch has no upstream, so the first push names its own remote branch
if ! git -C "$worktrees/new-thing" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' > /dev/null 2>&1; then
    pass "new branch does not track its start point"
else
    fail "new branch tracks '$(git -C "$worktrees/new-thing" rev-parse --abbrev-ref '@{upstream}')'"
fi

# 2. New branch with a base branch: created from that branch's tip
git -C "$repo" branch parent "$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q parent
git -C "$repo" commit -q --allow-empty -m "on parent"
parent_tip="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q main
bash "$SCRIPT" "$repo" feat/stacked parent > /dev/null 2>&1
tip="$(git -C "$worktrees/stacked" rev-parse HEAD 2> /dev/null)"
if [[ "$tip" == "$parent_tip" ]]; then
    pass "base branch argument is the start point"
else
    fail "stacked tip '$tip', want '$parent_tip'"
fi

# 3. Existing local branch: worktree checks it out
git -C "$repo" branch feat/local-only
bash "$SCRIPT" "$repo" feat/local-only > /dev/null 2>&1
branch="$(git -C "$worktrees/local-only" branch --show-current 2> /dev/null)"
if [[ "$branch" == "feat/local-only" ]]; then
    pass "existing local branch is checked out"
else
    fail "local-only worktree is on '$branch'"
fi

# 4. Remote-only branch: worktree checks it out
git -C "$other" push -q origin HEAD:refs/heads/feat/remote-only
bash "$SCRIPT" "$repo" feat/remote-only > /dev/null 2>&1
branch="$(git -C "$worktrees/remote-only" branch --show-current 2> /dev/null)"
if [[ "$branch" == "feat/remote-only" ]]; then
    pass "remote-only branch is checked out"
else
    fail "remote-only worktree is on '$branch'"
fi

# 5. Running again on an existing worktree reuses it
out="$(bash "$SCRIPT" "$repo" feat/new-thing 2> /dev/null)"
status=$?
if [[ $status -eq 0 && "$(cd "$out" && pwd)" == "$(cd "$worktrees/new-thing" && pwd)" ]]; then
    pass "existing worktree is reused"
else
    fail "rerun status $status, stdout '$out'"
fi

# 6. The worktree is recorded in the repos history
if grep -Fq -- "$(cd "$worktrees/new-thing" && pwd)" "$CLAUDE_REPOS_FILE"; then
    pass "worktree is recorded in the repos history"
else
    fail "history is: $(cat "$CLAUDE_REPOS_FILE" 2> /dev/null)"
fi

# 6b. The main checkout's local Claude settings reach a new worktree
mkdir -p "$repo/.claude"
echo '{"env":{"A":"main"}}' > "$repo/.claude/settings.local.json"
bash "$SCRIPT" "$repo" feat/with-settings > /dev/null 2>&1
if [[ "$(cat "$worktrees/with-settings/.claude/settings.local.json" 2> /dev/null)" == '{"env":{"A":"main"}}' ]]; then
    pass "local Claude settings are copied into a new worktree"
else
    fail "worktree settings: '$(cat "$worktrees/with-settings/.claude/settings.local.json" 2>&1)'"
fi

# 6c. A worktree's own local Claude settings are kept on reuse
echo '{"env":{"A":"worktree"}}' > "$worktrees/with-settings/.claude/settings.local.json"
bash "$SCRIPT" "$repo" feat/with-settings > /dev/null 2>&1
if [[ "$(cat "$worktrees/with-settings/.claude/settings.local.json")" == '{"env":{"A":"worktree"}}' ]]; then
    pass "a worktree's own local Claude settings are not overwritten"
else
    fail "worktree settings overwritten: '$(cat "$worktrees/with-settings/.claude/settings.local.json")'"
fi

# 7. Uncommitted changes: refuses without creating a worktree
echo dirty > "$repo/tracked.txt"
git -C "$repo" add tracked.txt
bash "$SCRIPT" "$repo" feat/blocked < /dev/null > /dev/null 2>&1
status=$?
if [[ $status -ne 0 && ! -e "$worktrees/blocked" ]]; then
    pass "dirty tree is refused"
else
    fail "dirty tree: status $status, worktree exists: $([[ -e "$worktrees/blocked" ]] && echo yes || echo no)"
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
