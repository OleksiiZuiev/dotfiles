---
name: ticket-context
description: Session-history documents for Linear tickets, stored outside the repo so worktrees share them. Use when creating a ticket context file from scratch, appending a session entry to one, or looking up where ticket context lives — covers the CLAUDE_TICKET_CONTEXTS_DIR convention and the document template.
---

# Ticket Context Documents

Session history for Linear tickets, stored outside the repo for worktree access.

## Configuration

Set the environment variable to customize the storage location:

```bash
export CLAUDE_TICKET_CONTEXTS_DIR="/c/work/ticket-contexts"
```

Default: `/c/work/ticket-contexts/`

## Structure

Each ticket gets its own file: `{TICKET-ID}.md` containing:
- Ticket info and Linear link
- Session history (accomplishments, decisions, files changed)

## Document Template

```markdown
# {TICKET-ID}: {Ticket Title}

## Ticket Info
- **Linear Link**: https://linear.app/team/issue/{TICKET-ID}
- **Created**: {YYYY-MM-DD}

## Sessions

### {YYYY-MM-DD HH:MM} - {Brief Session Title}
**Branch**: `{branch-name}`
**Repository**: `{repo-name}`

#### Accomplished
- {bullet list}

#### Key Decisions
- {decision}: {rationale}

#### Files Changed
- `{path}` - {description}

---
```

Omit a line or section the session has nothing to record for — `/ds:refine` runs before any
branch exists, and `/ds:review` changes no files.
