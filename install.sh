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
        ln -sT "$source" "$target"
        echo "  Linked: $target -> $source"
    else
        echo "  Skip (already linked): $target"
    fi
}

# Hide a machine-local entry from git without committing anything: .git/info/exclude
# is per-clone and never leaves this machine.
git_exclude_add() {
    local pattern="$1"
    local exclude_file="$DOTFILES_DIR/.git/info/exclude"

    [ -d "$DOTFILES_DIR/.git" ] || return 0

    if grep -qxF "$pattern" "$exclude_file" 2>/dev/null; then
        return 0
    fi

    echo "$pattern" >> "$exclude_file"
    echo "  Git-excluded (machine-local): $pattern"
}

# Move entries a directory link would otherwise hide. Runs on a real directory in
# the home just before it is replaced by a link to its repo counterpart: anything
# that does not already point into this repo is relocated to $destination. Entries
# that do point into the repo are left for backup_if_needed, because the link
# supersedes them — dangling ones included.
rescue_foreign_entries() {
    local dir="$1"
    local destination="$2"

    [ -d "$dir" ] || return 0
    if [ -L "$dir" ]; then
        return 0
    fi

    local entry
    for entry in "$dir"/*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue

        case "$(readlink "$entry" 2>/dev/null || true)" in
            "$DOTFILES_DIR"/*) continue ;;
        esac

        mkdir -p "$destination"
        mv "$entry" "$destination/"
        echo "  Rescued: $entry -> $destination/"

        case "$destination" in
            "$DOTFILES_DIR"/*)
                git_exclude_add "${destination#$DOTFILES_DIR/}/$(basename "$entry")"
                ;;
        esac
    done
}

# Point a home's ~/.gitconfig at the settings the homes must share, leaving the
# per-machine ones already in that file alone. An include is used rather than a
# link because the two homes differ legitimately (editor path, pager) and a link
# would force them to be identical.
ensure_git_include() {
    local shared="$DOTFILES_DIR/git/shared.gitconfig"
    local target="$TARGET_HOME/.gitconfig"

    [ -e "$shared" ] || return 0

    # Git for Windows resolves a drive-letter path; an MSYS-style one it may not.
    # cygpath exists only there, which makes it the platform test.
    local include_path="$shared"
    if command -v cygpath >/dev/null 2>&1; then
        include_path="$(cygpath -m "$shared")"
    fi

    if git config --file "$target" --get-all include.path 2>/dev/null \
        | grep -qxF "$include_path"; then
        echo "  Skip (already included): $target"
        return 0
    fi

    git config --file "$target" --add include.path "$include_path"
    echo "  Git include added: $target -> $include_path"
}

# Install Claude files
echo "Installing Claude configuration..."
mkdir -p "$TARGET_HOME/.claude"

# Every directory below is linked as a directory rather than file by file, so a file
# added to or deleted from the repo reaches every home immediately and no home can
# drift out of date. Two consequences worth knowing:
#   - Every .md anywhere under commands/ is a slash command, at any nesting depth.
#   - Nothing may write runtime state into these directories; it would land in git.
create_link "$DOTFILES_DIR/claude/commands" "$TARGET_HOME/.claude/commands"
create_link "$DOTFILES_DIR/claude/hooks" "$TARGET_HOME/.claude/hooks"
create_link "$DOTFILES_DIR/claude/scripts" "$TARGET_HOME/.claude/scripts"

# Claude config files
[ -e "$DOTFILES_DIR/claude/settings.json" ] && \
    create_link "$DOTFILES_DIR/claude/settings.json" "$TARGET_HOME/.claude/settings.json"
[ -e "$DOTFILES_DIR/claude/CLAUDE.md" ] && \
    create_link "$DOTFILES_DIR/claude/CLAUDE.md" "$TARGET_HOME/.claude/CLAUDE.md"
[ -e "$DOTFILES_DIR/claude/statusline.sh" ] && \
    create_link "$DOTFILES_DIR/claude/statusline.sh" "$TARGET_HOME/.claude/statusline.sh"

# Claude overlays (repo-keyed personal steering)
if [ -d "$DOTFILES_DIR/claude/overlays" ]; then
    create_link "$DOTFILES_DIR/claude/overlays" "$TARGET_HOME/.claude/overlays"
fi

# Claude skills (each skill is a directory: SKILL.md plus any bundled files).
# Claude Code reads skills from ~/.claude/skills and nowhere else, so skills
# installed from outside this repo — the `skills` CLI bridges ~/.agents/skills in
# here — have to sit alongside ours. They are moved into the repo directory and
# excluded from git per clone, so one link can cover both.
if [ -d "$DOTFILES_DIR/claude/skills" ]; then
    rescue_foreign_entries "$TARGET_HOME/.claude/skills" "$DOTFILES_DIR/claude/skills"
    create_link "$DOTFILES_DIR/claude/skills" "$TARGET_HOME/.claude/skills"
fi

# Install VS Code settings
echo ""
echo "Installing VS Code configuration..."
VSCODE_APPDATA="$TARGET_HOME/AppData/Roaming"
if [ -d "$VSCODE_APPDATA/Code" ]; then
    VSCODE_USER_DIR="$VSCODE_APPDATA/Code/User"
    mkdir -p "$VSCODE_USER_DIR"
    [ -e "$DOTFILES_DIR/vscode/settings.json" ] && \
        create_link "$DOTFILES_DIR/vscode/settings.json" "$VSCODE_USER_DIR/settings.json"
else
    echo "  Skipped: VS Code not found at $VSCODE_APPDATA/Code"
fi

# Install git configuration
echo ""
echo "Installing git configuration..."
ensure_git_include

# Install bash.d files
echo ""
echo "Installing bash.d configuration..."

# Functions sourced from other repos, and this machine's own local.sh, live in the
# sibling ~/.bash.d.local so one link can cover ~/.bash.d entirely. ~/.bashrc
# sources both.
mkdir -p "$TARGET_HOME/.bash.d.local"
rescue_foreign_entries "$TARGET_HOME/.bash.d" "$TARGET_HOME/.bash.d.local"
create_link "$DOTFILES_DIR/bash.d" "$TARGET_HOME/.bash.d"

# Linux homes (WSL) get the same fzf as Windows: the distro package lags far behind (Ubuntu 24.04
# ships 0.44), and the `sessions` view needs the newer actions. Checked against the release's own
# checksum, installed ahead of the distro's on PATH.
FZF_VERSION=0.74.4
FZF_SHA256=05e6813a337cc722c3ed07e54a764b75cc5d671e2e60459db0ba696ee5fa7504
install_fzf() {
    local bin="$TARGET_HOME/.local/bin" tarball="fzf-$FZF_VERSION-linux_amd64.tar.gz" tmp
    if [[ "$("$bin/fzf" --version 2>/dev/null)" == "$FZF_VERSION "* ]]; then
        echo "  fzf $FZF_VERSION already installed"
        return 0
    fi
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/$tarball" "https://github.com/junegunn/fzf/releases/download/v$FZF_VERSION/$tarball" &&
        echo "$FZF_SHA256  $tmp/$tarball" | sha256sum -c --quiet - &&
        mkdir -p "$bin" &&
        tar -xzf "$tmp/$tarball" -C "$bin" fzf &&
        echo "  Installed fzf $FZF_VERSION to $bin"
    local status=$?
    rm -rf "$tmp"
    return $status
}
if [[ "$(uname -s)" == "Linux" ]]; then
    echo ""
    echo "Installing fzf..."
    install_fzf || echo "  Warning: fzf $FZF_VERSION was not installed"
fi

if command -v cygpath >/dev/null 2>&1; then
    echo ""
    echo "Registering the worktree prune task..."
    bash "$DOTFILES_DIR/claude/scripts/register-prune-worktrees.sh" ||
        echo "  Warning: rerun claude/scripts/register-prune-worktrees.sh"
fi

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
echo '  for file in ~/.bash.d/*.sh ~/.bash.d.local/*.sh; do'
echo '      [ -r "$file" ] && source "$file"'
echo '  done'
