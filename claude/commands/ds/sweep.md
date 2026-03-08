---
description: Query Linear for eligible tickets and launch parallel /ds:refine sessions in Windows Terminal tabs
allowed-tools: mcp__linear-server__list_issues, mcp__linear-server__list_issue_statuses, mcp__linear-server__list_teams, mcp__linear-server__get_user, AskUserQuestion, Bash
---

You are dispatching parallel `/ds:refine` sessions for Linear tickets that are ready for refinement.

## Your Task

### Step 1. Find Your User ID

Use `mcp__linear-server__get_user` with `id: "me"` to get your Linear user ID.

### Step 2. Find the "Backlog" State ID

Use `mcp__linear-server__list_issue_statuses` to find the state ID for "Backlog" status. You'll need this for the query.

### Step 3. Query Linear for Eligible Tickets

Use `mcp__linear-server__list_issues` with:
- `labelName: "oleksii-ai-flow"`
- `stateId: <backlog-state-id>`
- `assigneeId: <your-user-id>`

### Step 4. Display Results

If **no tickets found**, tell the user:
```
No eligible tickets found.
Criteria: label "oleksii-ai-flow", state "Backlog", assigned to you.
```
And exit.

If tickets are found, display them in a numbered list:
```
Found N ticket(s) ready for sweep:

1. TICKET-ID — Title (Priority: P)
2. TICKET-ID — Title (Priority: P)
...
```

### Step 5. Ask for Confirmation

Use `AskUserQuestion` to ask which tickets to sweep:
- **header**: "Sweep"
- **question**: "Which tickets should I launch /ds:refine sessions for?"
- **multiSelect**: true
- **options**:
  - "All N tickets" — Launch sessions for all found tickets
  - One option per ticket: "TICKET-ID — Title"

If the user cancels or selects none, exit gracefully.

### Step 6. Launch Sessions

Collect the confirmed ticket IDs into a space-separated list.

Run via Bash:
```bash
source ~/.bash.d/sweep-launch.sh && sweep_launch TICKET-1 TICKET-2 ...
```

### Step 7. Report

Display what was launched:
```
Launched N /refine session(s):
- TICKET-ID — Title
- TICKET-ID — Title

Switch tabs with Ctrl+Tab. Each session will run /ds:refine and transition the ticket to "Ready" when done.
```
