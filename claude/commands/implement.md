---
description: Execute the implementation plan for a ticket
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, TodoWrite, AskUserQuestion
argument-hint: <ticket-id>
---

You are implementing the plan that was created for a specific ticket.

## Current Context

Working directory: !`pwd`
Current branch: !`git branch --show-current 2>/dev/null || echo "not in git repo"`

## Your Task

{{#if $1}}
Implement the plan for ticket: **{{$1}}**

### Steps to Follow

1. **Read the Plan**
   - Read the plan file from `.claude/plans/{{$1}}.md`
   - If the file doesn't exist, inform the user they need to run `/start-task {{$1}}` first
   - Understand all steps, requirements, and considerations

2. **Create Todo List**
   - Use TodoWrite to break down the plan into trackable tasks
   - Create specific, actionable items for each step
   - Ensure tasks are granular enough to show progress

3. **Implement Each Task**
   - Work through tasks sequentially
   - Mark each task as in_progress before starting, completed after finishing
   - Use Read, Write, Edit, Grep, Glob tools for code changes
   - Run bash commands for builds, tests, or other operations as needed
   - **Only mark a task completed when it's fully done** - if you hit errors or blockers, keep it in_progress

4. **Test and Verify**
   - Run tests as specified in the plan
   - Verify the implementation works as expected
   - If tests fail, fix issues before marking tasks complete

5. **Document Deviations**
   - If you deviate from the plan or make important decisions:
     - Note them in comments or commit messages
     - Consider updating the plan file with an "Implementation Notes" section
   - Use the Edit tool to append notes to `.claude/plans/{{$1}}.md` if significant changes occur

6. **Final Status**
   - Confirm all tasks are completed
   - Summarize what was implemented
   - Note any known issues or follow-up work needed
   - Remind user about next steps: `/create-pr {{$1}}`

### Important Guidelines

- **Follow TDD when possible**: Write test first, verify it fails, implement code, verify it passes
- **Keep it simple**: Don't over-engineer or add features not in the plan
- **Add comments only when needed**: Prefer expressive code to comments
- **Ask before expanding scope**: If you think something extra is needed, ask first
- **Be honest**: Flag issues immediately, don't hide problems

{{else}}
**Error:** No ticket ID provided.

Usage: `/implement <ticket-id>`

Example: `/implement LIN-123`
{{/if}}
