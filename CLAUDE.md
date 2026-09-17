# CLAUDE.md

Conventions for working in this repo. `claude/CLAUDE.md` here is the *global* user-level instruction
file (symlinked to `~/.claude/CLAUDE.md`) — it carries rules that apply in every repo, not these.

# Symlink Management

`install.sh` links whole directories, not individual files: `~/.claude/commands`, `~/.claude/hooks`,
`~/.claude/scripts`, `~/.claude/skills`, `~/.claude/overlays` and `~/.bash.d` are each one symlink
into this repo. A directory symlink resolves at access time, so **adding, renaming or deleting a file
here needs no install run** — every home sees the change at once. Only the four single-file targets
(`claude/settings.json`, `claude/CLAUDE.md`, `claude/statusline.sh`, `vscode/settings.json`) are
linked one by one.

Re-run the install script only to set up a new home, or after adding a new top-level target to
`install.sh` itself. Each home is separate: Windows and WSL need their own run.

Because those directories *are* the repo when read through the link, nothing may write runtime state
into them — it would land in git.

`git/shared.gitconfig` is the one target that is not a link: `install.sh` adds an `include.path`
entry for it to each home's `~/.gitconfig`. Settings the Windows and WSL homes must agree on go in
that file; per-machine ones stay in each home's own `~/.gitconfig`. Editing the shared file needs no
install run.

Content that isn't ours lives outside the linked directories: machine-specific and other-repo bash
functions in `~/.bash.d.local/` (sourced by `~/.bashrc` alongside `~/.bash.d`), and skills installed
by the `skills` CLI inside `claude/skills/`, excluded per clone via `.git/info/exclude`. `install.sh`
relocates both automatically on first run.

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
