# Git for Windows: route SSH through the Windows OpenSSH agent service. Its named
# pipe survives a cleared %TEMP%, where Git Bash's own ssh-agent keeps its socket,
# and every process reaches it, including ones that never source this file. git
# reaches it through core.sshCommand, which install.sh sets.
command -v cygpath >/dev/null 2>&1 || return 0

WIN_SSH_ADD=/c/Windows/System32/OpenSSH/ssh-add.exe
[ -x "$WIN_SSH_ADD" ] || { unset WIN_SSH_ADD; return 0; }

# Windows ssh.exe prefers SSH_AUTH_SOCK over the pipe, so a Git Bash agent's socket must not leak in.
unset SSH_AUTH_SOCK SSH_AGENT_PID

# The service keeps added keys across reboots, so this prompts once per key, ever.
# ssh-add exits 1 when the agent is running but holds no keys.
if [[ $- == *i* ]]; then
    "$WIN_SSH_ADD" -l >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        mapfile -t ssh_keys < <(sed -n 's/^[[:space:]]*IdentityFile[[:space:]]\+//p' ~/.ssh/config 2>/dev/null | sort -u)
        for key in "${ssh_keys[@]}"; do
            "$WIN_SSH_ADD" "$(cygpath -w "${key/#\~/$HOME}")"
        done
        unset ssh_keys key
    fi
fi
unset WIN_SSH_ADD
