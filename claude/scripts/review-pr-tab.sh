#!/bin/bash
# Open a Claude tab reviewing a pull request from its URL. See `review-pr-tab.sh --help`.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: review-pr-tab.sh <PR URL> [<review-arg>...]
       review-pr-tab.sh --release <worktree>

Open a Windows Terminal tab running `/ds:review <N> <review-arg>...` in a detached worktree of the
pull request's head, so the review's lanes can read the files around the diff from disk.

The local clone comes from the repo map, by the URL's owner and repo. The worktree is
<clone>-worktrees/pr-<N>-<short head sha>: a second tab for the same head opens in the same
worktree, and a new push gets a new one. When a tab's claude exits it runs --release, and the last
tab released removes the worktree.

Arguments:
  <PR URL>          https://github.com/<owner>/<repo>/pull/<N>
  <review-arg>      Passed on to /ds:review in the tab (+comment, --bar, --to, --since)

Environment:
  CLAUDE_REPO_MAP   Repo map to resolve the clone from (default: per OS, see ~/.bash.d/repo-roots.sh)

Options:
  --release <worktree>  Drop one tab from the worktree; remove it when none is left
  -h, --help            Show this help and exit
EOF
    exit 0
fi

# Per worktree, in its private git dir: how many review tabs are open in it.
tab_count_file() { echo "$(git -C "$1" rev-parse --path-format=absolute --git-dir)/review-tabs"; }

add_tabs() { # $1 worktree  $2 +1 or -1; prints the new count
    local file count
    file=$(tab_count_file "$1")
    count=$(( $(cat "$file" 2> /dev/null || echo 0) + $2 ))
    echo "$count" > "$file"
    echo "$count"
}

release() { # $1 worktree
    local wt="$1" common main
    common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir) || return 1
    main=$(dirname "$common")
    (( $(add_tabs "$wt" -1) > 0 )) && return 0
    if ! git -C "$main" -c core.longpaths=true worktree remove --force "$wt" > /dev/null 2>&1; then
        # Windows fails deep node_modules trees with "Directory not empty" after deleting part of them.
        [[ "$wt" =~ -worktrees/pr-[^/]+$ ]] && rm -rf "$wt" && git -C "$main" worktree prune || return 1
    fi
}

if [[ "$1" == "--release" ]]; then
    [[ -n "$2" ]] || { echo "review-pr-tab.sh: --release needs a worktree" >&2; exit 2; }
    release "$2"
    exit
fi

url="$1"
shift
if [[ ! "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)([/?#].*)?$ ]]; then
    echo "review-pr-tab.sh: '$url' is not a pull request URL (https://github.com/<owner>/<repo>/pull/<N>)" >&2
    exit 2
fi
owner="${BASH_REMATCH[1]}" name="${BASH_REMATCH[2]}" number="${BASH_REMATCH[3]}"

[[ -r "$HOME/.bash.d/repo-roots.sh" ]] && . "$HOME/.bash.d/repo-roots.sh"
map="${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}"
clone=$(awk -F'|' -v repo="${name,,}" -v org="${owner,,}" 'NF > 4 {
    r = tolower($2); o = tolower($3); p = $4
    gsub(/^[ \t]+|[ \t\r]+$/, "", r); gsub(/^[ \t]+|[ \t\r]+$/, "", o); gsub(/^[ \t]+|[ \t\r]+$/, "", p)
    if (r == repo && o == org) { print p; exit }
}' "$map" 2> /dev/null)
if [[ -z "$clone" ]]; then
    echo "review-pr-tab.sh: $owner/$name is not in the repo map ($map)" >&2
    exit 1
fi

git -C "$clone" fetch -q origin "pull/$number/head" || exit 1
head=$(git -C "$clone" rev-parse FETCH_HEAD) || exit 1

main=$(dirname "$(git -C "$clone" rev-parse --path-format=absolute --git-common-dir)")
wt="$(dirname "$main")/$(basename "$main")-worktrees/pr-$number-${head:0:7}"
if [[ -d "$wt" && "$(git -C "$wt" rev-parse HEAD 2> /dev/null)" == "$head" ]]; then
    how=reused
else
    git -C "$main" worktree add -q --detach "$wt" "$head" || exit 1
    how=new
fi

# A function already defined wins, so the tab can be stood in for.
if ! declare -F claude_tab > /dev/null; then
    source "$(dirname "${BASH_SOURCE[0]}")/claude-tab.sh" || exit 1
fi

add_tabs "$wt" 1 > /dev/null
release_cmd="bash $(printf %q "$HOME/.claude/scripts/review-pr-tab.sh") --release $(printf %q "$wt")"
if ! claude_tab --then "$release_cmd" "PR #$number" "$wt" "/ds:review $number${*:+ $*}"; then
    release "$wt"
    exit 1
fi
echo "Review tab opened for PR #$number in $wt ($how)"
