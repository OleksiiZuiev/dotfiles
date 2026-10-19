#!/bin/bash
# Tests for `repo-gh` (repo-gh.sh) against a fixture repo, fixture overlays and a stub `gh`.
# Run: bash claude/scripts/test_repo_gh.sh
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/repo-gh.sh"
fails=0

# A Windows path: Git for Windows cannot resolve Git Bash's /tmp.
root="$(cygpath -m "$(mktemp -d)")"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin" "$root/overlays" "$root/repos/acme" "$root/repos/bare" "$root/outside"
git -C "$root/repos/acme" init --quiet
git -C "$root/repos/bare" init --quiet
cat > "$root/bin/gh" <<'EOF'
#!/bin/bash
if [[ "$1 $2 $3" == "auth token --user" ]]; then
  [[ "$4" == "ghost" ]] && { echo "no oauth token found for ghost" >&2; exit 1; }
  echo "token-for-$4"
  exit 0
fi
echo "GH_TOKEN=[${GH_TOKEN-unset}] args=[$*]"
EOF
chmod +x "$root/bin/gh"
PATH="$(cygpath -u "$root")/bin:$PATH"
unset GH_TOKEN
export CLAUDE_OVERLAYS_DIR="$root/overlays"

check() { # $1 name  $2 actual  $3 expected
  if [[ "$2" == "$3" ]]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n      got [%s], want [%s]\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}
in_dir() { # $1 dir, then the command; a subshell so the test's own directory is untouched
  local dir="$1"; shift
  (cd "$dir" && "$@")
}

# --- help ---
out=$(repo-gh --help); code=$?
check "--help -> exit 0" "$code" 0
check "--help -> usage, gh not run" "$([[ "$out" == *"Usage: repo-gh"* && "$out" != *"args=["* ]] && echo yes)" yes

# --- account named in ## Workflow ---
printf '# Steering overlay — acme\n\n## Workflow\ndelivery: pr\ngithub-account: octo\n' \
  > "$root/overlays/acme.md"
check "account -> gh runs with its token, args passed through" \
  "$(in_dir "$root/repos/acme" repo-gh pr create --title "a b")" \
  "GH_TOKEN=[token-for-octo] args=[pr create --title a b]"

git -C "$root/repos/acme" -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m init
git -C "$root/repos/acme" worktree add --quiet "$root/acme-wt" -b feature
check "account -> resolved from a worktree by the main checkout's name" \
  "$(in_dir "$root/acme-wt" repo-gh pr list)" \
  "GH_TOKEN=[token-for-octo] args=[pr list]"

# --- no account ---
check "no overlay -> gh runs as the active account" \
  "$(in_dir "$root/repos/bare" repo-gh pr list)" \
  "GH_TOKEN=[unset] args=[pr list]"

printf '# Steering overlay — bare\n\n## Workflow\ndelivery: pr\n' > "$root/overlays/bare.md"
check "overlay without the line -> gh runs as the active account" \
  "$(in_dir "$root/repos/bare" repo-gh pr list)" \
  "GH_TOKEN=[unset] args=[pr list]"

printf '# Steering overlay — bare\n\n## Plan directives\n- github-account: nope\n\n## Workflow\ndelivery: pr\n\n## Distill ledger\ngithub-account: nope\n' \
  > "$root/overlays/bare.md"
check "line outside ## Workflow -> ignored" \
  "$(in_dir "$root/repos/bare" repo-gh pr list)" \
  "GH_TOKEN=[unset] args=[pr list]"

check "outside a git repo -> gh runs as the active account" \
  "$(in_dir "$root/outside" repo-gh api user)" \
  "GH_TOKEN=[unset] args=[api user]"

# --- the named account has no token ---
printf '## Workflow\ngithub-account: ghost\n' > "$root/overlays/acme.md"
out=$(in_dir "$root/repos/acme" repo-gh pr list 2>&1); code=$?
check "no token -> exit 1" "$code" 1
check "no token -> names the login, gh not run" \
  "$([[ "$out" == *"ghost"* && "$out" != *"args=["* ]] && echo yes || echo "no: $out")" yes

(( fails == 0 )) && echo "All passed" || { echo "$fails failed"; exit 1; }
