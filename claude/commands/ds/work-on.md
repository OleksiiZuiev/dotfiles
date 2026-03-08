---
description: Work on a Linear ticket — auto-detects fresh start vs continuation
allowed-tools: Bash, Read, Write, Grep, Glob, Task, AskUserQuestion, EnterPlanMode, TodoWrite
argument-hint: [extra context]
---

You are helping the user work on a Linear ticket. This command auto-detects whether to start fresh or continue previous work.

## Your Task

### Step 0: Extract Ticket ID from Branch Name

Run `git branch --show-current` to get the current branch name.

The branch follows the pattern `{type}/{ticket-id}-{slug}` (e.g., `feature/eng-123-add-user-auth`).
- Strip everything before the first `/`, then take the first two hyphen-separated segments as the ticket ID (e.g., `eng-123`)
- Convert to uppercase for display (e.g., `ENG-123`)

If extraction fails (branch doesn't match pattern), inform the user and exit:
> Could not extract ticket ID from branch name. Expected format: `{type}/{prefix-number}-{slug}` (e.g., `feature/eng-123-add-auth`).

Store the extracted ticket ID as `TICKET_ID` for use throughout.

{{#if $ARGUMENTS}}
Additional context from user: "{{$ARGUMENTS}}"
{{/if}}

### Ticket Context Configuration

Context path: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}`
Context file: `{context-path}/{TICKET_ID}.md`

### Critical Rules
- **MANDATORY**: You MUST call `EnterPlanMode` before any implementation work. NEVER write or modify code without an approved plan.
- **MANDATORY**: After writing the plan, call `ExitPlanMode`. The user will get a permission prompt to review and approve. NEVER auto-proceed to implementation.

### Step 1: Detect Phase

Check two signals to determine whether this is a fresh start or a continuation:

1. **Ticket context file**: Does `{context-path}/{TICKET_ID}.md` exist?
2. **Diff against main**: Run `git diff origin/main --stat` — are there changes on this branch?

**Phase detection logic:**
- **Fresh start** (no context file, OR context file exists but no diff against main): Go to Step 2A
- **Continuation** (context file exists AND diff against main exists): Go to Step 2B

Display the detected phase:
```
Ticket: {TICKET_ID}
Phase: Fresh start / Continuation
Context file: exists / not found
Branch diff: changes found / clean
```

### Step 2A: Fresh Start

#### 2A.1. Load Existing Ticket Context (if exists)

If `{context-path}/{TICKET_ID}.md` exists:
- Read and summarize previous sessions
- Use this context to inform planning (avoid re-exploring solved problems, build on previous decisions)

#### 2A.2. Fetch Linear Ticket Details

Use `mcp__linear-server__get_issue` with ticket ID `{TICKET_ID}` and `includeRelations: true`.

Extract the ticket title, description, comments, and any linked resources.
Look for Notion page links in the description or comments and fetch those automatically.

#### 2A.3. Explore the Codebase

- Use Grep, Glob, and Read tools to understand relevant code areas
- Use the Task tool with subagent_type=Explore for broader context gathering
- Focus on areas mentioned in the ticket or related to the feature/fix

#### 2A.4. Ask Clarifying Questions

If requirements are unclear or multiple approaches are viable, use AskUserQuestion.
Don't assume implementation details not specified in the ticket.

#### 2A.5. Enter Plan Mode

Use EnterPlanMode to create a detailed implementation plan.

Include:
- Overview of the change
- Files to be created/modified
- Implementation steps with rationale
- Testing approach
- Any risks or considerations
- **Final step: Update ticket context document** — the plan MUST end with a step to append a session entry to `{context-path}/{TICKET_ID}.md` following the template from the Ticket Context Configuration. This step will capture what was accomplished, key decisions, and files changed during implementation.

Then proceed to **Step 3** (shared flow).

### Step 2B: Continuation

#### 2B.1. Load Ticket Context (Required)

Read `{context-path}/{TICKET_ID}.md` and summarize previous sessions:
- Number of sessions
- Most recent session: date, branch, what was accomplished
- Key decisions made across sessions

Display the summary so the user can confirm the starting point.

#### 2B.2. Fetch Linear Ticket

Use `mcp__linear-server__get_issue` with ticket ID `{TICKET_ID}` and `includeRelations: true`.

Extract and display:
- Title and current status
- Description (brief excerpt)
- Any new comments since last session
- Related/blocking issues

#### 2B.3. Determine Follow-Up Prompt

{{#if $ARGUMENTS}}
Follow-up change: "{{$ARGUMENTS}}"
{{else}}
No follow-up prompt provided. Use AskUserQuestion to ask: "What would you like to work on next for this ticket?"
{{/if}}

#### 2B.4. Enter Plan Mode

Use EnterPlanMode to plan the follow-up change.

The plan should:
- Build on what was done in previous sessions (don't redo completed work)
- Reference specific decisions from ticket context
- Include the specific follow-up change
- Include files to be created/modified
- Include testing approach
- **Final step: Update ticket context document** — the plan MUST end with a step to append a new session entry to `{context-path}/{TICKET_ID}.md` following the existing document's format

Then proceed to **Step 3** (shared flow).

### Step 3: Save the Plan

After exiting plan mode, save the plan to `.claude/plans/{TICKET_ID}.md`:
- Ensure `.claude/plans/` directory exists (create if needed)
- Format as markdown with clear sections
- This overwrites any previous plan for this ticket

### Step 4: Implement the Plan

- Use TodoWrite to create task list from plan
- Execute each task sequentially
- Track files changed during implementation
- Run tests and verify
- After implementation, prepare a brief summary: what was accomplished, key decisions, files changed

### Step 5: Update Ticket Context

Use the Task tool with a subagent to update the ticket context document. Pass the subagent all session details:
- Ticket ID: `{TICKET_ID}`
- Context file path
- Branch name
- Repository name
- What was accomplished
- Key decisions made
- Files changed

The subagent should append a new session entry following the existing document format.

### Step 6: Final Summary

Show what was implemented:
```
Work completed: {TICKET_ID}
Phase: Fresh start / Continuation
Change: [brief description of what was done]
Files modified: [count]
Ticket context updated: yes/no
```

Suggest next steps:
- `/ds:create-pr` if ready for review
- `/ds:work-on <next change>` if more work needed
- `/ds:pre-review` to catch style issues before human review

### Important Notes

- The plan should be detailed enough for another developer (or future you) to implement
- Include specific file paths and function names where applicable
- Note any assumptions made during planning
- If the ticket references external docs (Notion, Confluence, etc.), fetch and incorporate that context
- Context documents persist across worktrees, enabling continuity when switching branches
