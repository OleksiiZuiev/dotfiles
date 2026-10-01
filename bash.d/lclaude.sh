# Smart Claude launcher with repository history. See `lclaude --help`.

lclaude() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: lclaude [claude-args...]

Smart Claude launcher: pick a recent project from an fzf menu (numbered menu
without fzf), then launch Claude there. Any arguments are forwarded to claude.
History is kept in ~/.claude_repos (up to 30 repos).

  - In a git repo: the current dir is listed first and pre-selected (Enter
    launches immediately).
  - Outside a git repo: history is shown with a "[Stay in current directory]"
    option.

Note: this flag shows lclaude's own help. For Claude's own help, run
`claude --help`.

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    local real_claude
    real_claude=$(claude_bin)

    # Refresh repo map in background
    bash "$HOME/.claude/scripts/update-repo-map.sh" &>/dev/null &

    local dir
    dir=$(_repo_pick) || return 1

    if [[ "$dir" != "$(pwd)" ]]; then
        echo "Changing to: $dir"
        cd "$dir" || return 1
    fi
    bash "$HOME/.claude/scripts/record-repo.sh" "$dir"
    clear
    "$real_claude" "$@"
}
