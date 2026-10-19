# The plan registry: named sets of vault tasks. See `plan --help`.

plan() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: plan register <slug> <note> [--title <title>]
       plan list [--json]
       plan status <slug> [--json]
       plan close <slug> closed|cancelled [--reason <reason>]

The registry of plans. A vault plan is a note whose "## Tasks" section lists its tasks as [[ID]]
links; the registry row says the note is a plan and whether it is active.

  register  Adds the note at <note> (a path relative to the vault) under <slug>. The title defaults
            to the note's heading.
  list      Every registered plan: slug, status, home, title.
  status    The plan's tasks with their statuses, how many are done, in review and remaining
            (todo, in-progress or missing), the frontier (todo tasks whose blockers are all done)
            and any drift between the note's "## Tasks" list and the tasks' plan: links. Drift is
            reported, never repaired.
            --json prints {slug, title, status, done, inReview, remaining, members, frontier, drift}.
  close     Ends an active plan: sets its status, closed_at and close_reason (from --reason).
            closed is refused while a task under "## Tasks" is todo, in-progress, in-review or
            missing;
            cancelled is not. The tasks are left as they are — cancel or detach them first.

The vault is $CLAUDE_VAULT_DIR, by default C:/work/github/OleksiiZuiev/projects-obsidian.
The registry is the plans table of $CLAUDE_DATA_DB (see `sessions --help`).
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
    # A Windows process started from WSL sees only the variables WSLENV names.
    WSLENV="${WSLENV:+$WSLENV:}CLAUDE_VAULT_DIR:CLAUDE_DATA_DB" MSYS2_ARG_CONV_EXCL='*' \
        _windows_node "$scripts/plans/plan.mjs" "$@"
}
