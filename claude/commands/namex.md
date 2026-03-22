---
description: Bookmark the current session with a name for cross-repo resuming
allowed-tools: Bash(cygpath:*), Bash(ls:*), Bash(node:*), Bash(cat:*), Bash(git branch:*)
argument-hint: "<name>"
---

Bookmark the current Claude Code session with a human-friendly name. Saves it to a cross-repo index that `resumex` (bash function) can read.

{{#if $ARGUMENTS}}
## Steps

1. **Derive the project key** (same encoding Claude uses for `~/.claude/projects/`):
   ```bash
   cygpath -w "$(pwd)"
   ```
   Then in a node one-liner: replace every `\` and `:` with `-` to get the key.

2. **Find the current session ID**: list `.jsonl` files in `~/.claude/projects/{project-key}/` sorted by modification time (most recent first). The most recent `.jsonl` file is the current session. Extract its filename (without `.jsonl`) as the session ID.

3. **Get git branch**:
   ```bash
   git branch --show-current
   ```

4. **Read or create the named-sessions index** at `${CLAUDE_NAMED_SESSIONS:-/c/work/claude-data/named-sessions.json}`. If it doesn't exist, start with `[]`.

5. **Add or update the entry** using a `node` one-liner:
   - If an entry with the same `sessionId` exists, update its `name` and `namedAt`
   - Otherwise, append a new entry:
     ```json
     {
       "name": "{{$ARGUMENTS}}",
       "sessionId": "<from step 2>",
       "projectPath": "<Windows path from step 1>",
       "gitBranch": "<from step 3>",
       "namedAt": "<ISO timestamp>"
     }
     ```
   - Write the updated JSON back (pretty-printed with 2-space indent)

6. **Confirm** to the user:
   - Show the saved entry
   - Suggest: "Run `/name {{$ARGUMENTS}}` to also set this name in Claude's built-in `/resume` picker."

## Important

- Use separate Bash calls for each step (no `&&` chaining)
- Use `node -e` for JSON manipulation (no python available)
- Use absolute paths (no `cd`)
{{else}}
No name provided. Usage: `/namex <name>`

Example: `/namex permissions-strategy`
{{/if}}
