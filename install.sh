#!/bin/bash
# Dotfiles installation script
# Creates symlinks from dotfiles repo to home directory

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

echo "Dotfiles installation"
echo "====================="
echo "Source: $DOTFILES_DIR"
echo ""

# Track if we created any backups
made_backups=false

# Create backup if target exists and is not a symlink to the same source
backup_if_needed() {
    local target="$1"
    local source="$2"

    if [ -e "$target" ] || [ -L "$target" ]; then
        # Check if it's already a symlink to the correct source
        if [ -L "$target" ]; then
            local current_target
            current_target=$(readlink "$target" 2>/dev/null || true)
            if [ "$current_target" = "$source" ]; then
                return 1  # Already correctly linked
            fi
        fi

        # Create backup directory if needed
        if [ "$made_backups" = false ]; then
            mkdir -p "$BACKUP_DIR"
            made_backups=true
        fi

        local backup_path="$BACKUP_DIR/$(basename "$target")"
        echo "  Backing up: $target -> $backup_path"
        mv "$target" "$backup_path"
    fi
    return 0
}

# Create a symlink
create_link() {
    local source="$1"
    local target="$2"

    # Create parent directory if needed
    local target_dir=$(dirname "$target")
    mkdir -p "$target_dir"

    if backup_if_needed "$target" "$source"; then
        ln -s "$source" "$target"
        echo "  Linked: $target -> $source"
    else
        echo "  Skip (already linked): $target"
    fi
}

# Install Claude files
echo "Installing Claude configuration..."
mkdir -p "$HOME/.claude/commands"

# Claude commands
for cmd in "$DOTFILES_DIR"/claude/commands/*.md; do
    [ -e "$cmd" ] || continue
    create_link "$cmd" "$HOME/.claude/commands/$(basename "$cmd")"
done

# Claude config files
[ -e "$DOTFILES_DIR/claude/settings.json" ] && \
    create_link "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
[ -e "$DOTFILES_DIR/claude/CLAUDE.md" ] && \
    create_link "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
[ -e "$DOTFILES_DIR/claude/statusline.ps1" ] && \
    create_link "$DOTFILES_DIR/claude/statusline.ps1" "$HOME/.claude/statusline.ps1"

# Install bash.d files
echo ""
echo "Installing bash.d configuration..."
mkdir -p "$HOME/.bash.d"

for bashfile in "$DOTFILES_DIR"/bash.d/*.sh; do
    [ -e "$bashfile" ] || continue
    create_link "$bashfile" "$HOME/.bash.d/$(basename "$bashfile")"
done

echo ""
echo "Installation complete!"

if [ "$made_backups" = true ]; then
    echo ""
    echo "Backups created in: $BACKUP_DIR"
fi

echo ""
echo "Note: Add the following to your ~/.bashrc if not already present:"
echo ""
echo '  # Load modular bash configurations'
echo '  for file in ~/.bash.d/*.sh; do'
echo '      [ -r "$file" ] && source "$file"'
echo '  done'
