#!/bin/bash
# Tests for prune-worktrees.sh against fixture repos and a stub `gh`.
# Run: bash claude/scripts/test_prune_worktrees.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/prune-worktrees.sh"

failures=0
check() { # $1 name  $2 actual  $3 expected
    if [[ "$2" == "$3" ]]; then
        echo "PASS: $1"
    else
        printf 'FAIL: %s\n      got [%s], want [%s]\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}

# Fixtures live under $HOME so the paths round-trip through cygpath on Git Bash.
test_root="$HOME/.prune-worktrees-test.$$"
if command -v cygpath > /dev/null 2>&1; then test_root="$(cygpath -m "$test_root")"; fi
mkdir -p "$test_root/bin" "$test_root/prs" "$test_root/overlays"
trap 'rm -rf "$test_root"' EXIT
# The script prunes the repo holding the current directory when it is misled into an empty repo
# path, so the tests never run it from inside a real repo.
cd "$test_root" || exit 1

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export CLAUDE_OVERLAYS_DIR="$test_root/overlays"
export CLAUDE_REPO_MAP="$test_root/repo-map.md"

# The stub answers `gh pr list --head <branch> ...` with the head commit written to
# prs/<branch, slashes as dashes>, nothing when that file is absent, and an error
# when it holds "error".
cat > "$test_root/bin/gh" <<'EOF'
#!/bin/bash
while [[ $# -gt 0 && "$1" != "--head" ]]; do shift; done
file="$PRUNE_TEST_PRS/${2//\//-}"
[[ -f "$file" ]] || exit 0
[[ "$(cat "$file")" == "error" ]] && { echo "gh: lookup failed" >&2; exit 1; }
cat "$file"
EOF
chmod +x "$test_root/bin/gh"
export PRUNE_TEST_PRS="$test_root/prs"
PATH="$(cd "$test_root/bin" && pwd):$PATH"

# make_repo <name>: a clone of a fresh bare origin with one commit on main
make_repo() {
    git init -q --bare -b main "$test_root/$1.git"
    git clone -q "$test_root/$1.git" "$test_root/$1" 2> /dev/null
    git -C "$test_root/$1" checkout -q -b main 2> /dev/null
    git -C "$test_root/$1" commit -q --allow-empty -m "initial"
    git -C "$test_root/$1" push -q origin main
}
# add_worktree <repo> <name>: worktree on branch feat/<name>, created from origin/main
add_worktree() {
    git -C "$test_root/$1" fetch -q origin
    git -C "$test_root/$1" worktree add -q --no-track -b "feat/$2" "$test_root/$1-worktrees/$2" origin/main
}
commit_in() { git -C "$test_root/$1-worktrees/$2" commit -q --allow-empty -m "$2 ${3:-work}"; }
tip() { git -C "$test_root/$1-worktrees/$2" rev-parse HEAD; }
exists() { [[ -d "$test_root/$1-worktrees/$2" ]] && echo yes || echo no; }
has_branch() { git -C "$test_root/$1" show-ref --verify --quiet "refs/heads/feat/$2" && echo yes || echo no; }
line_for() { grep -E "[[:space:]]feat/$1([[:space:]]|$)" <<< "$2" | sed -E 's/[[:space:]]+/ /g; s/ $//'; }

make_repo repo

add_worktree repo caught-up

add_worktree repo merged
commit_in repo merged
git -C "$test_root/repo-worktrees/merged" push -q origin HEAD:main

add_worktree repo dirty
commit_in repo dirty
git -C "$test_root/repo-worktrees/dirty" push -q origin HEAD:main
echo scratch > "$test_root/repo-worktrees/dirty/notes.txt"

add_worktree repo unmerged
commit_in repo unmerged

add_worktree repo squashed
commit_in repo squashed
tip repo squashed > "$test_root/prs/feat-squashed"

add_worktree repo continued
commit_in repo continued
tip repo continued > "$test_root/prs/feat-continued"
commit_in repo continued "after the merge"

add_worktree repo lookup-error
commit_in repo lookup-error
echo error > "$test_root/prs/feat-lookup-error"

add_worktree repo here
commit_in repo here
git -C "$test_root/repo-worktrees/here" push -q origin HEAD:main

add_worktree repo fresh
git -C "$test_root/repo-worktrees/caught-up" fetch -q origin
git -C "$test_root/repo-worktrees/caught-up" rebase -q origin/main

# --- help ---
out="$(bash "$SCRIPT" --help)"; code=$?
check "--help exits 0" "$code" 0
check "--help prints usage" "$([[ "$out" == *"Usage: prune-worktrees.sh"* ]] && echo yes)" yes

# --- an unknown option is a usage error, never a repo path ---
out="$(cd "$test_root/repo-worktrees/merged" && bash "$SCRIPT" --bogus 2>&1)"; code=$?
check "unknown option exits 2" "$code" 2
check "unknown option removes nothing" "$(exists repo merged)" yes

# --- dry run ---
out="$(bash "$SCRIPT" --dry-run "$test_root/repo" 2>&1)"
check "dry run names a merged worktree" "$(line_for merged "$out")" "would remove repo feat/merged"
check "dry run keeps the worktree" "$(exists repo merged)" yes
check "dry run keeps the branch" "$(has_branch repo merged)" yes

# --- live run, from inside the "here" worktree ---
out="$(cd "$test_root/repo-worktrees/here" && bash "$SCRIPT" "$test_root/repo" 2>&1)"

check "merged by ancestry: reported" "$(line_for merged "$out")" "removed repo feat/merged"
check "merged by ancestry: worktree gone" "$(exists repo merged)" no
check "merged by ancestry: branch gone" "$(has_branch repo merged)" no

check "squash-merged pull request: reported" "$(line_for squashed "$out")" "removed repo feat/squashed"
check "squash-merged pull request: worktree gone" "$(exists repo squashed)" no
check "squash-merged pull request: branch gone" "$(has_branch repo squashed)" no

check "dirty: left and named" "$(line_for dirty "$out")" "left repo feat/dirty uncommitted changes"
check "dirty: worktree kept" "$(exists repo dirty)" yes

check "unmerged: left and named" "$(line_for unmerged "$out")" "left repo feat/unmerged not merged"
check "unmerged: branch kept" "$(has_branch repo unmerged)" yes

check "fresh at origin/main: left and named" "$(line_for fresh "$out")" "left repo feat/fresh no commits yet"
check "fresh at origin/main: worktree kept" "$(exists repo fresh)" yes
check "rebased onto origin/main without commits: left and named" "$(line_for caught-up "$out")" \
    "left repo feat/caught-up no commits yet"

check "commits after the merged pull request: left and named" "$(line_for continued "$out")" \
    "left repo feat/continued commits after its merged pull request"
check "commits after the merged pull request: branch kept" "$(has_branch repo continued)" yes

check "pull-request lookup error: left and named" "$(line_for lookup-error "$out")" \
    "left repo feat/lookup-error pull-request lookup failed"

check "current directory: left and named" "$(line_for here "$out")" "left repo feat/here current directory"
check "current directory: worktree kept" "$(exists repo here)" yes

check "main checkout untouched" "$(git -C "$test_root/repo" branch --show-current)" main

# --- no repo arguments: the repos of the repo map ---
make_repo mapped
add_worktree mapped done
commit_in mapped done
git -C "$test_root/mapped-worktrees/done" push -q origin HEAD:main
cat > "$CLAUDE_REPO_MAP" <<EOF
# Local Repo Map

| Repo | Org | Path | Summary |
|------|-----|------|---------|
| mapped | test | $test_root/mapped | A fixture |
EOF
out="$(bash "$SCRIPT" 2>&1)"
check "no arguments: repo map repos pruned" "$(line_for done "$out")" "removed mapped feat/done"
check "no arguments: worktree gone" "$(exists mapped done)" no

out="$(bash "$SCRIPT" "$test_root/mapped" 2>&1)"
check "repo with only its main checkout: nothing reported" "$(tail -1 <<< "$out")" "0 removed, 0 left"

# --- --log appends the report to a file, creating its directory ---
log="$test_root/logs/prune.log"
out="$(bash "$SCRIPT" --log "$log" "$test_root/mapped" 2>&1)"
bash "$SCRIPT" --log "$log" "$test_root/mapped" > /dev/null 2>&1
check "--log: nothing on stdout" "$out" ""
check "--log: each run appended" "$(grep -c '^0 removed, 0 left$' "$log" 2> /dev/null)" 2

echo
if [[ $failures -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
