# Per-OS repo roots and repo-map location for update-repo-map.sh.

# WSL reaches both the ext4 clones and the Windows ones; a Windows shell cannot
# usefully reach ext4. Each side keeps its own map, listing what it can edit.
if [ -r /proc/version ] && grep -qi microsoft /proc/version; then
    export CLAUDE_GITHUB_ROOTS="$HOME/work/github:/c/work/github"
    export CLAUDE_REPO_MAP="$HOME/.claude/repo-map.md"
fi
