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
export CLAUDE_SCRIPTS_DIR="$(realpath "$SCRIPT_DIR/..")"
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

# --- a shell restored from a Claude Code snapshot ---
# The snapshot keeps the plan function's text, but neither the underscore helpers nor the variables
# that sourcing plan.sh set.
out=$(bash --norc --noprofile -c "$(declare -f plan); plan list --json" 2>&1); code=$?
check "restored shell -> list exit 0" "$code" 0
check "restored shell -> list prints the plans" "$(field "$out" 's.map((p) => p.slug).join(" ")')" "ladder titled"

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

task set VE-2 status in-review
task new ve after-review --blocked-by VE-2 --plan 2026-01-01-ladder-plan > /dev/null   # VE-8
write_note VE-1 VE-2 VE-8
out=$(plan status ladder --json)
check "in-review -> counted apart from done and remaining" "$(field "$out" '[s.done, s.inReview, s.remaining].join("/")')" "1/1/1"
check "in-review -> a task it blocks is not on the frontier" "$(field "$out" 's.frontier.length')" 0
check "in-review -> text shows the count" "$(has "$(plan status ladder)" "in review 1")" yes
out=$(plan close ladder closed 2>&1); code=$?
check "close closed with an in-review member -> fails" "$code" 1
check "close closed with an in-review member -> names it" "$(has "$out" "VE-2 (in-review)")" yes

task set VE-2 status cancelled
task set VE-8 status cancelled
out=$(plan close ladder closed); code=$?
check "close closed with only done and cancelled members -> exit 0" "$code" 0
check "close closed -> status closed, no reason" \
  "$(plan_field ladder status)|$(plan_field ladder close_reason)" "closed|null"

out=$(plan close unknown closed 2>&1); code=$?
check "close an unregistered slug -> fails" "$code" 1

# --- early start ---
early_note="projects/ve/work-notes/2026-01-01-early-plan.md"
task new ve contract --workspace svc --plan 2026-01-01-early-plan --status in-progress > /dev/null   # VE-9
task new ve consumer --workspace app --blocked-by VE-9 --plan 2026-01-01-early-plan > /dev/null     # VE-10
task new ve same-repo --workspace svc --blocked-by VE-9 --plan 2026-01-01-early-plan > /dev/null    # VE-11
task new ve waiting --workspace svc --plan 2026-01-01-early-plan > /dev/null                        # VE-12
task new ve after-waiting --workspace app --blocked-by VE-9 VE-12 --plan 2026-01-01-early-plan > /dev/null   # VE-13
printf -- '---\ntype: plan\n---\n\n# Early plan\n\n## Tasks\n\n- [[VE-9]]\n- [[VE-10]]\n- [[VE-11]]\n- [[VE-12]]\n- [[VE-13]]\n' > "$root/$early_note"
plan register early "$early_note" > /dev/null
out=$(plan status early --json)
check "early start -> the todo task whose only blocker is in progress in another workspace" "$(field "$out" 's.earlyStart.join(",")')" VE-10
check "early start -> members carry their workspace" "$(field "$out" 's.members.map((m) => m.workspace).join(",")')" "svc,app,svc,svc,app"
check "early start -> the frontier still waits for done blockers" "$(field "$out" 's.frontier.join(",")')" VE-12
check "early start -> text names it" "$(has "$(plan status early)" "early start: VE-10")" yes
task set VE-9 status in-review
check "early start -> a blocker in review counts as started" "$(field "$(plan status early --json)" 's.earlyStart.join(",")')" VE-10

# --- Linear document plans ---
# A fake Linear that answers like the real one: a document by its slugId, issues by aliased
# identifier (an unknown identifier nulls the whole `data` and is named by its alias in `errors`),
# and issues whose description contains a text. It reads $root/linear.json on every request, so a
# test changes Linear by rewriting that file.
cat > "$root/fake-linear.mjs" <<'EOF'
import { createServer } from 'node:http';
import { readFileSync, writeFileSync } from 'node:fs';
const [fixture, portFile] = process.argv.slice(2);
const server = createServer((req, res) => {
  let body = '';
  req.on('data', (chunk) => (body += chunk));
  req.on('end', () => {
    const { query, variables = {} } = JSON.parse(body);
    const { documents, issues } = JSON.parse(readFileSync(fixture, 'utf8'));
    const toIssue = (id) => ({
      identifier: id,
      title: issues[id].title,
      description: issues[id].description,
      state: issues[id].state,
      inverseRelations: { nodes: (issues[id].blockedBy ?? []).map((blocker) =>
        ({ type: blocker.type ?? 'blocks', issue: { identifier: blocker.id, state: issues[blocker.id].state } })) },
    });
    let reply;
    if (/document\(id:/.test(query)) {
      const doc = documents[variables.id];
      reply = doc ? { data: { document: doc } } : { data: null, errors: [{ message: 'Entity not found: Document' }] };
    } else if (/issues\(/.test(query)) {
      const ids = Object.keys(issues).filter((id) => issues[id].description.includes(variables.text));
      reply = { data: { issues: { nodes: ids.map(toIssue) } } };
    } else {
      const aliases = [...query.matchAll(/(\w+): issue\(id: "([^"]+)"\)/g)];
      const unknown = aliases.filter(([, , id]) => !issues[id]);
      reply = unknown.length
        ? { data: null, errors: unknown.map(([, alias]) => ({ message: 'Entity not found: Issue', path: [alias] })) }
        : { data: Object.fromEntries(aliases.map(([, alias, id]) => [alias, toIssue(id)])) };
    }
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(reply));
  });
});
server.listen(0, '127.0.0.1', () => writeFileSync(portFile, String(server.address().port)));
EOF
doc_url="https://linear.app/acme/document/ladder-doc-abc123def456"
todo='{"type": "unstarted", "name": "Todo"}'
write_linear() { # $1 the ## Tasks lines  $2 the issues as a JSON object
  local content="# Ladder doc\n\nSee [INT-9](https://linear.app/acme/issue/INT-9/x) outside the list.\n\n## Tasks\n\n$1\n## Open questions\n\n- none\n"
  printf '{"documents": {"abc123def456": {"title": "Ladder doc", "url": "%s", "content": "%s"}}, "issues": %s}\n' \
    "$doc_url" "$content" "$2" > "$root/linear.json"
}
ticket() { # $1 title  $2 state JSON  $3 description  [$4 blockedBy JSON]
  printf '{"title": "%s", "state": %s, "description": "%s", "blockedBy": %s}' "$1" "$2" "$3" "${4:-[]}"
}
plan_line="Workspace: dotfiles\nPlan:https://linear.app/acme/document/old-title-abc123def456"
two_tickets() { # $1 INT-1 state JSON  [$2 INT-2 state JSON]
  printf '{"INT-1": %s, "INT-2": %s, "INT-9": %s}' \
    "$(ticket "First ticket" "$1" "Do it.\n\n$plan_line")" \
    "$(ticket "Second ticket" "${2:-$todo}" "$plan_line" '[{"id": "INT-1"}, {"id": "INT-9", "type": "related"}]')" \
    "$(ticket "Elsewhere" "$todo" "Unrelated.")"
}
tasks_lines='- [INT-1](https://linear.app/acme/issue/INT-1/first-ticket)\n- [INT-2](https://linear.app/acme/issue/INT-2/second-ticket)\n'
write_linear "$tasks_lines" "$(two_tickets "$todo")"

node "$(cygpath -w "$root/fake-linear.mjs")" "$(cygpath -w "$root/linear.json")" "$(cygpath -w "$root/linear.port")" &
linear_pid=$!
trap 'kill "$linear_pid" 2> /dev/null; rm -rf "$root"' EXIT
for _ in $(seq 50); do [[ -s "$root/linear.port" ]] && break; sleep 0.1; done
export CLAUDE_LINEAR_API="http://127.0.0.1:$(cat "$root/linear.port")"
printf 'test-key\n' > "$root/api-key"
export CLAUDE_LINEAR_KEY_FILE="$(cygpath -w "$root/api-key")"

out=$(plan register doc "$doc_url" 2>&1); code=$?
check "register a document URL -> exit 0" "$code" 0
check "register a document URL -> linear-doc home, the URL as locator, the document's title" \
  "$(field "$(plan list --json)" 's.filter((p) => p.slug === "doc").map((p) => [p.home, p.locator, p.title, p.status].join("|")).join(",")')" \
  "linear-doc|$doc_url|Ladder doc|active"
check "register a document URL -> list shows it" "$(has "$(plan list)" "linear-doc")" yes
out=$(plan register gone "https://linear.app/acme/document/gone-000000000000" 2>&1); code=$?
check "register an unknown document -> fails" "$code" 1
check "register an unknown document -> not in the list" "$(field "$(plan list --json)" 's.some((p) => p.slug === "gone")')" false

out=$(plan status doc --json); code=$?
check "linear status -> exit 0" "$code" 0
check "linear status -> members in document order with their titles, the mention outside ## Tasks left out" \
  "$(field "$out" 's.members.map((m) => [m.id, m.status, m.title].join(":")).join(",")')" "INT-1:todo:First ticket,INT-2:todo:Second ticket"
check "linear status -> blockers from the blocks relations only" \
  "$(field "$out" 's.members.find((m) => m.id === "INT-2").blockers.map((b) => b.id + ":" + b.status).join(",")')" "INT-1:todo"
check "linear status -> frontier is the todo ticket without an open blocker" "$(field "$out" 's.frontier.join(",")')" INT-1
check "linear status -> no drift when a Plan: line names the document under an old title" "$(field "$out" 's.drift.join(" ; ")')" ""
check "linear status -> counts" "$(field "$out" '[s.done, s.inReview, s.remaining].join("/")')" "0/0/2"

state_of() { # $1 INT-1 state JSON: the status plan status maps it to
  write_linear "$tasks_lines" "$(two_tickets "$1")"
  field "$(plan status doc --json)" 's.members[0].status'
}
check "state started -> in-progress" "$(state_of '{"type": "started", "name": "In Progress"}')" in-progress
check "state started named In Review -> in-review" "$(state_of '{"type": "started", "name": "In review"}')" in-review
check "state triage -> todo" "$(state_of '{"type": "triage", "name": "Triage"}')" todo
check "state backlog -> todo" "$(state_of '{"type": "backlog", "name": "Backlog"}')" todo
check "state completed -> done" "$(state_of '{"type": "completed", "name": "Done"}')" done
check "state canceled -> cancelled" "$(state_of '{"type": "canceled", "name": "Canceled"}')" cancelled
check "state duplicate -> cancelled" "$(state_of '{"type": "duplicate", "name": "Duplicate"}')" cancelled

write_linear "$tasks_lines" "$(two_tickets '{"type": "started", "name": "In Review"}')"
out=$(plan status doc --json)
check "linear in-review blocker -> its dependent is not on the frontier" "$(field "$out" 's.frontier.length')" 0
check "linear in-review blocker in the same workspace -> no early start" "$(field "$out" 's.earlyStart.length')" 0
write_linear "$tasks_lines" "$(printf '{"INT-1": %s, "INT-2": %s}' \
  "$(ticket "First ticket" '{"type": "started", "name": "In Progress"}' "Workspace: svc\nPlan: $doc_url")" \
  "$(ticket "Second ticket" "$todo" "$plan_line" '[{"id": "INT-1"}]')")"
out=$(plan status doc --json)
check "linear blocker in progress in another workspace -> early start" "$(field "$out" 's.earlyStart.join(",")')" INT-2
check "linear members -> workspace from the Workspace: line" "$(field "$out" 's.members.map((m) => m.workspace).join(",")')" "svc,dotfiles"
write_linear "$tasks_lines" "$(two_tickets '{"type": "completed", "name": "Done"}')"
out=$(plan status doc --json)
check "linear done blocker -> its dependent reaches the frontier" "$(field "$out" 's.frontier.join(",")')" INT-2
write_linear "$tasks_lines" "$(two_tickets '{"type": "canceled", "name": "Canceled"}')"
check "linear cancelled blocker -> its dependent stays off the frontier" "$(field "$(plan status doc --json)" 's.frontier.length')" 0

out=$(plan close doc closed 2>&1); code=$?
check "linear close closed with an open ticket -> fails" "$code" 1
check "linear close closed with an open ticket -> names it" "$(has "$out" "INT-2 (todo)")" yes

write_linear "$tasks_lines- [INT-4](https://linear.app/acme/issue/INT-4/x)\n- [INT-5](https://linear.app/acme/issue/INT-5/x)\n- INT-99\n" \
  "$(two_tickets "$todo" | sed 's/}$//'), $(printf '"INT-3": %s, "INT-4": %s, "INT-5": %s}' \
    "$(ticket "Unlisted" "$todo" "Plan: $doc_url")" \
    "$(ticket "No plan line" "$todo" "Mentions $doc_url in passing.")" \
    "$(ticket "Other plan" "$todo" "Plan: https://linear.app/acme/document/other-fff000fff000")")"
out=$(plan status doc --json)
drift=$(field "$out" 's.drift.join(" ; ")')
check "linear drift -> a ticket with the Plan: line that is not listed" "$(has "$drift" "INT-3")" yes
check "linear drift -> a listed ticket without the Plan: line" "$(has "$drift" "INT-4")" yes
check "linear drift -> a listed ticket whose Plan: line names another document" "$(has "$drift" "INT-5")" yes
check "linear drift -> a listed ID Linear does not know" "$(has "$drift" "INT-99")" yes
check "linear drift -> an unknown ID is a missing member" \
  "$(field "$out" 's.members.find((m) => m.id === "INT-99").status')" missing
check "linear drift -> the known tickets still read when one ID is unknown" \
  "$(field "$out" 's.members.find((m) => m.id === "INT-1").title')" "First ticket"
check "linear drift -> four lines, nothing about the tickets that agree" "$(field "$out" 's.drift.length')" 4

check "vault status -> unchanged beside a Linear plan" "$(field "$(plan status ladder --json)" 's.members.map((m) => m.id).join(",")')" "VE-1,VE-2,VE-8"

rm "$root/api-key"
out=$(plan status doc --json 2>&1); code=$?
check "linear status without an API key -> fails" "$code" 1
check "linear status without an API key -> says so" "$(has "$out" "API key")" yes

exit "$fails"
