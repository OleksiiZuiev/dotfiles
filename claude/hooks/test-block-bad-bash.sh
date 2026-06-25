#!/bin/bash
# Regression tests for block-bad-bash.sh. Pipes crafted PreToolUse payloads through the real
# hook and asserts exit code + stdout. Run: bash claude/hooks/test-block-bad-bash.sh
HOOK="$(dirname "$0")/block-bad-bash.sh"
fails=0

payload() { # stdout = compact PreToolUse JSON payload carrying $1 as the bash command
  CMD="$1" python -c 'import os,sys,json; sys.stdout.write(json.dumps({"session_id":"x","cwd":"C:\\work\\repo","permission_mode":"auto","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":os.environ["CMD"],"description":"d"},"tool_use_id":"t"},separators=(",",":")))'
}

check() { # $1 name  $2 command  $3 want_exit  $4 want_stdout_substr (empty => expect empty stdout)
  local out code ok=1
  # capture stdout+stderr together: allow JSON lands on stdout, BLOCKED messages on stderr
  out=$(payload "$2" | bash "$HOOK" 2>&1); code=$?
  [[ "$code" == "$3" ]] || ok=0
  if [[ -n "$4" ]]; then
    [[ "$out" == *"$4"* ]] || ok=0
  else
    [[ -z "$out" ]] || ok=0
  fi
  if [[ $ok == 1 ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n      exit=%s (want %s)  stdout=[%s]\n' "$1" "$code" "$3" "$out"
    fails=$((fails + 1))
  fi
}

# --- Auto-approve branch ---
check "rm -rf worktree path -> allow" \
  'rm -rf "C:/work/github/org/repo-worktrees/int-123-foo-a1b2c3"' 0 '"permissionDecision":"allow"'
check "rm -fr worktree path -> allow" \
  'rm -fr "C:/work/github/org/repo-worktrees/x-deadbeef"' 0 '"permissionDecision":"allow"'
check "rm -rf non-worktree path -> no allow" \
  'rm -rf "C:/work/github/org/repo/node_modules"' 0 ''
check "rm -rf root -> no allow (defers to normal prompt)" \
  'rm -rf /' 0 ''
check "git worktree remove --force -> no allow, no block" \
  'git -c core.longpaths=true worktree remove --force "C:/work/github/org/repo-worktrees/int-123-foo-a1b2c3"' 0 ''
check "commit msg mentioning rm + worktrees -> no allow" \
  'git commit -m "rm -rf old-worktrees/ cleanup notes"' 0 ''

# --- Block branch (repaired) ---
check "git push --force -> block" 'git push --force origin main' 2 'BLOCKED'
check "git push -f -> block" 'git push -f origin main' 2 'BLOCKED'
check "aws delete -> block" 'aws s3api delete-bucket --bucket x' 2 'BLOCKED'
check "az delete -> block" 'az group delete --name x' 2 'BLOCKED'
check "kubectl delete -> block" 'kubectl delete pod x' 2 'BLOCKED'
check "terraform destroy -> block" 'terraform destroy -auto-approve' 2 'BLOCKED'
check "GIT_DIR env -> block" 'GIT_DIR=/x git status' 2 'BLOCKED'
check "commit msg mentioning --force -> no block" 'git commit -m "note about --force push danger"' 0 ''
check "single-line commit msg mentioning kubectl/aws delete -> no block" \
  'git commit -m "fix the kubectl delete bug and the aws delete issue"' 0 ''
# multi-line heredoc commit message whose body enumerates dangerous commands (the real
# false-positive that bit us): only the first line is scanned, so the body is ignored.
HEREDOC_MSG='git -C /x commit -m "$(cat <<EOF
fix: block checks now catch aws delete, az delete, kubectl delete, terraform destroy, git push --force, GIT_DIR=
EOF
)"'
check "heredoc commit msg enumerating dangerous cmds -> no block" "$HEREDOC_MSG" 0 ''

# --- Benign ---
check "pwd -> pass, empty" 'pwd' 0 ''
check "normal git push -> pass, empty" 'git push origin main' 0 ''

echo
if [[ $fails == 0 ]]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
