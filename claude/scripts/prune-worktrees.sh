#!/bin/bash
# Remove the worktrees and branches whose work has reached origin/main. See `prune-worktrees.sh --help`.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: prune-worktrees.sh [--dry-run] [--log <file>] [repo-path...]

Remove every worktree, and its local branch, whose branch has reached origin/main, in the given
repos or, with none given, in every repo of the repo map. Never prompts; prints one line per
worktree: removed (or "would remove" with --dry-run), or left with the reason.

A branch has reached origin/main when it was committed on and is an ancestor of origin/main
(a direct push or a merge commit), or when a merged pull request has the branch's tip as its head
(a squash merge). A worktree is left when its branch has not reached origin/main, when it has
uncommitted changes, when it is locked, detached or missing, or when it holds the current directory.

Under WSL, repos on a Windows drive are skipped: their worktrees belong to Windows git.

Environment:
  CLAUDE_REPO_MAP       Repo map read with no repo-path (default: per OS, see ~/.bash.d/repo-roots.sh)
  CLAUDE_OVERLAYS_DIR   Overlay directory naming the GitHub account (see repo-gh --help)

Options:
  --dry-run     Report what would be removed and change nothing
  --log <file>  Append the report to <file> instead of printing it, creating its directory
  -h, --help    Show this help and exit
EOF
    exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/repo-gh.sh"

dry_run=false
log=""
while [[ "$1" == -* ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --log)
            [[ -n "$2" ]] || { echo "prune-worktrees.sh: --log needs a file" >&2; exit 2; }
            log="$2"; shift 2
            ;;
        *) echo "prune-worktrees.sh: unknown option '$1' (see --help)" >&2; exit 2 ;;
    esac
done

if [[ -n "$log" ]]; then
    mkdir -p "$(dirname "$log")"
    exec >> "$log" 2>&1
fi

# A scheduled run starts without the SSH agent an interactive shell loads (see ~/.bashrc), and must
# fail rather than wait on a passphrase or credential prompt no one can answer. Git Credential
# Manager ignores GIT_TERMINAL_PROMPT and opens a sign-in window for an HTTPS remote.
if [[ -z "$SSH_AUTH_SOCK" && -r "$HOME/.ssh/agent.env" ]]; then
    . "$HOME/.ssh/agent.env" > /dev/null
fi
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never

native_path() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}

on_wsl=false
[[ -r /proc/version ]] && grep -qi microsoft /proc/version && on_wsl=true

repos=("$@")
if [[ ${#repos[@]} -eq 0 ]]; then
    # A scheduled run skips ~/.bashrc, so the per-OS map default may not be set yet.
    [[ -r "$HOME/.bash.d/repo-roots.sh" ]] && . "$HOME/.bash.d/repo-roots.sh"
    map="${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}"
    mapfile -t repos < <(awk -F'|' 'NF > 4 {
        p = $4; gsub(/^[ \t]+|[ \t\r]+$/, "", p)
        if (p ~ /^(\/|[A-Za-z]:)/) print p
    }' "$map")
fi

here="$(native_path "$PWD")"
removed=0
left=0

report() { # $1 outcome  $2 repo  $3 branch  [$4 reason]
    printf '%-13s %-28s %s%s\n' "$1" "$2" "$3" "${4:+  $4}"
}
leave() { report left "$@"; left=$((left + 1)); }

# Prints why the branch has not reached origin/main, or nothing when it has.
unreached_reason() { # $1 main checkout  $2 branch  $3 tip
    local main="$1" branch="$2" tip="$3" pr_head
    # A branch never committed on sits on a commit of origin/main (where it was created, or where
    # a rebase or fast-forward moved it), so ancestry proves nothing for it. A reflog expired
    # past its creation counts as committed on.
    local committed_on=false reflog
    reflog=$(git -C "$main" reflog show --format=%gs "refs/heads/$branch" 2> /dev/null)
    if grep -qE '^(commit|cherry-pick)' <<< "$reflog" || ! grep -q '^branch: Created' <<< "$reflog"; then
        committed_on=true
    fi

    if $committed_on && git -C "$main" rev-parse --verify --quiet origin/main > /dev/null &&
        git -C "$main" merge-base --is-ancestor "$tip" origin/main; then
        return
    fi

    if ! pr_head=$(repo-gh -C "$main" pr list --head "$branch" --state merged \
        --json headRefOid --jq '.[].headRefOid' --limit 1 2> /dev/null); then
        echo "pull-request lookup failed"
    elif [[ "$pr_head" == "$tip" ]]; then
        return
    elif [[ -n "$pr_head" ]]; then
        echo "commits after its merged pull request"
    elif $committed_on; then
        echo "not merged"
    else
        echo "no commits yet"
    fi
}

remove_worktree() { # $1 main checkout  $2 worktree  $3 branch
    local main="$1" wt="$2" branch="$3"
    if ! git -C "$main" -c core.longpaths=true worktree remove "$wt" > /dev/null 2>&1; then
        # Windows fails deep node_modules trees with "Directory not empty" after deleting part of
        # them; finishing with rm keeps a half-deleted worktree from reading as dirty on the next run.
        [[ "$wt" =~ -worktrees/[^/]+ ]] && rm -rf "$wt" && git -C "$main" worktree prune || return 1
    fi
    git -C "$main" branch -D "$branch" > /dev/null
}

prune_repo() { # $1 repo path
    local repo name main wt="" branch="" head="" locked=false prunable=false first=true
    repo=$(native_path "$1")
    name=$(basename "$repo")

    if $on_wsl && [[ "$1" =~ ^/(mnt/)?[a-z]/ ]]; then
        return
    fi
    # `git -C ""` runs in the current directory, which is not the repo asked for.
    if [[ -z "$repo" ]] || ! main=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2> /dev/null); then
        report skipped "$name" "not a git repository"
        return
    fi
    main=$(dirname "$main")
    local fetch_error
    if ! fetch_error=$(git -C "$main" fetch -q origin 2>&1); then
        report skipped "$name" "fetch from origin failed: $(head -1 <<< "$fetch_error" | tr -d '\r')"
        return
    fi

    local entries=()
    while IFS= read -r line; do
        case "$line" in
            "worktree "*) wt="${line#worktree }" ;;
            "HEAD "*) head="${line#HEAD }" ;;
            "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
            locked*) locked=true ;;
            prunable*) prunable=true ;;
            "")
                [[ -n "$wt" ]] && ! $first && entries+=("$wt|$branch|$head|$locked|$prunable")
                [[ -n "$wt" ]] && first=false
                wt="" branch="" head="" locked=false prunable=false
                ;;
        esac
    done < <(git -C "$main" worktree list --porcelain; echo)

    local entry reason
    for entry in "${entries[@]}"; do
        IFS='|' read -r wt branch head locked prunable <<< "$entry"
        if [[ -z "$branch" ]]; then
            leave "$name" "$wt" "detached HEAD"
        elif $locked; then
            leave "$name" "$branch" "locked"
        elif $prunable; then
            leave "$name" "$branch" "directory missing"
        elif [[ "$here/" == "$wt/"* ]]; then
            leave "$name" "$branch" "current directory"
        elif reason=$(unreached_reason "$main" "$branch" "$head") && [[ -n "$reason" ]]; then
            leave "$name" "$branch" "$reason"
        elif [[ -n "$(git -C "$wt" status --porcelain 2> /dev/null)" ]]; then
            leave "$name" "$branch" "uncommitted changes"
        elif $dry_run; then
            report "would remove" "$name" "$branch"
            removed=$((removed + 1))
        elif remove_worktree "$main" "$wt" "$branch"; then
            report removed "$name" "$branch"
            removed=$((removed + 1))
        else
            leave "$name" "$branch" "removal failed: $wt"
        fi
    done
}

echo "prune-worktrees $(date '+%Y-%m-%d %H:%M:%S')$($dry_run && echo ' (dry run)')"
for repo in "${repos[@]}"; do
    prune_repo "$repo"
done
echo "$removed $($dry_run && echo 'to remove' || echo removed), $left left"
