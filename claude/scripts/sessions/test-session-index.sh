#!/bin/bash
# Tests for session-index.sh: pipes crafted SessionStart / SessionEnd payloads through the real hook
# into a throwaway database and reads the rows back. Run: bash claude/scripts/sessions/test-session-index.sh
HOOK="$(dirname "$0")/session-index.sh"
fails=0

# Fixtures under $HOME so cygpath round-trips (/tmp maps elsewhere on Git Bash).
root="$HOME/.session-index-test.$$"
mkdir -p "$root"
trap 'rm -rf "$root"' EXIT
export CLAUDE_SESSIONS_DB="$(cygpath -w "$root/sessions.db")"

start_payload() { # $1 session id  $2 source  $3 cwd
  printf '{"session_id":"%s","transcript_path":"C:/t/%s.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "$1" "$1" "$3" "$2"
}
end_payload() { # $1 session id  $2 reason
  printf '{"session_id":"%s","transcript_path":"C:/t/%s.jsonl","hook_event_name":"SessionEnd","reason":"%s"}' "$1" "$1" "$2"
}
run_hook() { # $1 dir  $2 event  $3 payload; stdout = hook stdout+stderr, $? = hook exit code
  (cd "$1" && printf '%s' "$3" | bash "$HOOK" "$2" 2>&1)
}
col() { # $1 session id  $2 column; prints the value, NULL, or MISSING when there is no row
  node -e '
    const { DatabaseSync } = require("node:sqlite");
    const [db, id, column] = process.argv.slice(1);
    let row;
    try {
      row = new DatabaseSync(db).prepare("SELECT * FROM sessions WHERE session_id = ?").get(id);
    } catch (e) {
      if (!/no such table/.test(e.message)) throw e;
    }
    console.log(row === undefined ? "MISSING" : row[column] ?? "NULL");
  ' "$CLAUDE_SESSIONS_DB" "$1" "$2" 2>/dev/null
}
check() { # $1 name  $2 actual  $3 expected
  if [[ "$2" == "$3" ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n      got [%s], want [%s]\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}
check_set() { # $1 name  $2 actual — passes when the value is present
  if [[ "$2" != "NULL" && "$2" != "MISSING" && -n "$2" ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n      got [%s], want a value\n' "$1" "$2"
    fails=$((fails + 1))
  fi
}

ticket_repo="$root/ticket-repo"
git init -q -b main "$ticket_repo"
git -C "$ticket_repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$ticket_repo" checkout -q -b feature/int-812-add-thing
git -C "$ticket_repo" remote add origin git@github.com:some-org/some-repo.git

local_repo="$root/local-repo"
git init -q -b main "$local_repo"
git -C "$local_repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$local_repo" worktree add -q -b chore/tidy "$root/local-repo-worktrees/tidy"

plain="$root/plain"
mkdir -p "$plain"

# --- Fail open ---
out=$(CLAUDE_SESSIONS_NODE=/nonexistent/node run_hook "$ticket_repo" start "$(start_payload s-broken startup C:/x)"); code=$?
check "broken node path -> exit 0" "$code" 0
check "broken node path -> logs to stderr" "$([[ "$out" == *"session-index: start write failed"* ]] && echo yes)" yes
check "broken node path -> no row" "$(col s-broken session_id)" MISSING

# --- SessionStart ---
out=$(run_hook "$ticket_repo" start "$(start_payload s-ticket startup C:/work/ticket-repo)"); code=$?
check "startup -> exit 0" "$code" 0
check "startup -> no output" "$out" ""
check "startup -> ticket from branch" "$(col s-ticket ticket)" INT-812
check "startup -> branch" "$(col s-ticket branch)" feature/int-812-add-thing
check "startup -> repo from origin" "$(col s-ticket repo)" some-org/some-repo
check "startup -> cwd from payload" "$(col s-ticket cwd)" C:/work/ticket-repo
check "startup -> transcript path" "$(col s-ticket transcript_path)" C:/t/s-ticket.jsonl
check_set "startup -> started_at" "$(col s-ticket started_at)"
check "startup -> open" "$(col s-ticket ended_at)" NULL

run_hook "$root/local-repo-worktrees/tidy" start "$(start_payload s-worktree startup C:/w)" > /dev/null
check "no origin, in a worktree -> repo is the main checkout's name" "$(col s-worktree repo)" local-repo
check "branch without a ticket -> no ticket" "$(col s-worktree ticket)" NULL

run_hook "$plain" start "$(start_payload s-plain startup C:/p)" > /dev/null
check "outside git -> no repo" "$(col s-plain repo)" NULL
check "outside git -> no branch" "$(col s-plain branch)" NULL
check "outside git -> no ticket" "$(col s-plain ticket)" NULL

# --- SessionEnd ---
run_hook "$ticket_repo" end "$(end_payload s-ticket prompt_input_exit)" > /dev/null
check "end -> end reason" "$(col s-ticket end_reason)" prompt_input_exit
check_set "end -> ended_at" "$(col s-ticket ended_at)"

run_hook "$ticket_repo" end "$(end_payload s-never-started other)" > /dev/null
check "end of an unknown session -> no row" "$(col s-never-started session_id)" MISSING

# --- Session boundaries ---
started=$(col s-ticket started_at)
run_hook "$plain" start "$(start_payload s-ticket startup C:/elsewhere)" > /dev/null
check "second startup for an existing id -> row kept" "$(col s-ticket cwd)" C:/work/ticket-repo

run_hook "$ticket_repo" start "$(start_payload s-ticket resume C:/work/ticket-repo)" > /dev/null
check "resume after end -> reopened" "$(col s-ticket ended_at)" NULL
check "resume after end -> end reason cleared" "$(col s-ticket end_reason)" NULL
check "resume -> started_at kept" "$(col s-ticket started_at)" "$started"

run_hook "$ticket_repo" start "$(start_payload s-resumed-first resume C:/r)" > /dev/null
check "resume of an unknown id -> row inserted" "$(col s-resumed-first ticket)" INT-812

run_hook "$ticket_repo" end "$(end_payload s-ticket other)" > /dev/null
run_hook "$ticket_repo" start "$(start_payload s-ticket compact C:/work/ticket-repo)" > /dev/null
check "compact -> row unchanged" "$(col s-ticket end_reason)" other

run_hook "$ticket_repo" start "$(start_payload s-cleared clear C:/work/ticket-repo)" > /dev/null
check "clear -> new id gets a row" "$(col s-cleared ticket)" INT-812

echo
if [[ $fails == 0 ]]; then echo "All passed."; else echo "$fails failed."; exit 1; fi
