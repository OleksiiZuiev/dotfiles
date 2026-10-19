# Identify the branch the current branch is stacked on, for use as the base of a
# stacked pull request. See `stack-parent --help`.

stack-parent() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: stack-parent

Print the branch the current branch is stacked on, together with that branch's
open PR number. Prints nothing and returns 1 when the current branch is based
on main.

A stack parent is a remote branch whose tip is an ancestor of HEAD but is not
yet in origin/main — work your branch already contains that main does not have.
Candidates are ranked nearest first (fewest commits between their tip and HEAD)
and the first one with an open PR wins, because only a branch with an open PR
can be linked into a GitHub stack.

Output (one space-separated line):
  <parent-branch> <pr-number>   parent found, PR open
  <parent-branch> -             parent found, no open PR (cannot be linked)
  (nothing, exit 1)             branch is based on main

Fetches origin/main first — the whole rule is stated relative to it.

Requires: gh, authenticated as the account `repo-gh` resolves for the repo.

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "stack-parent: not a git repository" >&2
        return 1
    fi

    git fetch --quiet origin main 2>/dev/null

    local current
    current=$(git branch --show-current)

    # Rank every remote branch whose work HEAD already contains but main does not,
    # nearest first. `git branch -r --contains <fork-point>` answers the reverse
    # question — every branch cut from that commit — so it returns unrelated
    # branches whenever several were cut from the same tip.
    local ranked
    ranked=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin \
        | grep -v -E '^origin/(HEAD|main|master)$' \
        | while read -r ref; do
              local branch="${ref#origin/}"
              [[ "$branch" == "$current" ]] && continue
              git merge-base --is-ancestor "$ref" HEAD 2>/dev/null || continue
              git merge-base --is-ancestor "$ref" origin/main 2>/dev/null && continue
              local distance
              distance=$(git rev-list --count "${ref}..HEAD")
              # Distance 0 is a branch sitting on your own tip — a sibling, not a
              # parent; basing a PR on it would produce an empty diff.
              [[ "$distance" -eq 0 ]] && continue
              echo "$distance $branch"
          done \
        | sort -n)

    [[ -z "$ranked" ]] && return 1

    local nearest=""
    local distance branch pr
    while read -r distance branch; do
        [[ -z "$nearest" ]] && nearest="$branch"
        pr=$(repo-gh pr list --head "$branch" --state open --json number -q '.[0].number' 2>/dev/null)
        if [[ -n "$pr" ]]; then
            echo "$branch $pr"
            return 0
        fi
    done <<< "$ranked"

    # Nothing in the chain has an open PR. Report the nearest anyway so the caller
    # can still target the right base, and signal that linking is not possible.
    echo "$nearest -"
}
