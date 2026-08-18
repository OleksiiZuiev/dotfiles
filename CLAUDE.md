# CLAUDE.md

Conventions for working in this repo. `claude/CLAUDE.md` here is the *global* user-level instruction
file (symlinked to `~/.claude/CLAUDE.md`) — it carries rules that apply in every repo, not these.

# Symlink Management

Files in this repo are symlinked to `~/.claude/` and `~/.bash.d/` by the install script. After creating new files that need to be symlinked, the install script must be re-run.

On Windows without Developer Mode, use `install-admin.ps1` in the repo root — it self-elevates to admin (UAC prompt) and runs `install.sh --home`.

#Commandments for writing bash functions
- These apply to shell functions in `bash.d/`.
- Every function must support `-h`/`--help`: print idiomatic CLI usage and `return 0` without side effects, intercepted as the function's first statement:
  ```bash
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      cat <<'EOF'
  Usage: <fn> <args>
  ...
  Options:
    -h, --help    Show this help and exit
  EOF
      return 0
  fi
  ```
- The `--help` text is the single source of truth for usage; keep the top-of-file comment to a brief one-line purpose.
- When you create or change a `bash.d/` function (its arguments or behavior), create or update its `--help` in the same change.
- Reference pattern: `bash.d/claude-merge-rebase.sh` (uses a shared usage helper when multiple functions share help).
