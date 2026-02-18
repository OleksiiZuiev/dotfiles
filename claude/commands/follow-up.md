---
description: Continue work on a Linear ticket with a specific follow-up change
allowed-tools: Bash, Read, Write, Grep, Glob, Task, AskUserQuestion, EnterPlanMode, ExitPlanMode, TodoWrite
argument-hint: <ticket-id> <prompt>
---

You are helping the user continue work on an existing ticket. Unlike `/start-task` (which starts fresh), this command assumes previous sessions exist and builds on them.

## Your Task

{{#if $1}}

Continue work on Linear ticket: **{{$1}}**

{{#if $ARGUMENTS}}
Follow-up change: "{{$ARGUMENTS}}"
{{/if}}

### Ticket Context Configuration

Context path: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}`
Context file: `{context-path}/{{$1}}.md`

### Steps to Follow

#### 1. Validate Arguments

You need both a ticket ID and a description of what to do next.

- Ticket ID: `{{$1}}`
- Full arguments: `{{$ARGUMENTS}}`

If the arguments contain only the ticket ID and nothing else (no follow-up prompt), show an error:
```
Error: No follow-up prompt provided.

Usage: /follow-up <ticket-id> <prompt describing what to do next>

Examples:
- /follow-up ENG-123 add error handling for the edge case from PR review
- /follow-up ENG-123 implement the remaining acceptance criteria
- /follow-up ENG-123 fix the failing tests from CI
```

#### 2. Load Ticket Context (Required)

- Read `{context-path}/{{$1}}.md`
- If the file does NOT exist, show a warning and suggest `/start-task`:
  ```
  Warning: No previous sessions found for {{$1}}.
  This command is for continuing existing work. To start fresh, use:
    /start-task {{$1}}
  ```
  Then use AskUserQuestion:
  - "No ticket context found. How would you like to proceed?"
  - Option 1: "Continue anyway" — proceed without prior context
  - Option 2: "Use /start-task instead" — exit gracefully
  If user chooses "Use /start-task instead", stop here.

- If the file exists, summarize previous sessions:
  - Number of sessions
  - Most recent session: date, branch, what was accomplished
  - Key decisions made across sessions

Display the summary so the user can confirm the starting point.

#### 3. Fetch Linear Ticket

Use `mcp__linear-server__get_issue` with ticket ID `{{$1}}` and `includeRelations: true`.

Extract and display:
- Title and current status
- Description (brief excerpt)
- Any new comments since last session
- Related/blocking issues

#### 4. Enter Plan Mode

Use EnterPlanMode to plan the follow-up change described in the arguments.

The plan should:
- Build on what was done in previous sessions (don't redo completed work)
- Reference specific decisions from ticket context
- Include the specific follow-up change from the user's prompt
- Include files to be created/modified
- Include testing approach
- **Final step: Update ticket context document** — the plan MUST end with a step to append a new session entry to `{context-path}/{{$1}}.md` following the existing document's format

#### 5. Save the Plan

After exiting plan mode, save the plan to `.claude/plans/{{$1}}.md`:
- Ensure `.claude/plans/` directory exists (create if needed)
- Format as markdown with clear sections
- This overwrites any previous plan for this ticket

#### 6. Confirm Implementation Approach

Use AskUserQuestion:
- "Ready to implement the follow-up change?"
- Option 1: "Implement now" — continue with implementation
- Option 2: "Save plan only" — save and exit

#### 7. Implement the Plan (if user chose "Implement now")

- Use TodoWrite to create task list from plan
- Execute each task sequentially
- Track files changed during implementation
- Run tests and verify
- After implementation, prepare a brief summary: what was accomplished, key decisions, files changed

#### 8. Update Ticket Context

Use the Task tool with a subagent to update the ticket context document. Pass the subagent all session details:
- Ticket ID: `{{$1}}`
- Context file path
- Branch name
- Repository name
- What was accomplished
- Key decisions made
- Files changed

The subagent should append a new session entry following the existing document format.

#### 9. Final Summary

Show what was done:
```
Follow-up completed: {{$1}}
Change: [brief description of what was done]
Files modified: [count]
Ticket context updated: yes/no
```

Suggest next steps:
- `/create-pr {{$1}}` if ready for review
- `/follow-up {{$1}} <next change>` if more work needed
- `/polish-pr` if PR already exists and needs updates

{{else}}
**Error:** No ticket ID provided.

Usage: `/follow-up <ticket-id> <prompt describing what to do next>`

Examples:
- `/follow-up ENG-123 add error handling for the edge case from PR review`
- `/follow-up ENG-123 implement the remaining acceptance criteria`
- `/follow-up ENG-123 fix the failing tests from CI`
{{/if}}
