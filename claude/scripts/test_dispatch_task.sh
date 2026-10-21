#!/bin/bash
# Tests for dispatch-task.sh.
# Run: bash test_dispatch_task.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/dispatch-task.sh"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

test_root="$HOME/.dispatch-task-test.$$"
mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT

# The script reaches its helpers and the overlays through $HOME, so a fixture home holds stubs
# that record their arguments, one per line, instead of making worktrees and opening tabs.
fake_home="$test_root/home"
scripts="$fake_home/.claude/scripts"
mkdir -p "$scripts/tasks" "$fake_home/.claude/overlays"
worktree_args="$test_root/make-worktree-args"
tab_args="$test_root/claude-tab-args"
task_args="$test_root/task-args"

cat > "$scripts/make-worktree.sh" <<'EOF'
printf '%s\n' "$@" > "$WORKTREE_ARGS"
[[ -n "$MAKE_WORKTREE_FAILS" ]] && { echo "Error: Uncommitted changes in $1" >&2; exit 1; }
echo "/worktrees/${2#*/}"
EOF
cat > "$scripts/claude-tab.sh" <<'EOF'
printf '%s\n' "$@" > "$TAB_ARGS"
EOF
cat > "$scripts/tasks/task.sh" <<'EOF'
task() { printf '%s\n' "$@" > "$TASK_ARGS"; }
EOF
printf '## Workflow\nworktree: no\n' > "$fake_home/.claude/overlays/shared.md"
printf '## Workflow\nworktree: yes\n' > "$fake_home/.claude/overlays/app.md"

repo_map="$test_root/repo-map.md"
cat > "$repo_map" <<'EOF'
# Local Repo Map

| Repo | Org | Path | Summary |
|------|-----|------|---------|
| app | other | /repos/other/app | Same name, another org. |
| app | acme | /repos/acme/app | The app. |
| shared | acme | /repos/acme/shared | Runs in its own checkout. |
EOF

vault="C:/vault"
export WORKTREE_ARGS="$worktree_args" TAB_ARGS="$tab_args" TASK_ARGS="$task_args"
export CLAUDE_REPO_MAP="$repo_map" CLAUDE_VAULT_DIR="$vault"
unset WSL_DISTRO_NAME MAKE_WORKTREE_FAILS

# Runs the script with the fixture home; sets $out, $err and $status.
dispatch() {
    rm -f "$worktree_args" "$tab_args" "$task_args"
    out="$(HOME="$fake_home" bash "$SCRIPT" "$@" 2> "$test_root/stderr")"
    status=$?
    err="$(cat "$test_root/stderr")"
}
recorded() { cat "$1" 2> /dev/null | tr '\n' ' '; }

# 1. A worktree workspace: the worktree from the repo's path, the tab in it with the prompt,
# the model flags and the vault added
dispatch VE-7 acme/app --branch feat/ve-7-thing --model sonnet --effort high
if [[ $status -eq 0 && "$out" == "/worktrees/ve-7-thing" \
    && "$(recorded "$worktree_args")" == "/repos/acme/app feat/ve-7-thing " \
    && "$(recorded "$tab_args")" == "VE-7 /worktrees/ve-7-thing /task-run VE-7 --model sonnet --effort high --add-dir $vault " ]]; then
    pass "worktree workspace gets a worktree and a tab with the vault added"
else
    fail "status $status, stdout '$out', worktree '$(recorded "$worktree_args")', tab '$(recorded "$tab_args")'"
fi

# 2. Without --record-branch no branch is recorded
if [[ $status -eq 0 && ! -e "$task_args" ]]; then
    pass "branch is not recorded without --record-branch"
else
    fail "task was called with '$(recorded "$task_args")'"
fi

# 3. --record-branch records the branch on the task
dispatch VE-7 acme/app --branch feat/ve-7-thing --record-branch
if [[ $status -eq 0 && "$(recorded "$task_args")" == "set VE-7 branch feat/ve-7-thing " ]]; then
    pass "--record-branch records the branch"
else
    fail "status $status, task '$(recorded "$task_args")'"
fi

# 4. No model flags reach the tab when none are given
if [[ "$(recorded "$tab_args")" == "VE-7 /worktrees/ve-7-thing /task-run VE-7 --add-dir $vault " ]]; then
    pass "no model flags without --model and --effort"
else
    fail "tab '$(recorded "$tab_args")'"
fi

# 5. The vault workspace: the tab in the vault root, no worktree, no added directory
dispatch VE-8 vault --branch feat/ve-8-notes
if [[ $status -eq 0 && "$out" == "$vault" && ! -e "$worktree_args" \
    && "$(recorded "$tab_args")" == "VE-8 $vault /task-run VE-8 " ]]; then
    pass "vault workspace opens the tab in the vault root"
else
    fail "status $status, stdout '$out', worktree '$(recorded "$worktree_args")', tab '$(recorded "$tab_args")'"
fi

# 6. An overlay saying worktree: no: the tab in the checkout with the vault added, no worktree
dispatch VE-9 acme/shared --branch feat/ve-9-x --record-branch
if [[ $status -eq 0 && "$out" == "/repos/acme/shared" && ! -e "$worktree_args" && ! -e "$task_args" \
    && "$(recorded "$tab_args")" == "VE-9 /repos/acme/shared /task-run VE-9 --add-dir $vault " ]]; then
    pass "shared checkout opens the tab in the checkout with the vault added"
else
    fail "status $status, stdout '$out', worktree '$(recorded "$worktree_args")', task '$(recorded "$task_args")', tab '$(recorded "$tab_args")'"
fi

# 7. A worktree workspace without --branch: refused, no tab
dispatch VE-7 acme/app
if [[ $status -ne 0 && "$err" == *"--branch"* && ! -e "$worktree_args" && ! -e "$tab_args" ]]; then
    pass "worktree workspace without --branch is refused"
else
    fail "status $status, stderr '$err', worktree '$(recorded "$worktree_args")', tab '$(recorded "$tab_args")'"
fi

# 8. A workspace missing from the repo map: refused, no tab
dispatch VE-7 acme/missing --branch feat/ve-7-thing
if [[ $status -ne 0 && "$err" == *"acme/missing"* && ! -e "$worktree_args" && ! -e "$tab_args" ]]; then
    pass "unknown workspace is refused"
else
    fail "status $status, worktree '$(recorded "$worktree_args")', tab '$(recorded "$tab_args")'"
fi

# 9. make-worktree.sh fails: no branch recorded, no tab
MAKE_WORKTREE_FAILS=1 dispatch VE-7 acme/app --branch feat/ve-7-thing --record-branch
if [[ $status -ne 0 && "$err" == *"Uncommitted changes"* && ! -e "$task_args" && ! -e "$tab_args" ]]; then
    pass "failed worktree stops before the branch is recorded and the tab opens"
else
    fail "status $status, task '$(recorded "$task_args")', tab '$(recorded "$tab_args")'"
fi

# 10. From WSL: refused before a worktree is made
WSL_DISTRO_NAME=Ubuntu dispatch VE-7 acme/app --branch feat/ve-7-thing
if [[ $status -ne 0 && "$err" == *"WSL"* && ! -e "$worktree_args" && ! -e "$tab_args" ]]; then
    pass "WSL is refused before any worktree"
else
    fail "status $status, worktree '$(recorded "$worktree_args")', tab '$(recorded "$tab_args")'"
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
