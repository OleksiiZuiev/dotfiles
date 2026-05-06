#!/bin/bash
# Claude Code statusline — reads JSON from stdin, outputs "model | repo | branch"
# Uses pure bash for speed (node/powershell too slow for 300ms debounce on Windows)

input=$(cat)

# Extract display_name value with bash string manipulation
model="${input#*\"display_name\":\"}"
model="${model%%\"*}"

# Extract current_dir value, then get leaf directory
dir="${input#*\"current_dir\":\"}"
dir="${dir%%\"*}"
# Leaf: try forward slash first, then backslash
leaf="${dir##*/}"
[ "$leaf" = "$dir" ] && leaf="${dir##*\\}"

# Convert Windows path (C:\foo\bar) to Git Bash path (/c/foo/bar) if needed
gitdir="$dir"
if [[ "$gitdir" =~ ^[A-Za-z]:\\ ]]; then
    drive="${gitdir:0:1}"
    drive="${drive,,}"
    gitdir="/${drive}/${gitdir:3}"
    gitdir="${gitdir//\\//}"
fi

# Repo name — basename of the main worktree (parent of the shared .git dir).
# On a worktree, --git-common-dir points to the main repo's .git, so this stays
# stable across worktrees instead of showing the worktree folder name.
common_dir=$(git -C "$gitdir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
repo_name=""
[ -n "$common_dir" ] && repo_name=$(basename "$(dirname "$common_dir")")

branch=$(git -C "$gitdir" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Build output — prefer repo name; fall back to leaf when not in a repo
second="${repo_name:-$leaf}"
out="$model | $second"
[ -n "$branch" ] && out="$out | $branch"
echo "$out"
