#!/usr/bin/env bash
# Bookmark a Claude Code session to the cross-repo named-sessions index.
# Usage: namex.sh <name>
# Called from the /namex slash command inside a Claude session.

set -euo pipefail

NAME="${1:?Usage: namex.sh <name>}"
INDEX_FILE_UNIX="${CLAUDE_NAMED_SESSIONS:-/c/work/claude-data/named-sessions.json}"
INDEX_FILE=$(cygpath -w "$INDEX_FILE_UNIX")
CLAUDE_DIR="$HOME/.claude/projects"

# Derive project key (same encoding Claude uses: replace \ and : with -)
WIN_PATH=$(cygpath -w "$(pwd)")
PROJECT_KEY=$(echo "$WIN_PATH" | sed 's/[:\\]/-/g')
PROJECT_DIR="$CLAUDE_DIR/$PROJECT_KEY"

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: no Claude project directory found at $PROJECT_DIR"
    exit 1
fi

# Find current session: most recently modified .jsonl file
SESSION_FILE=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1)
if [[ -z "$SESSION_FILE" ]]; then
    echo "Error: no session files found in $PROJECT_DIR"
    exit 1
fi
SESSION_ID=$(basename "$SESSION_FILE" .jsonl)

# Get git branch (empty string if not in a repo)
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

# Ensure index directory exists
mkdir -p "$(dirname "$INDEX_FILE_UNIX")"

# Add or update entry in the index
node -e "
const fs = require('fs');
const [indexFile, name, sessionId, projectPath, gitBranch] = process.argv.slice(1);

const entries = fs.existsSync(indexFile)
    ? JSON.parse(fs.readFileSync(indexFile, 'utf8'))
    : [];

const entry = { name, sessionId, projectPath, gitBranch, namedAt: new Date().toISOString() };

const idx = entries.findIndex(e => e.sessionId === entry.sessionId);
if (idx >= 0) entries[idx] = entry;
else entries.unshift(entry);

fs.writeFileSync(indexFile, JSON.stringify(entries, null, 2) + '\n');
console.log('Bookmarked: ' + name + ' (' + sessionId.slice(0, 8) + '...)');
console.log('Project:    ' + projectPath);
console.log('Branch:     ' + (gitBranch || '-'));
console.log();
console.log('Tip: also run /name ' + name + ' to set it in the built-in /resume picker.');
" "$INDEX_FILE" "$NAME" "$SESSION_ID" "$WIN_PATH" "$GIT_BRANCH"
