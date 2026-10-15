# Dotfiles

Personal configuration files managed with symlinks.

## What's Tracked

This section describes directories, not the files in them. Each file carries its own summary — a
command's `description:` frontmatter, a bash function's `--help` — and that is the one place to read it.

### Claude Code Configuration (`claude/`)

- `commands/` - Slash commands. `ds/` holds the Linear-ticket and PR workflow, invoked as `/ds:<name>`
  (`/ds:work-on`, `/ds:review`, `/ds:polish-pr` and friends); the top level holds general-purpose ones
  (`/git-commit`, `/code`). Every `.md` at any depth is a command.
- `hooks/` - Hook scripts referenced from `settings.json`, each with its test beside it — e.g.
  `block-bad-bash.sh`, a `PreToolUse` guard on Bash calls.
- `scripts/` - Helpers that commands, hooks and bash functions call, with their tests beside them.
  Two subsystems have their own folder: `sessions/` (the session index — its lifecycle hook, store and
  the `sessions` view) and `tasks/` (the `task` CLI for vault tasks).
- `skills/` - One directory per skill, each with a `SKILL.md`. Skills installed by the `skills` CLI are
  moved in here and excluded from git per clone (see the install steps below).
- `overlays/` - Repo-keyed personal steering, one `{repo-key}.md` per repo. Written by `/ds:distill`,
  read by `/ds:work-on`.
- `settings.json` - Claude Code settings (permissions, hooks, env, status line)
- `CLAUDE.md` - Global instructions for Claude Code
- `statusline.sh` - Status line script

### Bash Configuration (`bash.d/`)

Modular bash scripts loaded via `~/.bashrc`, one function family per file. Every function answers
`--help`, which is the source of truth for its usage. The ones meant to be typed:

- `lclaude`, `lcode`, `cd-repo` - Open Claude, VS Code or a shell in a recently used repo
- `gsw` - Switch to a recent branch
- `start-worktree`, `clean-worktrees` - Create a worktree; remove the ones whose PRs merged
- `claude-merge`, `claude-rebase` - Merge or rebase with Claude resolving conflicts
- `sessions` - Every Claude session, grouped by ticket
- `task` - Vault tasks with IDs and a status in frontmatter
- `plan` - The plan registry: named sets of vault tasks

The rest are helpers for these and for the `/ds:*` commands: `repo-roots.sh`, `repo-pick.sh`,
`claude-bin.sh`, `stack-parent.sh`, `worktree-teardown.sh`, `sweep-launch.sh`. `sessions.sh`,
`task.sh` and `plan.sh` are one-line shims that source their subsystem from `claude/scripts/`; the
Windows-node wrapper, database opener and Linear cache they share are in `claude/scripts/lib/`.

### Other

- `git/shared.gitconfig` - Git settings every home must agree on (see Shared Git Config below)
- `vscode/settings.json` - VS Code user settings
- `local/bash.d.example/` - Template for machine-specific bash settings (see Machine-Specific
  Configuration below)

## Installation

### New Machine Bootstrap

```bash
# Clone the repo (repos live under /c/work/github/{org}/{repo})
git clone https://github.com/OleksiiZuiev/dotfiles.git /c/work/github/OleksiiZuiev/dotfiles

# Run the install script
cd /c/work/github/OleksiiZuiev/dotfiles
./install.sh
```

The script will:
1. Back up anything already at a target to `~/.dotfiles-backup-<timestamp>/`
2. Move content that isn't ours out of the way — other-repo bash functions to `~/.bash.d.local/`,
   skills installed by the `skills` CLI into `claude/skills/` (excluded per clone)
3. Create symlinks from your home directory to the repo

### Manual Bashrc Update

Add this to your `~/.bashrc` if not already present:

```bash
# Load modular bash configurations
for file in ~/.bash.d/*.sh ~/.bash.d.local/*.sh; do
    [ -r "$file" ] && source "$file"
done
```

## Adding New Configurations

Commands, hooks, scripts, skills, overlays and bash modules are reached through **one symlink per
directory**, which resolves at access time. Create the file in the repo and every home has it —
no install run, no reload beyond `source ~/.bashrc` for a new bash module.

Re-run `./install.sh` only to set up a new home, or after adding a new top-level target to the script
itself. Windows and WSL are separate homes and each needs its own run.

Because a linked directory *is* the repo when read through the link, nothing may write runtime state
into one — it would land in git. Machine-specific bash functions belong in `~/.bash.d.local/`.

## Machine-Specific Configuration

For settings that shouldn't be version controlled (machine-specific paths, secrets):

1. Copy `local/bash.d.example/local.sh.example` to `~/.bash.d.local/local.sh`
2. Edit with your machine-specific settings
3. The file will be loaded automatically but won't be in git

`~/.bash.d.local/` is the home for anything `~/.bash.d` can't hold: `~/.bash.d` is a symlink into this
repo, so a file placed there would be a file placed in git.

## Windows Terminal

Windows Terminal's `settings.json` is not symlinked from here — it lives under
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\` and Windows Terminal
rewrites it whenever settings change through the UI. Apply these overrides by hand per machine.

The WSL app ships its own profile fragment
(`%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\Microsoft.WSL\{guid}.json`) that sets
`"suppressApplicationTitle": true`. Windows Terminal then ignores every title the running application
emits, so the tab keeps the distro name and Claude Code's session title never shows — unlike a Git
Bash tab. The fragment is regenerated when the WSL app updates, so the override belongs in your own
`settings.json`, whose profile entries layer on top of fragments. Add to the WSL profile entry in
`profiles.list`, matched by its `guid`:

```json
"bellStyle": [ "audible", "window", "taskbar" ],
"suppressApplicationTitle": false
```

`bellStyle` matches the `Git Bash` profile, so the tab flashes and the taskbar button blinks when
Claude Code rings the bell.

## Directory Structure

```
dotfiles/
├── README.md
├── CLAUDE.md               # instructions for working on this repo
├── install.sh
├── claude/
│   ├── commands/
│   │   └── ds/
│   ├── hooks/
│   ├── scripts/
│   │   ├── sessions/
│   │   └── tasks/
│   ├── skills/
│   ├── overlays/
│   ├── settings.json
│   ├── CLAUDE.md
│   └── statusline.sh
├── bash.d/
├── git/
│   └── shared.gitconfig
├── vscode/
│   └── settings.json
└── local/
    └── bash.d.example/
```

## Symlink Targets

One symlink per row. The directory rows are a single link on the directory itself, so their contents
follow the repo with no install run.

| Source | Target | Kind |
|--------|--------|------|
| `claude/commands` | `~/.claude/commands` | directory |
| `claude/hooks` | `~/.claude/hooks` | directory |
| `claude/scripts` | `~/.claude/scripts` | directory |
| `claude/skills` | `~/.claude/skills` | directory |
| `claude/overlays` | `~/.claude/overlays` | directory |
| `bash.d` | `~/.bash.d` | directory |
| `claude/settings.json` | `~/.claude/settings.json` | file |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | file |
| `claude/statusline.sh` | `~/.claude/statusline.sh` | file |
| `vscode/settings.json` | `%APPDATA%/Code/User/settings.json` | file |

## Shared Git Config

`git/shared.gitconfig` is not linked. `install.sh` adds an `include.path` entry for it to each
home's `~/.gitconfig`, so the settings the homes must agree on live in one tracked file while each
home keeps its per-machine ones — editor path, pager, credential helper — in its own file.

It carries `core.autocrlf = input`. The homes disagreeing here is what makes the same checkout show
every CRLF file as modified from whichever side does not convert, and lets a commit from that side
rewrite whole files to CRLF.

Adding a setting to that file needs no install run, since the include already points at it. Adding
the include to a **new** home does.

## Windows Notes

On Windows, creating a symlink is a privileged operation unless Developer Mode is on. The install
script needs one of:

1. **Developer Mode enabled** — no elevation, plain `./install.sh`
2. **Git Bash running as Administrator** — a UAC prompt every run

`install.sh` exports `MSYS=winsymlinks:nativestrict`, so Git Bash makes real symlinks or fails
loudly; it never silently falls back to copying. The script tests this up front and stops with
instructions if symlinks can't be created.

### Enabling Developer Mode (recommended)

1. Open **Settings > Privacy & Security > For developers**
2. Turn **Developer Mode** on, and confirm the prompt
3. Restart Git Bash so the new privilege is picked up
4. Check it took: `MSYS=winsymlinks:nativestrict ln -s /tmp /tmp/link-probe` succeeds, then
   `rm /tmp/link-probe`

With Developer Mode on, `./install.sh` runs unelevated and `install-admin.ps1` is no longer needed.
Corporate policy can disable the toggle; if it's greyed out, use the admin route below.

### Corporate Windows (no Developer Mode)

If Developer Mode is disabled by IT policy, running Git Bash as Administrator changes `$HOME` to the admin user's directory. Use the `--home` flag to specify the correct target:

```bash
# Open Git Bash as Administrator, then:
cd /c/work/github/OleksiiZuiev/dotfiles
./install.sh --home /c/Users/YourUsername
```

This creates symlinks in your user's home directory while running with admin privileges.

#### PowerShell Admin Wrapper (Recommended)

For convenience, create a local `install-admin.ps1` script that handles elevation and paths automatically:

```powershell
# Self-elevate to Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Configuration - edit these paths for your machine
# Common bash paths:
#   C:\Program Files\Git\bin\bash.exe (system-wide install)
#   C:\Users\<name>\AppData\Local\Programs\Git\bin\bash.exe (user install)
$bashPath = "C:\Program Files\Git\bin\bash.exe"
$dotfilesPath = "/c/work/github/YourUsername/dotfiles"
$targetHome = "/c/Users/YourUsername"

# Run install script
& $bashPath -c "cd $dotfilesPath && ./install.sh --home $targetHome"

Read-Host "Press Enter to close"
```

Save this in the dotfiles directory (it's gitignored since paths are machine-specific). Double-click to run - it will prompt for UAC elevation and run the install script with the correct paths.
