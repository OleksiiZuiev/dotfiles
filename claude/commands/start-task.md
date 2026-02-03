---
description: Gather context from Linear ticket and build implementation plan
allowed-tools: Bash, Read, Write, Grep, Glob, Task, AskUserQuestion, EnterPlanMode, ExitPlanMode, TodoWrite
argument-hint: <ticket-id> [--worktree] [extra context]
---

You are helping the user start work on a new task by gathering context and creating an implementation plan.

## Current Context

Working directory: !`pwd`
Current branch: !`git branch --show-current 2>/dev/null || echo "not in git repo"`

## Your Task

{{#if $1}}
{{! Check if --worktree flag is present in arguments }}
{{#if (contains $ARGUMENTS "--worktree")}}

## Worktree Mode

You are creating a new worktree for Linear ticket: **{{$1}}**

This mode will:
1. Validate you're on main/master branch
2. Create a new worktree with a clean branch
3. Spawn a new Claude Code session in the worktree to continue the planning flow

### Steps to Follow

1. **Validate Environment**
   - Check current branch is `main` or `master`
   - If not on main/master, use AskUserQuestion to ask: "You're on branch `<current-branch>`. Switch to main and continue?" with options:
     - "Yes, switch to main"
     - "No, abort"
   - If user chooses to switch, run `git checkout main` or `git checkout master` (whichever exists)
   - Run `git pull` to get latest changes from remote

2. **Fetch Linear Ticket Details**
   - Use the Task tool with MCP Linear integration to fetch ticket details for `{{$1}}`
   - Extract: ticket ID, title, type/labels, and description
   - This information will be used to generate the branch name

3. **Generate Branch Name**
   - Determine branch type from ticket:
     - If ticket type/labels contain "bug", "fix", or "defect" → use `fix/`
     - If ticket type/labels contain "feature", "enhancement", or "story" → use `feature/`
     - If ticket type/labels contain "chore", "task", or "maintenance" → use `chore/`
     - If ticket type/labels contain "refactor" → use `refactor/`
     - Default: `feature/`
   - Convert ticket ID to lowercase (e.g., `ENG-123` → `eng-123`)
   - Generate brief slug from ticket title:
     - Take first 4 significant words (skip articles like "the", "a", "an")
     - Convert to lowercase
     - Replace spaces with hyphens
     - Remove special characters
     - Example: "Add User Authentication Feature" → "add-user-authentication-feature"
   - Final format: `{type}/{id-lower}-{brief-slug}`
   - Example: `feature/eng-123-add-user-authentication`

4. **Confirm Branch Name**
   - Use AskUserQuestion to show the proposed branch name
   - Ask: "Branch name for this worktree?"
   - Provide the generated name as the default option
   - Allow user to modify if needed

5. **Create Worktree**
   - Get repository name: `basename $(git rev-parse --show-toplevel)`
   - Create worktrees directory if needed: `mkdir -p "../${repo_name}-worktrees"`
   - Create worktree with new branch:
     ```bash
     git worktree add "../${repo_name}-worktrees/{branch-name}" -b {branch-name}
     ```
   - Verify creation succeeded

6. **Open New Terminal with Claude and Start Task**
   - Get the absolute path of the worktree:
     ```bash
     worktree_abs_path=$(cd "../${repo_name}-worktrees/{branch-name}" && pwd)
     ```
   - Open a new Windows Terminal tab with Git Bash:
     ```bash
     wt.exe -w 0 -d "$worktree_abs_path" -- "C:/Users/OleksiiZuiev/AppData/Local/Programs/Git/bin/bash.exe" -l -i
     ```
     - `-w 0` opens a new tab in the current Windows Terminal window
     - `-d` sets the working directory to the worktree
     - `--` separator prevents command parsing issues
     - Uses full path to Git Bash (not WSL bash) with `-l -i` flags for proper environment loading
   - Display confirmation:
     ```
     ✓ Worktree created at: {worktree_abs_path}
     ✓ Branch: {branch-name}
     ✓ Git Bash opened in new terminal tab

     Next steps in the new tab:
     1. Run: claude
     2. Run: /start-task {{$1}}
     ```

### Important Notes

- The worktree is created in `../{repo-name}-worktrees/{branch-name}/`
- A new Windows Terminal tab opens with Claude Code ready
- Once Claude starts, manually run `/start-task {{$1}}` to begin planning
- If `wt.exe` fails, fall back to showing the path and command for manual execution

{{else}}

## Simple Mode

Create an implementation plan for Linear ticket: **{{$1}}**

{{#if $ARGUMENTS}}
Additional context from user: "{{$ARGUMENTS}}"
{{/if}}

### Ticket Context Configuration

Context path: `${CLAUDE_TICKET_CONTEXTS_DIR:-$HOME/work/ticket-contexts}`
Context file: `{context-path}/{{$1}}.md`

### Steps to Follow

0. **Load Existing Ticket Context (if exists)**
   - Check if `{context-path}/{{$1}}.md` exists
   - If yes, read and summarize previous sessions
   - Use this context to inform planning (avoid re-exploring solved problems, build on previous decisions)
   - Note: This helps maintain continuity across worktrees and sessions

1. **Fetch Linear Ticket Details**
   - Use the Task tool with the MCP Linear integration to fetch ticket details for `{{$1}}`
   - Extract the ticket title, description, and any linked resources
   - Look for Notion page links in the description or comments and fetch those automatically

2. **Explore the Codebase**
   - Use Grep, Glob, and Read tools to understand relevant code areas
   - Use the Task tool with subagent_type=Explore for broader context gathering
   - Focus on areas mentioned in the ticket or related to the feature/fix

3. **Ask Clarifying Questions**
   - If requirements are unclear or multiple approaches are viable, use AskUserQuestion
   - Don't assume implementation details not specified in the ticket

4. **Enter Plan Mode**
   - Use EnterPlanMode to create a detailed implementation plan
   - Include:
     - Overview of the change
     - Files to be created/modified
     - Implementation steps with rationale
     - Testing approach
     - Any risks or considerations

5. **Save the Plan**
   - After exiting plan mode, save the plan to `.claude/plans/{{$1}}.md`
   - Ensure the `.claude/plans/` directory exists (create if needed)
   - Format the plan as markdown with clear sections

6. **Confirm Implementation Approach**
   - Use AskUserQuestion with options:
     - "Implement now" - Continue with implementation in this session
     - "Save plan only" - Save plan and exit (user can run `/implement {{$1}}` later)

7. **Implement the Plan** (if user chose "Implement now")
   - Use TodoWrite to create task list from plan
   - Execute each task (same logic as /implement)
   - Track files changed during implementation
   - Run tests and verify

8. **Update Ticket Context Document**
   - Create context directory if needed: `mkdir -p {context-path}`
   - If new ticket: create document from template:
     ```markdown
     # {{$1}}: {Ticket Title}

     ## Ticket Info
     - **Linear Link**: https://linear.app/team/issue/{{$1}}
     - **Created**: {YYYY-MM-DD}

     ## Sessions
     ```
   - Append new session entry:
     ```markdown
     ### {YYYY-MM-DD HH:MM} - {Brief Session Title}
     **Branch**: `{branch-name}`
     **Repository**: `{repo-name}`

     #### Accomplished
     - {bullet list of completed items}

     #### Key Decisions
     - {decision}: {rationale}

     #### Files Changed
     - `{path}` - {description}

     ---
     ```

9. **Final Summary**
   - Show what was implemented
   - Show context document location: `{context-path}/{{$1}}.md`
   - Remind user: `/create-pr {{$1}}`

### Important Notes

- The plan should be detailed enough for another developer (or future you) to implement
- Include specific file paths and function names where applicable
- Note any assumptions made during planning
- If the ticket references external docs (Notion, Confluence, etc.), fetch and incorporate that context
- Context documents persist across worktrees, enabling continuity when switching branches

{{/if}}

{{else}}
**Error:** No ticket ID provided.

Usage: `/start-task <ticket-id> [--worktree] [extra context]`

Examples:
- Simple mode: `/start-task LIN-123 focus on performance`
- Worktree mode: `/start-task LIN-123 --worktree`
{{/if}}
