# Run `gh` as the GitHub account the repo's overlay names. See `repo-gh --help`.

repo-gh() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: repo-gh [-C <dir>] <gh arguments>

Run gh as the GitHub account the current repo names, without switching the active gh account.
With -C, like `git -C`, the repo is the one at <dir>: its overlay names the account and gh runs
inside <dir>, so gh also takes the repo from <dir>'s remote. A <dir> that is not a directory fails
before gh runs.

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

    local dir=. common_dir overlay account token
    if [[ "$1" == "-C" ]]; then
        if [[ -z "$2" || ! -d "$2" ]]; then
            echo "repo-gh: -C needs a directory; got '${2-}'" >&2
            return 1
        fi
        dir="$2"
        shift 2
    fi

    if common_dir=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
        overlay="${CLAUDE_OVERLAYS_DIR:-$HOME/.claude/overlays}/$(basename "$(dirname "$common_dir")").md"
        [[ -f "$overlay" ]] && account=$(awk '
            /^## / { in_workflow = ($0 == "## Workflow") }
            in_workflow && /^github-account:/ { sub(/^github-account:[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }
        ' "$overlay")
    fi

    if [[ -z "$account" ]]; then
        (cd "$dir" && gh "$@")
        return
    fi
    if ! token=$(gh auth token --user "$account"); then
        echo "repo-gh: no gh token for $account (named in $overlay); run: gh auth login" >&2
        return 1
    fi
    (cd "$dir" && GH_TOKEN="$token" gh "$@")
}
