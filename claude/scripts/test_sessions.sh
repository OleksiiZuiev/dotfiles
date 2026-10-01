#!/bin/bash
# Tests for the `sessions` read commands (bash.d/sessions.sh): builds a sessions index through the
# real writer, then reads it back through `sessions list` and `sessions show`.
# Run: bash claude/scripts/test_sessions.sh
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
WRITER="$SCRIPT_DIR/sessions-db.mjs"
source "$SCRIPT_DIR/../../bash.d/sessions.sh"
fails=0

# Fixtures under $HOME so cygpath round-trips (/tmp maps elsewhere on Git Bash).
root="$HOME/.sessions-test.$$"
mkdir -p "$root/contexts" "$root/alive"
trap 'rm -rf "$root"' EXIT
export CLAUDE_SESSIONS_DB="$(cygpath -w "$root/sessions.db")"
export CLAUDE_TICKET_CONTEXTS_DIR="$root/contexts"
alive=$(cygpath -w "$root/alive")
gone=$(cygpath -w "$root/gone")

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
add() { # $1 id  $2 branch  $3 origin  $4 cwd  $5 started  $6 last active  $7 ended ("" = open)
  printf '%s\n%s\n\n{"session_id":"%s","cwd":"%s","transcript_path":"C:/t/%s.jsonl","source":"startup"}' \
    "$2" "$3" "$1" "${4//\\/\\\\}" "$1" | node --disable-warning=ExperimentalWarning "$(cygpath -w "$WRITER")" start
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
check "list ticket -> open session" "$(has "$(grep '^bbbbbbbb' <<< "$out")" "open")" yes
check "list ticket -> missing directory marked" "$(has "$(grep '^bbbbbbbb' <<< "$out")" "(gone)")" yes
check "list ticket -> existing directory not marked" \
  "$(has "$(grep '^aaaaaaaa' <<< "$out")" "(gone)")" "no: $(grep '^aaaaaaaa' <<< "$out")"
check "list ticket -> WSL directory unchecked from Windows" \
  "$(has "$(sessions list INT-3 | grep '^eeeeeeee')" "(?)")" yes
check "list — -> sessions without a ticket" "$(sessions list — | awk 'NR > 1 { print $1 }')" dddddddd
check "list ticket --json -> directory_exists" "$(node -e '
  console.log(JSON.parse(process.argv[1]).map(r => r.session_id + ":" + r.directory_exists).join(" "));
' "$(sessions list INT-1 --json)")" "bbbbbbbb-1:false aaaaaaaa-1:true"
check "list unknown ticket -> exit 1" "$(sessions list INT-404 > /dev/null 2>&1; echo $?)" 1

# --- Fitting the terminal width ---
widest() { awk '{ if (length($0) > max) max = length($0) } END { print max }'; }
out=$(COLUMNS=60 sessions list)
check "list -> no line wider than the terminal" "$(( $(widest <<< "$out") <= 60 ))" 1
check "list -> narrowed rows keep the trailing columns" "$(has "$(grep '^INT-1 ' <<< "$out")" " open")" yes
out=$(COLUMNS=70 sessions list INT-1)
check "list ticket -> no line wider than the terminal" "$(( $(widest <<< "$out") <= 70 ))" 1
check "list ticket -> narrowed rows keep the end column" "$(has "$(grep '^bbbbbbbb' <<< "$out")" "open")" yes
check "list ticket -> a narrowed directory keeps its end" "$(has "$(grep '^bbbbbbbb' <<< "$out")" "… (gone)")" yes
check "preview width wins over the terminal's" "$(( $(COLUMNS=200 FZF_PREVIEW_COLUMNS=50 sessions list | widest) <= 50 ))" 1

# --- sessions show ---
out=$(sessions show bbbb)
check "show -> row by id prefix" "$(has "$out" "bbbbbbbb-1")" yes
check "show -> transcript path" "$(has "$out" "C:/t/bbbbbbbb-1.jsonl")" yes
check "show unknown id -> exit 1" "$(sessions show zzzz > /dev/null 2>&1; echo $?)" 1

# --- help ---
out=$(CLAUDE_SESSIONS_DB='C:\nonexistent\x.db' sessions --help); code=$?
check "help -> exit 0" "$code" 0
check "help -> usage" "$(has "$out" "Usage: sessions")" yes

echo
if [[ $fails == 0 ]]; then echo "All passed."; else echo "$fails failed."; exit 1; fi
