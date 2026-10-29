# The plan registry: named sets of vault tasks or Linear tickets. See `plan --help`.

plan() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: plan register <slug> <note|document URL> [--title <title>]
       plan list [--json]
       plan status <slug> [--json]
       plan close <slug> closed|cancelled [--reason <reason>]

The registry of plans; the registry row says where a plan lives and whether it is active.
  vault       A note whose "## Tasks" section lists its tasks as [[ID]] links; each task links
              back with plan: in its frontmatter.
  linear-doc  A Linear document whose "## Tasks" section lists its tickets; each ticket links back
              with a "Plan: <document URL>" line in its body. Read live from Linear. Statuses map
              from the state's type: triage, backlog, unstarted -> todo; started -> in-progress,
              or in-review for a state named "In Review"; completed -> done; canceled,
              duplicate -> cancelled. Blockers are the tickets that "block" it in Linear.

  register  Adds the plan under <slug>: a note at <note> (a path relative to the vault), or the
            Linear document at an https://linear.app/ URL. The title defaults to the note's
            heading or the document's title.
  list      Every registered plan: slug, status, home, title.
  status    The plan's members with their statuses, how many are done, in review and remaining
            (todo, in-progress or missing), the frontier (todo members whose blockers are all
            done), the early start (todo members whose open blockers are all members in progress
            or in review in another workspace: they can be built now and merged after their
            blockers) and any drift between the "## Tasks" list and the members' links back.
            Drift is reported, never repaired. A member's workspace is its task's workspace, or
            the "Workspace:" line of its ticket.
            --json prints {slug, title, status, done, inReview, remaining, members, frontier,
            earlyStart, drift}.
            A vault task's blocker may be a Linear ticket outside the plan (see `task --help`).
            Started, it counts as work in another workspace, so the task is an early start.
  close     Ends an active plan: sets its status, closed_at and close_reason (from --reason).
            closed is refused while a member under "## Tasks" is todo, in-progress, in-review or
            missing; cancelled is not. The members are left as they are — cancel or detach them
            first.

The vault is $CLAUDE_VAULT_DIR, by default C:/work/github/OleksiiZuiev/projects-obsidian.
The registry is the plans table of $CLAUDE_DATA_DB (see `sessions --help`).
Linear is read with the API key in $CLAUDE_LINEAR_KEY_FILE, by default ~/.config/linear/api-key.
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
