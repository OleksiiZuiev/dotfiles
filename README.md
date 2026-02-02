# Dotfiles

Personal configuration files managed with symlinks.

## What's Tracked

### Claude Code Configuration (`claude/`)

- `commands/` - Custom slash commands for Claude Code
  - `create-pr.md` - Create PR for a Linear ticket
  - `git-commit.md` - Commit changes with context
  - `implement.md` - Execute implementation plans
  - `polish-pr.md` - Address PR review comments
  - `refine.md` - Refine Linear tickets with acceptance criteria
  - `start-task.md` - Start work on a Linear ticket
- `settings.json` - Claude Code settings (permissions, hooks, model)
- `CLAUDE.md` - Global instructions for Claude Code
- `statusline.ps1` - Custom status line script

### Bash Configuration (`bash.d/`)

Modular bash scripts loaded via `~/.bashrc`:

- `git-helpers.sh` - Git helper functions (`gsw` for recent branch switching)
- `lclaude.sh` - Smart Claude launcher with project history

## Installation

### New Machine Bootstrap

```bash
# Clone the repo
git clone https://github.com/OleksiiZuiev/dotfiles.git ~/dotfiles

# Run the install script
cd ~/dotfiles
./install.sh
```

The script will:
1. Create `~/.claude/commands/` and `~/.bash.d/` directories
2. Back up any existing files to `~/.dotfiles-backup-<timestamp>/`
3. Create symlinks from your home directory to the repo

### Manual Bashrc Update

Add this to your `~/.bashrc` if not already present:

```bash
# Load modular bash configurations
for file in ~/.bash.d/*.sh; do
    [ -r "$file" ] && source "$file"
done
```

## Adding New Configurations

### New Claude Command

1. Create the command file in `claude/commands/your-command.md`
2. Run `./install.sh` to create the symlink

### New Bash Module

1. Create the script in `bash.d/your-module.sh`
2. Run `./install.sh` to create the symlink
3. Reload your shell or `source ~/.bashrc`

## Machine-Specific Configuration

For settings that shouldn't be version controlled (machine-specific paths, secrets):

1. Copy `local/bash.d.example/local.sh.example` to `~/.bash.d/local.sh`
2. Edit with your machine-specific settings
3. The file will be loaded automatically but won't be in git

## Directory Structure

```
dotfiles/
├── README.md
├── install.sh
├── claude/
│   ├── commands/
│   │   ├── create-pr.md
│   │   ├── git-commit.md
│   │   ├── implement.md
│   │   ├── polish-pr.md
│   │   ├── refine.md
│   │   └── start-task.md
│   ├── settings.json
│   ├── CLAUDE.md
│   └── statusline.ps1
├── bash.d/
│   ├── git-helpers.sh
│   └── lclaude.sh
└── local/
    └── bash.d.example/
        └── local.sh.example
```

## Symlink Targets

| Source | Target |
|--------|--------|
| `claude/commands/*.md` | `~/.claude/commands/` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/statusline.ps1` | `~/.claude/statusline.ps1` |
| `bash.d/*.sh` | `~/.bash.d/` |

## Windows Notes

On Windows with Git Bash, true symlinks require either:
1. Running Git Bash as Administrator, or
2. Enabling Developer Mode in Windows Settings

Without these, the install script creates copies instead of symlinks (default Git Bash behavior). This works but requires re-running `./install.sh` after making changes to the dotfiles repo.

To enable native symlinks in Git Bash:
1. Enable Developer Mode: Settings > Privacy & Security > For developers > Developer Mode
2. Or set `MSYS=winsymlinks:nativestrict` environment variable
