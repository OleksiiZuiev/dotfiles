---
description: Gather context from Linear ticket and build implementation plan
allowed-tools: Bash, Read, Write, Grep, Glob, Task, AskUserQuestion, EnterPlanMode, ExitPlanMode, TodoWrite
argument-hint: <ticket-id> [extra context]
---

You are helping the user start work on a new task by gathering context and creating an implementation plan.

## Your Task

{{#if $1}}

Create an implementation plan for Linear ticket: **{{$1}}**

{{#if $ARGUMENTS}}
Additional context from user: "{{$ARGUMENTS}}"
{{/if}}

### Ticket Context Configuration

Context path: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}`
Context file: `{context-path}/{{$1}}.md`

### Steps to Follow

1. **Load Existing Ticket Context (if exists)**
   - Check if `{context-path}/{{$1}}.md` exists
   - If yes, read and summarize previous sessions
   - Use this context to inform planning (avoid re-exploring solved problems, build on previous decisions)
   - Note: This helps maintain continuity across worktrees and sessions

2. **Fetch Linear Ticket Details**
   - Use `mcp__linear-server__get_issue` with ticket ID `{{$1}}` and `includeRelations: true`
   - Extract the ticket title, description, comments, and any linked resources
   - Look for Notion page links in the description or comments and fetch those automatically

3. **Explore the Codebase**
   - Use Grep, Glob, and Read tools to understand relevant code areas
   - Use the Task tool with subagent_type=Explore for broader context gathering
   - Focus on areas mentioned in the ticket or related to the feature/fix

4. **Ask Clarifying Questions**
   - If requirements are unclear or multiple approaches are viable, use AskUserQuestion
   - Don't assume implementation details not specified in the ticket

5. **Enter Plan Mode**
   - Use EnterPlanMode to create a detailed implementation plan
   - Include:
     - Overview of the change
     - Files to be created/modified
     - Implementation steps with rationale
     - Testing approach
     - Any risks or considerations
     - **Final step: Update ticket context document** — the plan MUST end with a step to append a session entry to `{context-path}/{{$1}}.md` following the template from step 1. This step will capture what was accomplished, key decisions, and files changed during implementation.

6. **Save the Plan**
   - After exiting plan mode, save the plan to `.claude/plans/{{$1}}.md`
   - Ensure the `.claude/plans/` directory exists (create if needed)
   - Format the plan as markdown with clear sections

7. **Confirm Implementation Approach**
   - Use AskUserQuestion with options:
     - "Implement now" - Continue with implementation in this session
     - "Save plan only" - Save plan and exit (user can run `/follow-up {{$1}}` later to continue)

8. **Implement the Plan** (if user chose "Implement now")
   - Use TodoWrite to create task list from plan
   - Execute each task sequentially
   - Track files changed during implementation
   - Run tests and verify
   - After implementation, prepare a brief summary: what was accomplished, key decisions, files changed

9. **Final Summary**
    - Show what was implemented (or "Plan saved" if user chose save only)
    - Confirm ticket context was updated
    - Remind user: `/create-pr {{$1}}` (if implemented) or `/follow-up {{$1}} <next change>` to continue (if saved only)

### Important Notes

- The plan should be detailed enough for another developer (or future you) to implement
- Include specific file paths and function names where applicable
- Note any assumptions made during planning
- If the ticket references external docs (Notion, Confluence, etc.), fetch and incorporate that context
- Context documents persist across worktrees, enabling continuity when switching branches

{{else}}
**Error:** No ticket ID provided.

Usage: `/start-task <ticket-id> [extra context]`

Example: `/start-task LIN-123 focus on performance`
{{/if}}
