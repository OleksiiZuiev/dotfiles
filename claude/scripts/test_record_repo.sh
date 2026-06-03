#!/bin/bash
# Tests for record-repo.sh (record_repo_history).
# Run: bash test_record_repo.sh

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/record-repo.sh"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Isolated fixtures under a real /c/... path ($HOME) so cygpath -w <-> -u
# round-trips cleanly (/tmp maps onto a different path and would not).
test_root="$HOME/.record-repo-test.$$"
mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT

export CLAUDE_REPOS_FILE="$test_root/.claude_repos"

norm() { if command -v cygpath > /dev/null 2>&1; then cygpath -u "$1"; else echo "$1"; fi; }

repo="$test_root/repo"
mkdir -p "$repo"
git -C "$repo" init -q
expected="$(norm "$repo")"

not_repo="$test_root/plain"
mkdir -p "$not_repo"

# 1. Non-git dir is not recorded (guard)
record_repo_history "$not_repo"
if [[ ! -s "$CLAUDE_REPOS_FILE" ]]; then
    pass "non-git dir is not recorded"
else
    fail "non-git dir was recorded: $(cat "$CLAUDE_REPOS_FILE")"
fi

# 2. Git repo is recorded, normalized, at the top
record_repo_history "$repo"
top="$(head -n 1 "$CLAUDE_REPOS_FILE")"
if [[ "$top" == "$expected" ]]; then
    pass "git repo recorded (normalized) at top"
else
    fail "expected top '$expected', got '$top'"
fi

# 3. Recording the C:\ form of the same repo yields exactly one entry
if command -v cygpath > /dev/null 2>&1; then
    record_repo_history "$(cygpath -w "$repo")"
    count="$(grep -Fxc -- "$expected" "$CLAUDE_REPOS_FILE")"
    if [[ "$count" -eq 1 ]]; then
        pass "C:\\ form dedups against /c/ form (no double entry)"
    else
        fail "expected 1 entry for repo, found $count"
    fi
else
    pass "skip normalization test (no cygpath)"
fi

# 4. Re-recording an existing entry moves it to the top without duplicating
repo2="$test_root/repo2"
mkdir -p "$repo2"
git -C "$repo2" init -q
record_repo_history "$repo2"
record_repo_history "$repo"
top="$(head -n 1 "$CLAUDE_REPOS_FILE")"
count="$(grep -Fxc -- "$expected" "$CLAUDE_REPOS_FILE")"
if [[ "$top" == "$expected" && "$count" -eq 1 ]]; then
    pass "re-record moves entry to top, no duplicate"
else
    fail "expected top '$expected' single entry, got top '$top' count $count"
fi

# 5. Cap at 30: pre-fill 30 lines, record a new repo -> 30 lines, new at top
printf 'line-%02d\n' $(seq 1 30) > "$CLAUDE_REPOS_FILE"
repo3="$test_root/repo3"
mkdir -p "$repo3"
git -C "$repo3" init -q
record_repo_history "$repo3"
lines="$(wc -l < "$CLAUDE_REPOS_FILE")"
top="$(head -n 1 "$CLAUDE_REPOS_FILE")"
expected3="$(norm "$repo3")"
if [[ "$lines" -eq 30 && "$top" == "$expected3" ]]; then
    pass "history capped at 30 with newest first"
else
    fail "expected 30 lines newest-first, got $lines lines, top '$top'"
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
