#!/bin/bash
# Tests for the `plan` CLI (plan.sh, plan.mjs) against a fixture vault and database.
# Run: bash claude/scripts/plans/test_plan.sh
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/plan.sh"
source "$SCRIPT_DIR/../tasks/task.sh"
fails=0

# Fixtures under $HOME so cygpath round-trips (/tmp maps elsewhere on Git Bash).
root="$HOME/.plan-test.$$"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/templates" "$root/projects/ve/tasks" "$root/projects/ve/work-notes"
printf '# {{title}}\n\n## Description\n' > "$root/templates/task.md"
printf -- '---\ncreated: 2026-01-01\nid-prefix: VE\n---\n\n# VE\n' > "$root/projects/ve/ve.md"
export CLAUDE_VAULT_DIR="$(cygpath -w "$root")"
export CLAUDE_DATA_DB="$(cygpath -w "$root/claude-data.db")"
note="projects/ve/work-notes/2026-01-01-ladder-plan.md"

check() { # $1 name  $2 actual  $3 expected
  if [[ "$2" == "$3" ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n      got [%s], want [%s]\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}
has() { # $1 haystack  $2 needle
  [[ "$1" == *"$2"* ]] && echo yes || echo "no: $1"
}
write_note() { # $@ the IDs listed under ## Tasks
  { printf -- '---\ntype: plan\n---\n\n# Ladder plan\n\n## Design\n\nSee [[VE-9]] for nothing.\n\n## Tasks\n\n'
    for id in "$@"; do printf -- '- [[%s]]\n' "$id"; done
    printf '\n## Open questions\n\n- [[VE-8]] is mentioned here and is not a member.\n'
  } > "$root/$note"
}
field() { # $1 JSON  $2 JavaScript expression over `s`
  node -e 'const s = JSON.parse(process.argv[1]); console.log(eval(process.argv[2]))' "$1" "$2"
}

# --- help ---
out=$(plan --help); code=$?
check "--help -> exit 0" "$code" 0
check "--help -> usage" "$(has "$out" "Usage: plan register")" yes

# --- register and list ---
write_note VE-1 VE-2 VE-3 VE-5
task new ve one --plan 2026-01-01-ladder-plan > /dev/null
task new ve two --blocked-by VE-1 --plan 2026-01-01-ladder-plan > /dev/null
task new ve three --blocked-by VE-2 --plan 2026-01-01-ladder-plan > /dev/null
task new ve cancelled-blocker > /dev/null
task new ve four --blocked-by VE-4 --plan 2026-01-01-ladder-plan > /dev/null
task set VE-1 status done
task set VE-4 status cancelled

out=$(plan register ladder "$note"); code=$?
check "register -> exit 0" "$code" 0
out=$(plan list --json)
check "list -> slug, title from the note's heading, active, vault" \
  "$(field "$out" 's.map((p) => [p.slug, p.title, p.status, p.home, p.locator].join("|")).join(",")')" \
  "ladder|Ladder plan|active|vault|$note"
check "list -> text names the slug" "$(has "$(plan list)" ladder)" yes

out=$(plan register ladder "$note" 2>&1); code=$?
check "register a duplicate slug -> fails" "$code" 1
check "register a duplicate slug -> says so" "$(has "$out" "already registered")" yes
out=$(plan register nope projects/ve/work-notes/missing.md 2>&1); code=$?
check "register a missing note -> fails" "$code" 1
check "register a missing note -> not in the list" "$(field "$(plan list --json)" 's.length')" 1
out=$(plan register titled "$note" --title "Given title" 2>&1)
check "register --title wins over the heading" \
  "$(field "$(plan list --json)" 's.find((p) => p.slug === "titled").title')" "Given title"

# --- status ---
out=$(plan status ladder --json); code=$?
check "status -> exit 0" "$code" 0
check "status -> done and remaining count members only" "$(field "$out" '[s.done, s.remaining].join("/")')" "1/3"
check "status -> a member listed outside ## Tasks is not counted" "$(field "$out" 's.members.length')" 4
check "status -> frontier is the todo task whose blockers are done" "$(field "$out" 's.frontier.join(",")')" VE-2
check "status -> a cancelled blocker keeps its dependent off the frontier" \
  "$(field "$out" 's.members.find((m) => m.id === "VE-5").blockers.map((b) => b.id + ":" + b.status).join(",")')" "VE-4:cancelled"
check "status -> no drift when both directions agree" "$(field "$out" 's.drift.length')" 0
check "status -> text names the frontier" "$(has "$(plan status ladder)" "frontier")" yes

# --- drift ---
task new ve six --plan 2026-01-01-ladder-plan > /dev/null
task new ve seven > /dev/null
write_note VE-1 VE-2 VE-3 VE-5 VE-7 VE-99
out=$(plan status ladder --json)
drift=$(field "$out" 's.drift.join(" ; ")')
check "drift -> task links the plan but is not listed" "$(has "$drift" "VE-6")" yes
check "drift -> listed task does not link the plan back" "$(has "$drift" "VE-7")" yes
check "drift -> listed ID with no task" "$(has "$drift" "VE-99")" yes
check "drift -> the mention outside ## Tasks is not drift" "$(has "$drift" "VE-8")" "no: $drift"

out=$(plan status unknown 2>&1); code=$?
check "status of an unregistered slug -> fails" "$code" 1

# --- close ---
check "--help -> documents close" "$(has "$(plan --help)" "plan close <slug>")" yes
plan_field() { # $1 slug  $2 property
  field "$(plan list --json)" "s.find((p) => p.slug === '$1').$2"
}
write_note VE-1 VE-2   # VE-1 done, VE-2 todo

out=$(plan close ladder closed 2>&1); code=$?
check "close closed with a todo member -> fails" "$code" 1
check "close closed with a todo member -> names it" "$(has "$out" VE-2)" yes
check "close closed with a todo member -> stays active" "$(plan_field ladder status)" active
out=$(plan close ladder finished 2>&1); code=$?
check "close with an unknown status -> fails" "$code" 1
check "close with an unknown status -> stays active" "$(plan_field ladder status)" active

out=$(plan close titled cancelled --reason "Dropped for now"); code=$?
check "close cancelled with a todo member -> exit 0" "$code" 0
check "close cancelled -> status and reason" \
  "$(plan_field titled status)|$(plan_field titled close_reason)" "cancelled|Dropped for now"
check "close cancelled -> closed_at set" "$(plan_field titled 'closed_at !== null')" true
out=$(plan close titled closed 2>&1); code=$?
check "close a plan that is not active -> fails" "$code" 1
check "close a plan that is not active -> keeps its status" "$(plan_field titled status)" cancelled

task set VE-2 status cancelled
out=$(plan close ladder closed); code=$?
check "close closed with only done and cancelled members -> exit 0" "$code" 0
check "close closed -> status closed, no reason" \
  "$(plan_field ladder status)|$(plan_field ladder close_reason)" "closed|null"

out=$(plan close unknown closed 2>&1); code=$?
check "close an unregistered slug -> fails" "$code" 1

exit "$fails"
