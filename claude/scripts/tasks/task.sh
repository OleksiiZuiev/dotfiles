# Vault tasks with IDs and a status in frontmatter. See `task --help`.

task() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: task new <project> <slug> [--title <title>] [--blocked-by <ID>...] [--plan <note>] [--status <status>]
       task set <ID> status <status>
       task set <ID> blocked-by [<ID>...]
       task set <ID> plan
       task list <project> [--json]

The one writer of vault task files: projects/<project>/tasks/<ID> <slug>.md, with id, status,
blocked-by and plan in frontmatter.

  new   Claims the project's next ID (prefix from `id-prefix:` in projects/<project>/<project>.md)
        and writes the task from templates/task.md. Prints the ID, then the path.
        --title defaults to the slug; --status to todo. --blocked-by takes one or more IDs.
  set   Changes a task's status, or replaces its whole blocked-by list; no IDs clears it. A
        blocked-by ID must be a task of the same project, not the task itself, and must not
        already be blocked by it, directly or through other tasks (a cycle). Nothing is written
        when a check fails. `set <ID> plan` clears the plan: link; a plan is only ever
        given with `new --plan`.
  list  The project's todo and in-progress tasks by ID, one per line, tab-separated: ID, status,
        title (the task's heading), and its blockers — the blocked-by tasks not yet done, as
        "VE-3 (todo), VE-7 (cancelled)"; empty when the task is unblocked.
        --json prints an array of {id, status, title, path, blockers: [{id, status}]}.

Statuses: todo, in-progress, done, cancelled.
The vault is $CLAUDE_VAULT_DIR, by default C:/work/github/OleksiiZuiev/projects-obsidian.
The scripts are read from $CLAUDE_SCRIPTS_DIR, by default ~/.claude/scripts.

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi
    # A shell Claude Code restores from a snapshot keeps this function but not the underscore helpers
    # or the variables set when this file was sourced, so the files are found from here, at call time.
    local scripts="${CLAUDE_SCRIPTS_DIR:-$HOME/.claude/scripts}"
    source "$scripts/lib/windows-node.sh" || return 1
    # A Windows process started from WSL sees only the variables WSLENV names. Git Bash would
    # rewrite an argument starting with / (a title like "/plan-next") into a Windows path.
    WSLENV="${WSLENV:+$WSLENV:}CLAUDE_VAULT_DIR" MSYS2_ARG_CONV_EXCL='*' \
        _windows_node "$scripts/tasks/task.mjs" "$@"
}
