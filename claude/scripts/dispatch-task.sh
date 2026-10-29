#!/bin/bash
# Dispatch one task: open a Claude tab running `/task-run <ID>` in the task's workspace, in a new
# worktree unless the workspace runs in its own checkout. Prints the directory the tab opened in.
#
# <workspace> is a repo key: `vault` for the vault, else `owner/repo` (or a bare repo name) looked
# up in the repo map. The vault and a repo whose overlay ~/.claude/overlays/<repo>.md says
# `worktree: no` are shared checkouts: the tab opens in the checkout itself and --branch is unused.
# Any other workspace needs --branch for its worktree; --record-branch then records it on the vault
# task with `task set <ID> branch`. --base <branch> cuts a new worktree branch from origin/<branch>,
# fetched first, instead of from origin/main: a stacked start on a blocker's pull request.
# Every tab outside the vault gets the vault as an added directory.
# --context <text> follows the ID in the prompt, as `/task-run`'s extra context.
#
# Usage: dispatch-task.sh <ID> <workspace> [--branch <name>] [--base <branch>] [--record-branch]
#                         [--context <text>] [--model <model>] [--effort <effort>]

usage="Usage: dispatch-task.sh <ID> <workspace> [--branch <name>] [--base <branch>] [--record-branch] [--context <text>] [--model <model>] [--effort <effort>]"

# Prints the Path column of the repo map row matching <workspace>.
repo_path() {
    local workspace="$1" org="" repo="${1##*/}"
    [[ "$workspace" == */* ]] && org="${workspace%%/*}"
    awk -F'|' -v org="$org" -v repo="$repo" '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        NF >= 5 && trim($2) == repo && (org == "" || trim($3) == org) { print trim($4); exit }
    ' "${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}"
}

dispatch_task() {
    local id="$1" workspace="$2"
    if [[ -z "$id" || -z "$workspace" ]]; then
        echo "$usage" >&2
        return 1
    fi
    shift 2
    local branch="" base="" record_branch="" context="" model_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch) branch="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            --record-branch) record_branch=1; shift ;;
            --context) context="$2"; shift 2 ;;
            --model | --effort) model_args+=("$1" "$2"); shift 2 ;;
            *) echo "dispatch-task.sh: unknown argument '$1'" >&2; echo "$usage" >&2; return 1 ;;
        esac
    done

    if [[ -n "$WSL_DISTRO_NAME" ]]; then
        echo "dispatch-task.sh: dispatching from WSL is not supported; run it from a Windows shell" >&2
        return 1
    fi

    local scripts="$HOME/.claude/scripts"
    local vault="${CLAUDE_VAULT_DIR:-C:/work/github/OleksiiZuiev/projects-obsidian}"
    local dir add_dir=()
    if [[ "$workspace" == "vault" ]]; then
        dir="$vault"
    else
        local checkout
        checkout=$(repo_path "$workspace")
        if [[ -z "$checkout" ]]; then
            echo "dispatch-task.sh: workspace '$workspace' is not in the repo map" >&2
            return 1
        fi
        add_dir=(--add-dir "$vault")
        if grep -Eq '^worktree:[[:space:]]*no[[:space:]]*$' "$HOME/.claude/overlays/${workspace##*/}.md" 2> /dev/null; then
            dir="$checkout"
        else
            if [[ -z "$branch" ]]; then
                echo "dispatch-task.sh: workspace '$workspace' gets a worktree, so --branch is required" >&2
                return 1
            fi
            local base_args=()
            if [[ -n "$base" ]]; then
                if ! git -C "$checkout" fetch origin "$base" >&2; then
                    echo "dispatch-task.sh: cannot fetch base branch '$base' in $checkout" >&2
                    return 1
                fi
                base_args=("origin/$base")
            fi
            dir=$(bash "$scripts/make-worktree.sh" "$checkout" "$branch" "${base_args[@]}") || return 1
            if [[ -n "$record_branch" ]]; then
                source "$scripts/tasks/task.sh" && task set "$id" branch "$branch" > /dev/null || return 1
            fi
        fi
    fi

    bash "$scripts/claude-tab.sh" "$id" "$dir" "/task-run $id${context:+ $context}" "${model_args[@]}" "${add_dir[@]}" || return 1
    echo "$dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dispatch_task "$@"
fi
