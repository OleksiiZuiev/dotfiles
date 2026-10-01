# VSCode launcher with repository history. See `lcode --help`.

lcode() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: lcode [code-args...]

Pick a recent project from the same menu as lclaude (shared ~/.claude_repos
history), then open it in VSCode. Your shell's directory is left unchanged.
Any arguments are forwarded to code.

  - In a git repo: the current dir is listed first and pre-selected (Enter
    opens it immediately).
  - Outside a git repo: history is shown with a "[Stay in current directory]"
    option.

Note: this flag shows lcode's own help. For VSCode's own help, run
`code --help`.

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    local dir
    dir=$(_repo_pick) || return 1

    bash "$HOME/.claude/scripts/record-repo.sh" "$dir"
    code "$@" "$dir"
}
