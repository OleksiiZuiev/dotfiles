#!/bin/bash
# Tests for the `task` CLI (task.sh, task.mjs) against a fixture vault.
# Run: bash claude/scripts/tasks/test_task.sh
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/task.sh"
fails=0

# Fixtures under $HOME so cygpath round-trips (/tmp maps elsewhere on Git Bash).
root="$HOME/.task-test.$$"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/templates" "$root/projects/ve/tasks" "$root/projects/bare/tasks"
printf '# {{title}}\n\n## Description\n' > "$root/templates/task.md"
printf -- '---\ncreated: 2026-01-01\nid-prefix: VE\n---\n\n# VE\n' > "$root/projects/ve/ve.md"
printf -- '---\ncreated: 2026-01-01\n---\n\n# Bare\n' > "$root/projects/bare/bare.md"
export CLAUDE_VAULT_DIR="$(cygpath -w "$root")"
export CLAUDE_SCRIPTS_DIR="$(realpath "$SCRIPT_DIR/..")"
tasks="$root/projects/ve/tasks"
today=$(date +%Y-%m-%d)

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

# --- help ---
out=$(task --help); code=$?
check "--help -> exit 0" "$code" 0
check "--help -> usage" "$(has "$out" "Usage: task new")" yes

# --- new ---
out=$(task new ve scaffold-app --title "Scaffold the app"); code=$?
check "new -> exit 0" "$code" 0
check "new -> prints the ID" "$(head -1 <<< "$out")" VE-1
check "new -> file named ID and slug" "$(ls "$tasks" | grep -v '^\.')" "VE-1 scaffold-app.md"
check "new -> frontmatter and body" "$(cat "$tasks/VE-1 scaffold-app.md")" "---
id: VE-1
aliases: [VE-1]
status: todo
created: $today
---

# Scaffold the app

## Description"

task new ve wire-db --blocked-by VE-1 --plan some-plan --status in-progress > /dev/null
check "new -> next ID" "$(ls "$tasks/.ids" | sort | tr '\n' ' ')" "VE-1 VE-2 "
check "new -> blocked-by, plan, status, slug as title" "$(cat "$tasks/VE-2 wire-db.md")" "---
id: VE-2
aliases: [VE-2]
status: in-progress
blocked-by: [\"[[VE-1]]\"]
plan: \"[[some-plan]]\"
created: $today
---

# wire-db

## Description"

rm "$tasks/VE-2 wire-db.md"
check "new -> deleted task's ID is not reused" "$(task new ve again | head -1)" VE-3

# --- new: refusals ---
out=$(task new bare x 2>&1); code=$?
check "no id-prefix -> exit 1" "$code" 1
check "no id-prefix -> says so" "$(has "$out" "id-prefix")" yes
check "no id-prefix -> nothing written" "$(ls -A "$root/projects/bare/tasks")" ""

before=$(ls -A "$tasks" "$tasks/.ids")
out=$(task new ve y --blocked-by VE-99 2>&1); code=$?
check "unknown blocked-by -> exit 1" "$code" 1
check "unknown blocked-by -> names it" "$(has "$out" "VE-99")" yes
check "unknown blocked-by -> nothing written" "$(ls -A "$tasks" "$tasks/.ids")" "$before"

out=$(task new ve z --status blocked 2>&1); code=$?
check "invalid status on new -> exit 1" "$code" 1

# --- claim: a writer that read before another's claim landed ---
# Separate processes do not overlap reliably enough to race, so the losing writer's stale read is
# passed in directly. VE-1..VE-3 are claimed above.
claim() { # $1 the number the writer read as next
  node --disable-warning=ExperimentalWarning --input-type=module -e '
    const [module, dir, from] = process.argv.slice(1);
    const { claimId } = await import(new URL(`file:///${module.replaceAll("\\", "/")}`));
    console.log(claimId(dir, "VE", Number(from)));
  ' "$(cygpath -w "$SCRIPT_DIR/task.mjs")" "$(cygpath -w "$tasks/.ids")" "$1"
}
check "claim with a stale read -> skips the claimed ID" "$(claim 3)" VE-4
check "claim with a stale read -> leaves the claimed marker" "$(ls "$tasks/.ids" | sort | tr '\n' ' ')" "VE-1 VE-2 VE-3 VE-4 "

# --- set ---
task set VE-1 status done; code=$?
check "set -> exit 0" "$code" 0
check "set -> only the status line changes" "$(cat "$tasks/VE-1 scaffold-app.md")" "---
id: VE-1
aliases: [VE-1]
status: done
created: $today
---

# Scaffold the app

## Description"

before=$(cat "$tasks/VE-1 scaffold-app.md")
out=$(task set VE-1 status blocked 2>&1); code=$?
check "set invalid status -> exit 1" "$code" 1
check "set invalid status -> file unchanged" "$(cat "$tasks/VE-1 scaffold-app.md")" "$before"
out=$(task set VE-1 owner me 2>&1); code=$?
check "set unknown field -> exit 1" "$code" 1
out=$(task set VE-99 status done 2>&1); code=$?
check "set unknown ID -> exit 1" "$code" 1
check "set unknown ID -> names it" "$(has "$out" "VE-99")" yes

# --- list ---
# Here VE-1 is done, VE-2's file is deleted, VE-3 is todo and VE-4 is a marker without a file.
task new ve after-done --title "After done" --blocked-by VE-1 > /dev/null   # VE-5
task new ve after-todo --title "After todo" --blocked-by VE-3 VE-1 > /dev/null   # VE-6
task new ve dropped --status cancelled > /dev/null   # VE-7
task new ve after-dropped --blocked-by VE-7 --status in-progress > /dev/null   # VE-8
tab=$'\t'
out=$(task list ve); code=$?
check "list -> exit 0" "$code" 0
check "list -> open tasks by ID, title from the heading, open blockers with status" "$out" "VE-3${tab}todo${tab}again${tab}
VE-5${tab}todo${tab}After done${tab}
VE-6${tab}todo${tab}After todo${tab}VE-3 (todo)
VE-8${tab}in-progress${tab}after-dropped${tab}VE-7 (cancelled)"

json=$(task list ve --json)
row() { # $1 ID  $2 JS expression over the row `r`, with no "/" in it: Git Bash rewrites those
  node -e 'const [json, id, expr] = process.argv.slice(1);
    const r = JSON.parse(json).find((t) => t.id === id);
    console.log(eval(expr));' "$json" "$1" "$2"
}
check "list --json -> same tasks" "$(node -e 'console.log(JSON.parse(process.argv[1]).map((t) => t.id).join(" "))' "$json")" "VE-3 VE-5 VE-6 VE-8"
check "list --json -> blockers with status" "$(row VE-6 'JSON.stringify(r.blockers)')" '[{"id":"VE-3","status":"todo"}]'
check "list --json -> path to the task file" "$(row VE-5 r.path)" "$(cygpath -w "$tasks/VE-5 after-done.md")"

out=$(task list nope 2>&1); code=$?
check "list unknown project -> exit 1" "$code" 1
check "list unknown project -> names it" "$(has "$out" "projects/nope")" yes

# --- a shell restored from a Claude Code snapshot ---
# The snapshot keeps the task function's text, but neither the underscore helpers nor the variables
# that sourcing task.sh set.
out=$(bash --norc --noprofile -c "$(declare -f task); task list ve" 2>&1); code=$?
check "restored shell -> list exit 0" "$code" 0
check "restored shell -> list prints the open tasks" "$(cut -f1 <<< "$out" | tr '\n' ' ')" "VE-3 VE-5 VE-6 VE-8 "

# --- new: arguments reach node as written ---
id=$(task new ve slash-title --title "/plan-next with dispatch" | head -1)
check "new -> a title starting with / is kept as written" "$(sed -n '/^# /p' "$tasks/$id slash-title.md")" "# /plan-next with dispatch"

# --- set blocked-by ---
a=$(task new ve dep-a | head -1)
b=$(task new ve dep-b | head -1)
c=$(task new ve dep-c | head -1)
file_of() { local f=("$tasks/$1 "*.md); printf "%s" "${f[0]}"; }
blocked_by() { grep "^blocked-by:" "$(file_of "$1")" || echo none; }

task set "$a" blocked-by "$b"; code=$?
check "set blocked-by -> exit 0" "$code" 0
check "set blocked-by -> writes the line as new does" "$(blocked_by "$a")" "blocked-by: [\"[[$b]]\"]"
check "set blocked-by -> inserted after status, other lines intact" "$(sed -n 1,6p "$(file_of "$a")")" "---
id: $a
aliases: [$a]
status: todo
blocked-by: [\"[[$b]]\"]
created: $today"

task set "$a" blocked-by "$c" VE-1
check "set blocked-by -> replaces the whole list" "$(blocked_by "$a")" "blocked-by: [\"[[$c]]\", \"[[VE-1]]\"]"

task set "$a" blocked-by
check "set blocked-by with no IDs -> clears the line" "$(blocked_by "$a")" none
check "set blocked-by with no IDs -> other lines intact" "$(sed -n 1,5p "$(file_of "$a")")" "---
id: $a
aliases: [$a]
status: todo
created: $today"

task set "$a" blocked-by "$b"
before=$(cat "$(file_of "$a")")
out=$(task set "$a" blocked-by VE-99 2>&1); code=$?
check "set blocked-by unknown ID -> exit 1" "$code" 1
check "set blocked-by unknown ID -> names it" "$(has "$out" VE-99)" yes
check "set blocked-by unknown ID -> file unchanged" "$(cat "$(file_of "$a")")" "$before"

out=$(task set "$a" blocked-by "$c" "$a" 2>&1); code=$?
check "set blocked-by itself -> exit 1" "$code" 1
check "set blocked-by itself -> file unchanged" "$(cat "$(file_of "$a")")" "$before"

before_b=$(cat "$(file_of "$b")")
out=$(task set "$b" blocked-by "$a" 2>&1); code=$?
check "set blocked-by direct cycle -> exit 1" "$code" 1
check "set blocked-by direct cycle -> names the cycle" "$(has "$out" cycle)" yes
check "set blocked-by direct cycle -> file unchanged" "$(cat "$(file_of "$b")")" "$before_b"

task set "$b" blocked-by "$c"
before_c=$(cat "$(file_of "$c")")
out=$(task set "$c" blocked-by "$a" 2>&1); code=$?
check "set blocked-by indirect cycle -> exit 1" "$code" 1
check "set blocked-by indirect cycle -> file unchanged" "$(cat "$(file_of "$c")")" "$before_c"

# --- set plan ---
check "--help -> documents set plan" "$(has "$(task --help)" "task set <ID> plan")" yes
p=$(task new ve planned --blocked-by "$a" --plan some-plan | head -1)
task set "$p" plan; code=$?
check "set plan with no value -> exit 0" "$code" 0
check "set plan with no value -> clears the line, other lines intact" "$(sed -n 1,7p "$(file_of "$p")")" "---
id: $p
aliases: [$p]
status: todo
blocked-by: [\"[[$a]]\"]
created: $today
---"

before=$(cat "$(file_of "$p")")
task set "$p" plan; code=$?
check "set plan on a task with no plan -> exit 0" "$code" 0
check "set plan on a task with no plan -> file unchanged" "$(cat "$(file_of "$p")")" "$before"

out=$(task set "$p" plan other-plan 2>&1); code=$?
check "set plan with a value -> exit 1" "$code" 1
check "set plan with a value -> file unchanged" "$(cat "$(file_of "$p")")" "$before"

echo
if [[ $fails -eq 0 ]]; then echo "All tests passed"; else echo "$fails test(s) failed"; exit 1; fi
