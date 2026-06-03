---
description: Lightweight command for trivial changes — intake, Linear ticket, worktree, auto-implementation in new tab
allowed-tools: Bash, Read, Grep, Glob, AskUserQuestion, mcp__linear-server__save_issue, mcp__linear-server__get_issue, mcp__linear-server__list_projects
argument-hint: [linear-project-or-parent-task] [description]
---

You are helping the user quickly ship a trivial change. This command handles intake, Linear ticket creation, worktree setup, and launches a new terminal tab for auto-implementation.

## Your Task

### Step 1: Parse Arguments

{{#if $ARGUMENTS}}
Raw arguments: "{{$ARGUMENTS}}"
{{/if}}

Parse the arguments:
- **First token** (`$1`): **Optional.** If absent, set `target = none`. If present: treat as a **parent task ID** when it matches a ticket ID pattern (letters-digits, e.g. `INT-123`, `ENG-45`), otherwise treat it as a **Linear project name**.
- **Remaining tokens**: treat as the change description (optional — can come from conversation instead).

{{#unless $ARGUMENTS}}
No arguments provided. You will ask about the description and type during intake. No project or parent task will be set.
{{/unless}}

### Step 2: Validate Git State

Run these checks sequentially. If any fails, inform the user and exit.

1. Verify this is a git repo: `git rev-parse --git-dir`
2. Verify on `main` branch: `git branch --show-current` — must output `main`
3. Verify clean working tree: `git diff --quiet` and `git diff --cached --quiet`
4. Pull latest: `git pull -r`

If a check fails, print a clear error:
- Not a git repo → "Error: Not in a git repository."
- Not on main → "Error: Must be on 'main' branch (currently on '{branch}'). Switch to main first."
- Uncommitted changes → "Error: Uncommitted changes detected. Commit or stash them first."
- Pull fails → "Error: Failed to pull latest changes."

### Step 3: Conversational Intake

Goal: understand the change well enough to create a ticket and determine the branch type. Keep it lightweight — 1-2 rounds max.

{{#if $2}}
Description provided: "{{$2}}"

Briefly confirm your understanding of the change with the user. Determine the branch type (feat/fix/chore) from the description.
{{else}}
No description provided. Use `AskUserQuestion` to understand:
{{/if}}

{{#unless $2}}
Ask with `AskUserQuestion` (combine into one round if possible):

1. **What**: "What change do you need to make?" — free text (use "Other" option path)
2. **Type**: "What kind of change is this?" — options:
   - `feat` — new functionality or capability
   - `fix` — bug fix or correction
   - `chore` — maintenance, config, tooling, refactoring
{{/unless}}

By the end of this step you must have:
- A clear understanding of the change
- The branch type prefix (`feat/`, `fix/`, or `chore/`)
- The Linear target (project name or parent task ID), or `none` if not provided

### Step 4: Create Linear Ticket

Use `mcp__linear-server__save_issue` to create the ticket:
- `title`: concise title derived from intake
- `team`: "INT"
- `description`: brief description with acceptance criteria from the intake
- `project`: set only if target is a project name
- `parentId`: set only if target is a parent task ID
- If `target = none`, omit both fields
- `state`: "In Progress"
- `assignee`: "me"

From the response, extract the ticket identifier (e.g., `INT-456`). This is the `TICKET_ID`.

Display:
```
Ticket created: {TICKET_ID} — {title}
```

### Step 5: Create Worktree

Derive the branch name:
1. Lowercase the ticket ID (e.g., `INT-456` → `int-456`)
2. Create a slug from the title (lowercase, replace spaces/special chars with hyphens, max 40 chars)
3. Branch name: `{type}/{ticket-id-lowercase}-{slug}` (e.g., `feat/int-456-add-entity-property`)

Compute the worktree path:
1. Get repo root: `git rev-parse --show-toplevel`
2. Get repo name: basename of repo root
3. Worktree dir: `{repo-parent}/{repo-name}-worktrees/{ticket-id-lowercase}-{slug}`

Create the worktree:
```bash
git worktree add -b {branch-name} {worktree-path}
```

If this fails, inform the user and exit.

Then record the worktree in `~/.claude_repos` so it shows up in the `cd-repo` / `lclaude` picker later. Run as a **single Bash command** — the helper normalizes the path to the picker's `/c/...` form, so passing the worktree path in either form is fine:

```bash
bash ~/.claude/scripts/record-repo.sh "{worktree-path}"
```

### Step 6: Launch Implementation Tab

Open a new Windows Terminal tab pointing to the worktree, running `/ds:work-on +auto-plan`.

Run this as a **single Bash command** — inline `$(...)` subshells resolve paths without needing separate lookup steps. Only substitute `{TICKET_ID}` and `{worktree-path}` (the Unix-style worktree path from Step 5):

```bash
wt.exe -w 0 new-tab --profile "Git Bash" --title "{TICKET_ID}" --suppressApplicationTitle --startingDirectory "$(cygpath -w {worktree-path})" "$(cygpath -w /usr/bin/bash)" -c "$HOME/.local/bin/claude.exe '/ds:work-on +auto-plan'"
```

**Important**: `/ds:work-on +auto-plan` is wrapped in single quotes so it is passed as **one argument** to the claude CLI. Without this quoting, `+auto-plan` becomes a separate argument and the auto-plan flag is silently lost.

### Step 7: Summary

```
Quick setup complete:
  Ticket:   {TICKET_ID} — {title}
  Branch:   {branch-name}
  Worktree: {worktree-path}
  History:  added to cd-repo/lclaude picker
  Tab:      launched with /ds:work-on +auto-plan

Switch to the new tab (Ctrl+Tab) to monitor implementation.
```

This session is now free for other work.

### Error Handling

- **Not in a git repo**: exit with clear message
- **Not on main**: exit with message suggesting branch switch
- **Uncommitted changes**: exit with message suggesting commit/stash
- **Ticket creation fails**: show Linear API error, suggest retry
- **Worktree creation fails**: show error, note the ticket was already created
- **Tab launch fails**: show error, print the manual command to run
