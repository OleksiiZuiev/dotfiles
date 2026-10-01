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
# command (everything after the starting directory, the bash executable first)
# here instead of opening a tab. Double quotes are dropped from the command on
# the way, as the real wt.exe drops them: a tab launched with
# `bash -c "... \"What did you write\""` handed claude only `What`.
wt.exe() {
    printf '%s\n' "$@" > "$wt_args"
    local args=("$@") i
    for ((i = 0; i < ${#args[@]}; i++)); do
        [[ "${args[i]}" == "--startingDirectory" ]] && break
    done
    local command=("${args[@]:i+3}")
    bash "${command[@]//\"/}"
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

prompt='/ds:work-on +auto-plan; say "hi"'
claude_tab "INT-1" "$test_root" "$prompt"

# 1. The prompt reaches claude as a single argument, unchanged (split,
# +auto-plan is lost; a `;` or `"` must not reach any command line)
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

# 3. The launcher script the tab ran removes itself
launcher_path="$(tail -n 1 "$wt_args")"
if [[ "$launcher_path" != *claude-tab.* ]]; then
    fail "tab command does not end in a launcher script: $launcher_path"
elif [[ -e "$launcher_path" ]]; then
    fail "launcher script left behind: $launcher_path"
else
    pass "launcher script removed after launch"
fi

# 4. Title and starting directory reach the terminal
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

# 5. Every claude argument after the directory reaches claude, each as its own argument
claude_tab "INT-2" "$test_root" --resume abc-123
mapfile -t args < <(grep '^ARG:' "$launched" | sed 's/^ARG://')
if [[ "${args[*]}" == "--resume abc-123" && ${#args[@]} -eq 2 ]]; then
    pass "several claude arguments passed separately"
else
    fail "expected '--resume' 'abc-123', got ${#args[@]}: ${args[*]}"
fi

# --- --wsl: a tab in the WSL distro ---
# The WSL side's claude-bin.sh, which the launcher sources inside the tab.
wsl_home="$test_root/wsl-home"
mkdir -p "$wsl_home/.bash.d"
printf 'claude_bin() { printf "%%s\\n" %q; }\n' "$fake_claude" > "$wsl_home/.bash.d/claude-bin.sh"
wsl_args="$test_root/wsl-args"

# Stands in for wsl.exe: records its arguments, then runs the launcher (the last argument, a /mnt/c
# path) here with the WSL home.
wsl.exe() {
    printf '%s\n' "$@" > "$wsl_args"
    (( $# > 0 )) || return 1
    local launcher="${*: -1}"
    [[ "$launcher" == /mnt/c/* ]] && launcher=$(cygpath -u "C:${launcher#/mnt/c}")
    HOME="$wsl_home" bash "$launcher"
}
# The terminal stand-in for a WSL tab: the tab's command starts at wsl.exe.
wt.exe() {
    printf '%s\n' "$@" > "$wt_args"
    local args=("$@") i
    for ((i = 0; i < ${#args[@]}; i++)); do
        [[ "${args[i]}" == "wsl.exe" ]] && break
    done
    wsl.exe "${args[@]:i+1}"
}

: > "$launched"
claude_tab --wsl "UP-1" /home/someone/uplink --resume abc-123

# 6. The tab is a WSL tab in the session's directory
if grep -Fxq "Ubuntu" "$wt_args" && grep -Fxq "wsl.exe" "$wt_args"; then
    pass "--wsl opens a WSL tab"
else
    fail "no Ubuntu profile and wsl.exe in tab arguments: $(tr '\n' ' ' < "$wt_args")"
fi
if grep -A1 -Fx -- "--cd" "$wsl_args" 2>/dev/null | grep -Fxq "/home/someone/uplink"; then
    pass "--wsl starts in the session's directory"
else
    fail "expected --cd /home/someone/uplink in wsl.exe arguments: $(tr '\n' ' ' < "$wsl_args" 2>/dev/null)"
fi

# 7. The launcher runs the WSL side's claude with the arguments, its environment stripped
mapfile -t args < <(grep '^ARG:' "$launched" | sed 's/^ARG://')
if [[ "${args[*]}" == "--resume abc-123" && ${#args[@]} -eq 2 ]]; then
    pass "--wsl passes the claude arguments"
else
    fail "--wsl: expected '--resume' 'abc-123', got ${#args[@]}: ${args[*]}"
fi
if grep -q '^PATH=' "$launched" && ! grep -q '^CLAUDE_CODE_SESSION_ID=' "$launched"; then
    pass "--wsl strips the parent session environment"
else
    fail "--wsl: environment not captured, or the parent session id leaked"
fi

echo ""
if [[ $failures -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
fi
exit $((failures > 0))
