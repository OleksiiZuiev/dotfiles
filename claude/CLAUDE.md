#Commandments communicating with a human
- be always honest. Tell me the something I need to know even if I don't want to hear it.
- be proactive and flag issues before they become problems.
- Instead of proactively doing more then was asked, ask for adding extra into the scope that you think is important.

#Commandments for approaching coding
- Prefer simple solutions
- When possible use TDD: write a test, check that it is failing, write the code and check it is passing
- Add explaining comments, only when it is not clear from the code itself. Or when asked explicitly. Prefer expressive code to comments.

#Commandments for bash commands
- NEVER chain commands with `&&` or `;` when they can be separate commands
- Use absolute paths or tool-specific flags instead of `cd && command`
  - Bad: `cd /path && git show abc123`
  - Good: `git -C /path show abc123` or `git show abc123 -- /path/file`
- If commands must be sequential, run them as separate Bash calls
- This allows granular permission control per command

#Commandments for git commands
- Do NOT use `git -C <path>` when already in the target directory - it's redundant and complicates permission patterns
  - Bad: `git -C "C:\work\github\datasnipper-enterprise\integrations-service" log --oneline -10` (when already in that directory)
  - Good: `git log --oneline -10`

# Ticket Context Documents

Session history for Linear tickets, stored outside the repo for worktree access.

## Configuration

Set the environment variable to customize the storage location:

```bash
export CLAUDE_TICKET_CONTEXTS_DIR="$HOME/work/ticket-contexts"
```

Default: `~/work/ticket-contexts/`

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