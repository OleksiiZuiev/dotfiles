# The plan registry: named sets of vault tasks. See `plan --help`.

_PLAN_SH="${BASH_SOURCE[0]}"
source "$(dirname "$_PLAN_SH")/../lib/windows-node.sh"

plan() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: plan register <slug> <note> [--title <title>]
       plan list [--json]
       plan status <slug> [--json]

The registry of plans. A vault plan is a note whose "## Tasks" section lists its tasks as [[ID]]
links; the registry row says the note is a plan and whether it is active.

  register  Adds the note at <note> (a path relative to the vault) under <slug>. The title defaults
            to the note's heading.
  list      Every registered plan: slug, status, home, title.
  status    The plan's tasks with their statuses, how many are done and remaining, the frontier
            (todo tasks whose blockers are all done) and any drift between the note's "## Tasks"
            list and the tasks' plan: links. Drift is reported, never repaired.
            --json prints {slug, title, status, done, remaining, members, frontier, drift}.

The vault is $CLAUDE_VAULT_DIR, by default C:/work/github/OleksiiZuiev/projects-obsidian.
The registry is the plans table of $CLAUDE_DATA_DB (see `sessions --help`).

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi
    # A Windows process started from WSL sees only the variables WSLENV names.
    WSLENV="${WSLENV:+$WSLENV:}CLAUDE_VAULT_DIR:CLAUDE_DATA_DB" MSYS2_ARG_CONV_EXCL='*' \
        _windows_node "$(dirname "$_PLAN_SH")/plan.mjs" "$@"
}
