#!/bin/bash
# Tests for claude-tab.sh (claude_tab).
# Run: bash test_claude_tab.sh

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/claude-tab.sh"

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Isolated fixtures under a real /c/... path ($HOME) so cygpath -w <-> -u
# round-trips cleanly (/tmp maps onto a different path and would not).
test_root="$HOME/.claude-tab-test.$$"
mkdir -p "$test_root"
trap 'rm -rf "$test_root"' EXIT

launched="$test_root/launched"
wt_args="$test_root/wt-args"

# Stand-in for the claude binary: records its arguments, one per line, then the
# environment it was started with.
fake_claude="$test_root/fake-claude.sh"
cat > "$fake_claude" <<'FAKE_EOF'
#!/bin/bash
printf 'ARG:%s\n' "$@" > "$LAUNCHED_FILE"
env >> "$LAUNCHED_FILE"
FAKE_EOF
chmod +x "$fake_claude"

# A shell function beats a PATH lookup, so both stubs work without a stub binary
# and without a test-only seam in the script.
claude_bin() { printf '%s\n' "$fake_claude"; }

# Stands in for the terminal: records the tab's arguments, then runs the tab's
# own command line (its last argument) here instead of opening a tab.
wt.exe() {
    printf '%s\n' "$@" > "$wt_args"
    bash -c "${!#}"
}

export LAUNCHED_FILE="$launched"

# The parent-session environment Claude Code injects into every Bash subprocess,
# which a tab launched from a Claude session would otherwise inherit.
inherited_env=(
    CLAUDE_CODE_CHILD_SESSION
    CLAUDE_CODE_SESSION_ID
    CLAUDE_CODE_MESSAGING_SOCKET
    CLAUDE_CODE_MESSAGING_TOKEN
    CLAUDE_PID
    TRACEPARENT
    AI_AGENT
    CLAUDE_EFFORT
)
export CLAUDE_CODE_CHILD_SESSION=1
export CLAUDE_CODE_SESSION_ID=parent-session-id
export CLAUDE_CODE_MESSAGING_SOCKET='\.\pipe\LOCAL\cc-msg-parent'
export CLAUDE_CODE_MESSAGING_TOKEN=parent-token
export CLAUDE_PID=4242
export TRACEPARENT=00-parenttrace-parentspan-01
export AI_AGENT=claude-code_agent
export CLAUDE_EFFORT=xhigh

prompt="/ds:work-on +auto-plan"
claude_tab "INT-1" "$test_root" "$prompt"

# 1. The prompt reaches claude as a single argument (split, +auto-plan is lost)
mapfile -t args < <(grep '^ARG:' "$launched" | sed 's/^ARG://')
if [[ ${#args[@]} -eq 1 && "${args[0]}" == "$prompt" ]]; then
    pass "prompt passed as one argument"
else
    fail "expected 1 argument '$prompt', got ${#args[@]}: ${args[*]}"
fi

# 2. None of the parent session's environment reaches the new session.
# PATH is the control: without it the env dump is missing or empty, and an
# absence check would pass for the wrong reason.
leaked=()
for var in "${inherited_env[@]}"; do
    grep -q "^$var=" "$launched" && leaked+=("$var")
done
if ! grep -q '^PATH=' "$launched" 2>/dev/null; then
    fail "no environment captured from the launched session"
elif [[ ${#leaked[@]} -eq 0 ]]; then
    pass "parent session environment stripped"
else
    fail "inherited by the launched session: ${leaked[*]}"
fi

# 3. Title and starting directory reach the terminal
if grep -Fxq "INT-1" "$wt_args"; then
    pass "tab title forwarded"
else
    fail "title 'INT-1' not in tab arguments: $(tr '\n' ' ' < "$wt_args")"
fi

expected_dir="$(cygpath -w "$test_root")"
if grep -Fxq "$expected_dir" "$wt_args"; then
    pass "starting directory forwarded"
else
    fail "expected starting directory '$expected_dir' not in tab arguments: $(tr '\n' ' ' < "$wt_args")"
fi

echo ""
if [[ $failures -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
fi
exit $((failures > 0))
