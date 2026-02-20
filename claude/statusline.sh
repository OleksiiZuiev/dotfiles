#!/bin/bash
# Claude Code statusline — reads JSON from stdin, outputs "model | dir | branch"
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

# Git branch — run git in the project directory from the JSON input
# Convert Windows path (C:\foo\bar) to Git Bash path (/c/foo/bar) if needed
gitdir="$dir"
if [[ "$gitdir" =~ ^[A-Za-z]:\\ ]]; then
    drive="${gitdir:0:1}"
    drive="${drive,,}"
    gitdir="/${drive}/${gitdir:3}"
    gitdir="${gitdir//\\//}"
fi
branch=$(git -C "$gitdir" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Build output
out="$model | $leaf"
[ -n "$branch" ] && out="$out | $branch"
echo "$out"
