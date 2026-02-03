#!/bin/bash
# Dotfiles installation script
# Creates symlinks from dotfiles repo to home directory
#
# On Windows, requires one of:
# - Developer Mode enabled, OR
# - Running as Administrator
#
# Usage:
#   ./install.sh                    # Uses $HOME
#   ./install.sh --home /path/to/home  # Uses specified directory

set -e

# Parse arguments
TARGET_HOME="$HOME"
while [[ $# -gt 0 ]]; do
    case $1 in
        --home)
            TARGET_HOME="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$TARGET_HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Enable native symlinks on Windows/MSYS
export MSYS=winsymlinks:nativestrict

echo "Dotfiles installation"
echo "====================="
echo "Source: $DOTFILES_DIR"
echo "Target: $TARGET_HOME"
echo ""

# Test if we can create symlinks
test_symlink_support() {
    local test_dir=$(mktemp -d)
    local test_file="$test_dir/test_file"
    local test_link="$test_dir/test_link"

    echo "test" > "$test_file"

    if ln -s "$test_file" "$test_link" 2>/dev/null; then
        if [ -L "$test_link" ]; then
            rm -rf "$test_dir"
            return 0
        fi
    fi

    rm -rf "$test_dir"
    return 1
}

echo "Checking symlink support..."
if ! test_symlink_support; then
    echo ""
    echo "ERROR: Cannot create native symlinks."
    echo ""
    echo "On Windows, you need one of the following:"
    echo "  1. Enable Developer Mode:"
    echo "     Settings > Privacy & Security > For developers > Developer Mode"
    echo ""
    echo "  2. Run Git Bash as Administrator"
    echo ""
    echo "After enabling, restart Git Bash and run this script again."
    exit 1
fi
echo "Symlink support: OK"
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
mkdir -p "$TARGET_HOME/.claude/commands"

# Claude commands
for cmd in "$DOTFILES_DIR"/claude/commands/*.md; do
    [ -e "$cmd" ] || continue
    create_link "$cmd" "$TARGET_HOME/.claude/commands/$(basename "$cmd")"
done

# Claude config files
[ -e "$DOTFILES_DIR/claude/settings.json" ] && \
    create_link "$DOTFILES_DIR/claude/settings.json" "$TARGET_HOME/.claude/settings.json"
[ -e "$DOTFILES_DIR/claude/CLAUDE.md" ] && \
    create_link "$DOTFILES_DIR/claude/CLAUDE.md" "$TARGET_HOME/.claude/CLAUDE.md"
[ -e "$DOTFILES_DIR/claude/statusline.ps1" ] && \
    create_link "$DOTFILES_DIR/claude/statusline.ps1" "$TARGET_HOME/.claude/statusline.ps1"

# Install bash.d files
echo ""
echo "Installing bash.d configuration..."
mkdir -p "$TARGET_HOME/.bash.d"

for bashfile in "$DOTFILES_DIR"/bash.d/*.sh; do
    [ -e "$bashfile" ] || continue
    create_link "$bashfile" "$TARGET_HOME/.bash.d/$(basename "$bashfile")"
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
