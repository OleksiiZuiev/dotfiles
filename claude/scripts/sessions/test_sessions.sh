#!/bin/bash
# Tests for the `sessions` read commands (sessions.sh): builds a sessions index through the
# real writer, then reads it back through `sessions list`, `sessions show` and the view's key handler.
# Run: bash claude/scripts/sessions/test_sessions.sh
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
WRITER="$SCRIPT_DIR/sessions-db.mjs"
source "$SCRIPT_DIR/sessions.sh"
fails=0

# Fixtures under $HOME so cygpath round-trips (/tmp maps elsewhere on Git Bash).
root="$HOME/.sessions-test.$$"
mkdir -p "$root/contexts" "$root/alive" "$root/transcripts"
trap 'kill $linear_pid 2> /dev/null; rm -rf "$root"' EXIT
export CLAUDE_SESSIONS_DB="$(cygpath -w "$root/sessions.db")"
export CLAUDE_TICKET_CONTEXTS_DIR="$root/contexts"
# No key until the Linear section, so nothing before it reaches the real Linear.
export CLAUDE_LINEAR_KEY_FILE="$(cygpath -w "$root/no-key")"
alive=$(cygpath -w "$root/alive")
gone=$(cygpath -w "$root/int-1-a-long-worktree-name-that-is-gone")

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

# --- No database ---
out=$(sessions list 2>&1); code=$?
check "no database -> exit 1" "$code" 1
check "no database -> says so" "$(has "$out" "No sessions recorded yet")" yes

# --- Fixture ---
transcript() { cygpath -w "$root/transcripts/$1.jsonl"; }
add() { # $1 id  $2 branch  $3 origin  $4 cwd  $5 started  $6 last active  $7 ended ("" = open)
  local t; t=$(transcript "$1")
  printf '%s\n%s\n\n{"session_id":"%s","cwd":"%s","transcript_path":"%s","source":"startup"}' \
    "$2" "$3" "$1" "${4//\\/\\\\}" "${t//\\/\\\\}" | node --disable-warning=ExperimentalWarning "$(cygpath -w "$WRITER")" start
  node --disable-warning=ExperimentalWarning -e '
    const { DatabaseSync } = require("node:sqlite");
    const [db, id, started, last, ended] = process.argv.slice(1);
    new DatabaseSync(db).prepare(
      "UPDATE sessions SET started_at = ?, last_active_at = ?, ended_at = ? WHERE session_id = ?"
    ).run(started, last, ended || null, id);
  ' "$CLAUDE_SESSIONS_DB" "$1" "$5" "$6" "$7"
}
add aaaaaaaa-1 feat/int-1-first-thing git@github.com:org/alpha.git "$alive" \
  2026-09-30T10:00:00.000Z 2026-09-30T11:00:00.000Z 2026-09-30T11:00:00.000Z
add bbbbbbbb-1 feat/int-1-first-thing git@github.com:org/beta.git "$gone" \
  2026-09-30T12:00:00.000Z 2026-09-30T13:00:00.000Z ""
add cccccccc-1 fix/int-2-slug-title-here git@github.com:org/alpha.git "$alive" \
  2026-09-30T13:30:00.000Z 2026-09-30T14:00:00.000Z 2026-09-30T14:00:00.000Z
add dddddddd-1 main git@github.com:org/alpha.git "$alive" \
  2026-09-30T14:30:00.000Z 2026-09-30T15:00:00.000Z 2026-09-30T15:00:00.000Z
add eeeeeeee-1 feat/int-3-wsl-work git@github.com:org/gamma.git /home/someone/gamma \
  2026-09-30T08:00:00.000Z 2026-09-30T09:00:00.000Z 2026-09-30T09:00:00.000Z
printf '# INT-1: First thing title\n\nbody\n' > "$root/contexts/INT-1.md"

# Transcript lines in the shape Claude Code writes them; cccccccc-1 has no transcript.
cat > "$root/transcripts/aaaaaaaa-1.jsonl" <<'EOF'
{"type":"user","isMeta":true,"message":{"role":"user","content":"<local-command-caveat>ignored</local-command-caveat>"}}
{"type":"user","message":{"role":"user","content":"<command-message>ds:work-on</command-message>\n<command-name>/ds:work-on</command-name>\n<command-args>INT-1</command-args>"}}
{"type":"ai-title","aiTitle":"early-title","sessionId":"aaaaaaaa-1"}
{"type":"user","message":{"role":"user","content":"<command-name>/ds:review</command-name>"}}
{"type":"last-prompt","lastPrompt":"ship it","sessionId":"aaaaaaaa-1"}
{"type":"ai-title","aiTitle":"translate-picker-text","sessionId":"aaaaaaaa-1"}
{"type":"last-prompt","leafUuid":"l-1","sessionId":"aaaaaaaa-1"}
EOF
cat > "$root/transcripts/bbbbbbbb-1.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"<command-name>/ds:polish-pr</command-name>"}}
{"type":"ai-title","aiTitle":"generated","sessionId":"bbbbbbbb-1"}
{"type":"custom-title","customTitle":"polish-int-1","sessionId":"bbbbbbbb-1"}
EOF
cat > "$root/transcripts/dddddddd-1.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Explain the\nthing please"}]}}
EOF

# --- sessions list ---
out=$(sessions list); code=$?
check "list -> exit 0" "$code" 0
check "list -> tickets by latest session, no-ticket last" \
  "$(awk 'NR > 1 { printf "%s ", $1 }' <<< "$out")" "INT-2 INT-1 INT-3 — "
int1=$(grep '^INT-1 ' <<< "$out")
check "list -> title from the ticket context" "$(has "$int1" "First thing title")" yes
check "list -> repos of all its sessions" "$(has "$int1" "alpha, beta")" yes
check "list -> open when a session has no end" "$(has "$int1" " open")" yes
check "list -> session count" "$(has "$int1" "  2  ")" yes
int2=$(grep '^INT-2 ' <<< "$out")
check "list -> title from the branch slug without a ticket context" "$(has "$int2" "slug title here")" yes
check "list -> not open when every session ended" "$(has "$int2" " open")" "no: $int2"

json=$(sessions list --json)
check "list --json -> ticket rows" "$(node -e '
  const t = JSON.parse(process.argv[1]).find(r => r.ticket === "INT-1");
  console.log([t.title, t.repos.join(","), t.sessions, t.last_active_at, t.open].join("|"));
' "$json")" "First thing title|org/alpha,org/beta|2|2026-09-30T13:00:00.000Z|true"
check "list --json -> no-ticket group has a null ticket" \
  "$(node -e 'console.log(JSON.parse(process.argv[1]).at(-1).ticket)' "$json")" null

# --- sessions list <ticket> ---
out=$(sessions list INT-1)
check "list ticket -> its sessions, newest first" \
  "$(awk 'NR > 1 { printf "%s ", $1 }' <<< "$out")" "bbbbbbbb aaaaaaaa "
row_a=$(grep '^aaaaaaaa' <<< "$out") row_b=$(grep '^bbbbbbbb' <<< "$out")
check "list ticket -> last active, not started" "$(has "$(head -1 <<< "$out")" "LAST ACTIVE")$(has "$(head -1 <<< "$out")" "STARTED")" "yesno: $(head -1 <<< "$out")"
check "list ticket -> last active as an age" "$(has "$row_a" " ago ")" yes
check "list ticket -> kind from the first command" "$(has "$row_a" "/ds:work-on")" yes
check "list ticket -> title from the latest ai title" "$(has "$row_a" "translate-picker-text")" yes
check "list ticket -> a custom title wins over the ai title" "$(has "$row_b" "polish-int-1")" yes
check "list ticket -> directory by its name" "$(has "$row_a" "  alive")" yes
check "list ticket -> open flag on an open session" "$(has "$row_b" "open")" yes
check "list ticket -> no flag on an ended session" "$(has "$row_a" "open")" "no: $row_a"
check "list ticket -> missing directory marked" "$(has "$row_b" "(gone)")" yes
check "list ticket -> existing directory not marked" "$(has "$row_a" "(gone)")" "no: $row_a"
check "list ticket -> WSL directory unchecked from Windows" \
  "$(has "$(sessions list INT-3 | grep '^eeeeeeee')" "(?)")" yes
out=$(sessions list —)
check "list — -> sessions without a ticket" "$(awk 'NR > 1 { print $1 }' <<< "$out")" dddddddd
check "list — -> title from the first prompt without a title" "$(has "$out" "Explain the thing please")" yes
check "list ticket --json -> derived fields" "$(node -e '
  console.log(JSON.parse(process.argv[1]).map(r =>
    [r.session_id, r.directory_exists, r.kind, r.title, r.last_prompt].join(":")).join(" "));
' "$(sessions list INT-1 --json)")" \
  "bbbbbbbb-1:false:/ds:polish-pr:polish-int-1: aaaaaaaa-1:true:/ds:work-on:translate-picker-text:ship it"
check "list ticket --json -> no transcript, no title" "$(node -e '
  const r = JSON.parse(process.argv[1])[0]; console.log(`[${r.kind}][${r.title}]`);
' "$(sessions list INT-2 --json)")" "[][]"
check "list unknown ticket -> exit 1" "$(sessions list INT-404 > /dev/null 2>&1; echo $?)" 1

# --- Fitting the terminal width ---
widest() { awk '{ if (length($0) > max) max = length($0) } END { print max }'; }
out=$(COLUMNS=60 sessions list)
check "list -> no line wider than the terminal" "$(( $(widest <<< "$out") <= 60 ))" 1
check "list -> narrowed rows keep the trailing columns" "$(has "$(grep '^INT-1 ' <<< "$out")" " open")" yes
out=$(COLUMNS=60 sessions list INT-1)
check "list ticket -> no line wider than the terminal" "$(( $(widest <<< "$out") <= 60 ))" 1
check "list ticket -> narrowed rows keep the open flag" "$(has "$(grep '^bbbbbbbb' <<< "$out")" "open")" yes
check "list ticket -> a narrowed directory keeps its end" "$(has "$(grep '^bbbbbbbb' <<< "$out")" "…e (gone)")" yes
check "the view's width wins over the terminal's" "$(( $(COLUMNS=200 SESSIONS_WIDTH=50 sessions list | widest) <= 50 ))" 1

# --- sessions show ---
out=$(sessions show bbbb)
check "show -> row by id prefix" "$(has "$out" "bbbbbbbb-1")" yes
check "show -> transcript path" "$(has "$out" "bbbbbbbb-1.jsonl")" yes
check "show -> title" "$(has "$out" "polish-int-1")" yes
check "show unknown id -> exit 1" "$(sessions show zzzz > /dev/null 2>&1; echo $?)" 1

# --- sessions resume ---
# Stand-ins for the tab and for WSL: each records its arguments, one per line.
claude_tab() { printf '%s\n' "$@" > "$root/tab-args"; }
wsl.exe() { printf '%s\n' "$@" > "$root/wsl-args"; }
tab_args() { [[ -f "$root/tab-args" ]] && tr '\n' ' ' < "$root/tab-args"; rm -f "$root/tab-args"; }
sessions resume aaaa > /dev/null; code=$?
check "resume by id prefix -> exit 0" "$code" 0
check "resume by id prefix -> a tab in its directory resuming it" "$(tab_args)" "INT-1 $alive --resume aaaaaaaa-1 "
sessions resume int-2 > /dev/null
check "resume a ticket -> its latest session" "$(tab_args)" "INT-2 $alive --resume cccccccc-1 "
sessions resume dddd > /dev/null
check "resume a session with no ticket -> titled by its short id" "$(tab_args)" "dddddddd $alive --resume dddddddd-1 "
err=$(sessions resume INT-1 2>&1 > /dev/null); code=$?
check "resume a session whose directory is gone -> exit 1" "$code" 1
check "resume a session whose directory is gone -> says so" "$(has "$err" "no longer exists")" yes
check "resume a session whose directory is gone -> names the transcript" "$(has "$err" "bbbbbbbb-1.jsonl")" yes
check "resume a session whose directory is gone -> no tab" "$(tab_args)" ""
sessions resume eeee > /dev/null
check "resume a WSL session -> a WSL tab" "$(tab_args)" "--wsl INT-3 /home/someone/gamma --resume eeeeeeee-1 "
check "resume a WSL session -> its directory checked in WSL" "$(tr '\n' ' ' < "$root/wsl-args")" "-e test -d /home/someone/gamma "
check "resume unknown -> exit 1" "$(sessions resume zzzz > /dev/null 2>&1; echo $?)" 1
check "resume unknown -> no tab" "$(tab_args)" ""

# --- sessions new ---
sessions new int-2 > /dev/null; code=$?
check "new -> exit 0" "$code" 0
check "new -> a tab in the ticket's worktree running plain claude" "$(tab_args)" "INT-2 $alive "
err=$(sessions new INT-1 2>&1 > /dev/null); code=$?
check "new when the worktree is gone -> exit 1" "$code" 1
check "new when the worktree is gone -> says so" "$(has "$err" "no longer exists")" yes
check "new when the worktree is gone -> no tab" "$(tab_args)" ""
# A /ds:refine session: on main in the repo checkout, its ticket filled from the prompt.
add ffffffff-1 main git@github.com:org/alpha.git "$alive" \
  2026-09-30T16:00:00.000Z 2026-09-30T16:30:00.000Z 2026-09-30T16:30:00.000Z
printf '\n\n\n{"session_id":"ffffffff-1","prompt":"/ds:refine INT-4"}' \
  | node --disable-warning=ExperimentalWarning "$(cygpath -w "$WRITER")" fill
err=$(sessions new INT-4 2>&1 > /dev/null); code=$?
check "new for a ticket with no session on its branch -> exit 1" "$code" 1
check "new for a ticket with no session on its branch -> says so" "$(has "$err" "no worktree for INT-4")" yes
check "new for a ticket with no session on its branch -> no tab" "$(tab_args)" ""
out=$(FZF_PROMPT='tickets> ' bash "$SCRIPT_DIR/sessions.sh" _view new INT-4)
check "view ctrl-n on a ticket with no worktree -> the reason in the header" \
  "$(has "$out" "change-header:")$(has "$out" "no worktree for INT-4")" yesyes
node --disable-warning=ExperimentalWarning -e '
  const { DatabaseSync } = require("node:sqlite");
  new DatabaseSync(process.argv[1]).prepare("DELETE FROM sessions WHERE session_id = ?").run("ffffffff-1");
' "$CLAUDE_SESSIONS_DB"
check "view ctrl-n on no ticket -> nothing" "$(FZF_PROMPT='tickets> ' bash "$SCRIPT_DIR/sessions.sh" _view new —)" ""
rm -f "$root/wsl-args"
sessions new int-3 > /dev/null
check "new for a WSL worktree -> a WSL tab" "$(tab_args)" "--wsl INT-3 /home/someone/gamma "
check "new for a WSL worktree -> its directory checked in WSL" "$(tr '\n' ' ' < "$root/wsl-args")" "-e test -d /home/someone/gamma "
check "new unknown -> exit 1" "$(sessions new INT-404 > /dev/null 2>&1; echo $?)" 1
check "new unknown -> no tab" "$(tab_args)" ""
unset -f claude_tab wsl.exe

# --- The view's key handler: prints the fzf actions for a key in the current mode ---
view() { FZF_PROMPT="$1" bash "$SCRIPT_DIR/sessions.sh" _view "${@:2}"; }
out=$(view 'tickets> ' enter INT-1)
check "view enter on a ticket -> loads its sessions" "$(has "$out" "list 'INT-1')")" yes
check "view enter on a ticket -> sessions prompt" "$(has "$out" "change-prompt(INT-1 sessions> )")" yes
check "view enter on a ticket -> hides the session id" "$(has "$out" "change-with-nth(2..)")" yes
out=$(view 'INT-1 sessions> ' enter bbbbbbbb)
check "view enter on a session that cannot resume -> the reason in the header" \
  "$(has "$out" "change-header:")$(has "$out" "no longer exists")" yesyes
out=$(view 'INT-1 sessions> ' esc)
check "view esc in sessions -> back to tickets" "$(has "$out" "change-prompt(tickets> )")" yes
check "view esc in sessions -> shows every field" "$(has "$out" "change-with-nth(1..)")" yes
check "view esc in tickets -> quits" "$(view 'tickets> ' esc)" abort
check "view reload in sessions -> reloads that ticket's sessions" "$(has "$(view 'INT-1 sessions> ' reload)" "list 'INT-1')")" yes
check "view reload -> fits the list to fzf's width" "$(has "$(view 'tickets> ' reload)" 'SESSIONS_WIDTH=$((FZF_COLUMNS - 3))')" yes
check "view ctrl-o on a ticket -> opens it" "$(has "$(view 'tickets> ' open INT-1)" "/issue/INT-1")" yes
check "view ctrl-o in sessions -> opens the ticket" "$(has "$(view 'INT-1 sessions> ' open bbbbbbbb)" "/issue/INT-1")" yes
check "view ctrl-o on no ticket -> nothing" "$(view 'tickets> ' open —)" ""

# --- Linear titles and the cache ---
# A fake Linear that answers like the real one — an unknown identifier nulls the whole `data` and is
# named by its alias in `errors` — and logs every request body, one per line.
cat > "$root/fake-linear.mjs" <<'EOF'
import { createServer } from 'node:http';
import { appendFileSync, writeFileSync } from 'node:fs';
const [log, portFile] = process.argv.slice(2);
const issues = {
  'INT-1': { title: 'Linear title one', project: { name: 'Alpha project' } },
  'INT-2': { title: 'Linear two', project: null },
};
const server = createServer((req, res) => {
  let body = '';
  req.on('data', (chunk) => (body += chunk));
  req.on('end', () => {
    const { query } = JSON.parse(body);
    appendFileSync(log, `${req.headers.authorization} ${query.replace(/\s+/g, ' ')}\n`);
    const aliases = [...query.matchAll(/(\w+): issue\(id: "([^"]+)"\)/g)];
    const unknown = aliases.filter(([, , id]) => !issues[id]);
    const reply = unknown.length
      ? { data: null, errors: unknown.map(([, alias]) => ({ message: 'Entity not found: Issue', path: [alias] })) }
      : { data: Object.fromEntries(aliases.map(([, alias, id]) => [alias, issues[id]])) };
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(reply));
  });
});
server.listen(0, '127.0.0.1', () => writeFileSync(portFile, String(server.address().port)));
EOF
: > "$root/linear.log"
node "$(cygpath -w "$root/fake-linear.mjs")" "$(cygpath -w "$root/linear.log")" "$(cygpath -w "$root/linear.port")" &
linear_pid=$!
for _ in $(seq 50); do [[ -s "$root/linear.port" ]] && break; sleep 0.1; done
export CLAUDE_LINEAR_API="http://127.0.0.1:$(cat "$root/linear.port")"
requests() { wc -l < "$root/linear.log" | tr -d ' '; }
last_request() { tail -1 "$root/linear.log"; }
age_cache() { # $1 ticket: makes its cached row two days old
  node --disable-warning=ExperimentalWarning -e '
    const { DatabaseSync } = require("node:sqlite");
    new DatabaseSync(process.argv[1]).prepare("UPDATE linear_issues SET fetched_at = ? WHERE identifier = ?")
      .run(new Date(Date.now() - 2 * 86400000).toISOString(), process.argv[2]);
  ' "$CLAUDE_SESSIONS_DB" "$1"
}
clear_cache() {
  node --disable-warning=ExperimentalWarning -e '
    const { DatabaseSync } = require("node:sqlite");
    new DatabaseSync(process.argv[1]).exec("DELETE FROM linear_issues");
  ' "$CLAUDE_SESSIONS_DB"
}

sessions list > /dev/null
check "no key -> no request to Linear" "$(requests)" 0

printf 'test-key\n' > "$root/api-key"
export CLAUDE_LINEAR_KEY_FILE="$(cygpath -w "$root/api-key")"
out=$(sessions list)
check "list -> the Linear title wins over the ticket context" "$(has "$(grep '^INT-1 ' <<< "$out")" "Linear title one")" yes
check "list -> a ticket Linear does not know keeps the branch slug" "$(has "$(grep '^INT-3 ' <<< "$out")" "wsl work")" yes
check "list -> sends the key as the Authorization header" "$(has "$(last_request)" "test-key ")" yes
check "list -> asks for title and project" "$(has "$(last_request)" "title project { name }")" yes
check "list -> resends the known tickets without the unknown one" "$(has "$(last_request)" '"INT-1"')$(has "$(last_request)" "INT-3")" "yesno: $(last_request)"
check "list --json -> the ticket's project" "$(node -e '
  console.log(JSON.parse(process.argv[1]).find(r => r.ticket === "INT-1").project);
' "$(sessions list --json)")" "Alpha project"

before=$(requests)
sessions list > /dev/null
check "list within a day -> no request" "$(requests)" "$before"
age_cache INT-1
sessions list > /dev/null
check "list -> refetches a ticket cached over a day ago" "$(( $(requests) - before ))" 1
check "list -> refetches only the stale ticket" "$(has "$(last_request)" '"INT-1"')$(has "$(last_request)" "INT-2")" "yesno: $(last_request)"
before=$(requests)
sessions list --refresh > /dev/null
check "list --refresh -> refetches fresh tickets" "$(has "$(last_request)" '"INT-2"')" yes
check "list --refresh -> asks again for the unknown ticket" "$(has "$(sed -n "$((before + 1))p" "$root/linear.log")" '"INT-3"')" yes

out=$(sessions show INT-1)
check "show ticket -> its Linear title" "$(has "$out" "Linear title one")" yes
check "show ticket -> its project" "$(has "$out" "Alpha project")" yes
check "show ticket -> its session count" "$(has "$(grep '^sessions ' <<< "$out")" "2")" yes
out=$(view 'tickets> ' preview INT-1)
check "view preview on a ticket -> its project" "$(has "$out" "Alpha project")" yes
check "view preview on a ticket -> its sessions" "$(has "$out" "aaaaaaaa")" yes
check "view ctrl-r on tickets -> reloads with a refetch" "$(has "$(view 'tickets> ' refresh)" "list --refresh")" yes
out=$(view 'INT-1 sessions> ' refresh)
check "view ctrl-r in sessions -> refetches" "$(has "$out" "list --refresh")" yes
check "view ctrl-r in sessions -> reloads that ticket's sessions" "$(has "$out" "list 'INT-1')")" yes

export CLAUDE_LINEAR_API="http://127.0.0.1:1"
err=$(sessions list 2>&1 > /dev/null); code=$?
out=$(sessions list 2> /dev/null)
check "Linear unreachable -> exit 0" "$code" 0
check "Linear unreachable -> cached titles still shown" "$(has "$(grep '^INT-1 ' <<< "$out")" "Linear title one")" yes
check "Linear unreachable -> silent without --refresh" "$err" ""
check "Linear unreachable -> --refresh says so" "$(has "$(sessions list --refresh 2>&1 > /dev/null)" "could not reach Linear")" yes
clear_cache
check "Linear unreachable, nothing cached -> the ticket context title" \
  "$(has "$(sessions list | grep '^INT-1 ')" "First thing title")" yes

# --- help ---
out=$(CLAUDE_SESSIONS_DB='C:\nonexistent\x.db' sessions --help); code=$?
check "help -> exit 0" "$code" 0
check "help -> usage" "$(has "$out" "Usage: sessions")" yes

echo
if [[ $fails == 0 ]]; then echo "All passed."; else echo "$fails failed."; exit 1; fi
