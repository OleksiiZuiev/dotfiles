# Run `gh` as the GitHub account the current repo's overlay names. See `repo-gh --help`.

repo-gh() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: repo-gh <gh arguments>

Run gh as the GitHub account the current repo names, without switching the active gh account.

The account is the `github-account: <login>` line in the `## Workflow` section of the repo's
overlay, ~/.claude/overlays/<repo-key>.md (the format is defined in ~/.claude/commands/ds/distill.md).
The repo key is the main checkout's directory name, so every worktree of a repo resolves the same
overlay. With an account, gh runs with GH_TOKEN set to that account's token from
`gh auth token --user <login>`; with no overlay, no line, or outside a git repo, gh runs as the
active account. The account must be logged in to gh: a missing token fails before gh runs.

Environment:
  CLAUDE_OVERLAYS_DIR   Overlay directory (default: ~/.claude/overlays)

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    local common_dir overlay account token
    if common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
        overlay="${CLAUDE_OVERLAYS_DIR:-$HOME/.claude/overlays}/$(basename "$(dirname "$common_dir")").md"
        [[ -f "$overlay" ]] && account=$(awk '
            /^## / { in_workflow = ($0 == "## Workflow") }
            in_workflow && /^github-account:/ { sub(/^github-account:[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }
        ' "$overlay")
    fi

    if [[ -z "$account" ]]; then
        gh "$@"
        return
    fi
    if ! token=$(gh auth token --user "$account"); then
        echo "repo-gh: no gh token for $account (named in $overlay); run: gh auth login" >&2
        return 1
    fi
    GH_TOKEN="$token" gh "$@"
}
