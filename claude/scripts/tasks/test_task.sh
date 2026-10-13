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

echo
if [[ $fails -eq 0 ]]; then echo "All tests passed"; else echo "$fails test(s) failed"; exit 1; fi
