---
description: Work on a Linear ticket — auto-detects fresh start vs continuation
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, AskUserQuestion, EnterPlanMode
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

Then proceed to **Step 3** (shared flow).

### Step 3: Save the Plan with Checklist

After exiting plan mode, save the plan to `.claude/plans/{TICKET_ID}.md`:
- Ensure `.claude/plans/` directory exists (create if needed)
- Format as markdown with clear sections
- This overwrites any previous plan for this ticket

**CRITICAL**: Append a `## Checklist` section at the end of the plan file. This is the persistent checklist that survives `/clear` because it lives on disk.

The checklist must contain:
1. One checkbox per implementation task from the plan (derived from the plan steps)
2. The following fixed post-implementation checkboxes (always included, in this order):

```markdown
## Checklist

### Implementation
- [ ] {implementation task 1}
- [ ] {implementation task 2}
- [ ] ...

### Post-Implementation
- [ ] Pre-review: launch sub-agent (Step 5)
- [ ] Handle pre-review suggestions (Step 6)
- [ ] Commit: launch sub-agent (Step 7)
- [ ] Update ticket context: launch sub-agent (Step 8)
- [ ] Push & PR (Step 9)
- [ ] Final summary (Step 10)
```

### Step 4: Implement the Plan (Sub-Agent)

Launch a Task sub-agent to execute the implementation. This keeps the orchestrator context clean for post-implementation steps.

**Sub-agent prompt:**
> Implement the plan in `.claude/plans/{TICKET_ID}.md`.
>
> 1. Read `.claude/plans/{TICKET_ID}.md` to get the full plan and the `### Implementation` checklist
> 2. Execute each implementation task from the checklist sequentially
> 3. After completing each task, mark its checkbox in `.claude/plans/{TICKET_ID}.md`: change `- [ ]` to `- [x]`
> 4. Run tests and verify as you go
> 5. When all implementation tasks are done, return a summary:
>    - **What was accomplished**: brief description of the change
>    - **Key decisions**: any implementation choices made during execution
>    - **Files changed**: list of files created/modified/deleted

**Sub-agent allowed tools:** `Bash, Read, Write, Edit, Grep, Glob, LSP`

After the sub-agent returns:
1. Display the implementation summary to the user
2. **Then continue to the Post-Implementation checklist items.** Do NOT stop after implementation.
3. **After `/clear`**: Read `.claude/plans/{TICKET_ID}.md` to recover the checklist and resume from the first unchecked item.

## Post-Implementation Steps

The following steps correspond to the Post-Implementation checkboxes in `.claude/plans/{TICKET_ID}.md`. Work through them in order — use Edit to mark each checkbox `- [x]` when done. After `/clear`, read the plan file to find where you left off.

### Step 5: Pre-Review Sub-Agent

Launch a Task sub-agent to review uncommitted changes for style, naming, and convention issues.

**Sub-agent prompt:**
> Review the uncommitted changes in the current repo for style, naming, and convention issues.
>
> IMPORTANT: Ignore any gitStatus snapshot from the conversation context — it is stale. You MUST run fresh git commands to see the actual current state.
>
> 1. Get the diff: run `git diff` (unstaged) and `git diff --cached` (staged). Review both.
> 2. Read the repo's `CLAUDE.md` at the repo root for conventions.
> 3. Analyze the diff for: style issues, naming violations, obvious refactorings, convention violations. Do NOT flag architecture, logic, test coverage, performance, or security issues.
> 4. For each finding, classify as `auto-fix` (obvious, safe — apply it directly using Edit) or `suggestion` (requires judgment — report it back).
> 5. Apply all auto-fixes directly. For each auto-fix applied, note the file, line, and what you changed.
> 6. Return a structured report:
>    - **Auto-fixes applied**: list of changes made (file, line, description). Empty if none.
>    - **Suggestions**: list of suggestions for the user to consider (file, line, description, proposed change). Empty if none.
>    - If nothing found, return: "Pre-review passed — no issues found."

**Sub-agent allowed tools:** `Bash(git diff*), Read, Edit, Grep, Glob`

### Step 6: Handle Pre-Review Suggestions

If the pre-review sub-agent returned suggestions:
1. Display the suggestions report to the user
2. Use AskUserQuestion: "Apply all suggestions / Skip"
3. If **"Apply all"**: apply each suggestion using the Edit tool
4. If **"Skip"**: proceed without changes

If the pre-review returned no suggestions (only auto-fixes or clean pass), proceed silently.

### Step 7: Commit Sub-Agent

Launch a Task sub-agent to commit all changes (implementation + any pre-review fixes).

**Sub-agent prompt:**
> Commit the current changes in the repo.
>
> IMPORTANT: Ignore any gitStatus snapshot from the conversation context — it is stale. You MUST run fresh git commands to see the actual current state.
>
> 1. Run `git status` to see all changes
> 2. Run `git diff` and `git diff --cached` to understand what changed
> 3. Run `git log --oneline -5` to see recent commit message style
> 4. Stage all relevant files with `git add <specific files>` (avoid .env, credentials, etc.)
> 5. Generate a conventional commit message that summarizes the implementation work
> 6. Commit using a HEREDOC format:
>    ```bash
>    git commit -m "$(cat <<'EOF'
>    <commit message>
>
>    Co-Authored-By: Claude <noreply@anthropic.com>
>    EOF
>    )"
>    ```
> 7. Run `git status` to verify the commit succeeded
> 8. Do NOT push.

**Sub-agent allowed tools:** `Bash(git *)`

### Step 8: Update Ticket Context

Use the Task tool with a subagent to update the ticket context document. Pass the subagent all session details:
- Ticket ID: `{TICKET_ID}`
- Context file path
- Branch name
- Repository name
- What was accomplished
- Key decisions made
- Files changed

The subagent should append a new session entry following the existing document format.

### Step 9: Push & Create/Update PR

Push the branch and handle PR creation:

1. Push the branch: `git push -u origin <branch-name>`
2. Check if a PR already exists: `gh pr view --json url,number` (exit code 0 = exists)
3. **If no PR exists**: launch a Task sub-agent to create a draft PR.

**Sub-agent prompt:**
> Create a draft PR for the current branch.
>
> 1. Get the ticket ID from the branch name: strip everything before the first `/`, take the first two hyphen-separated segments, uppercase them (e.g., `feature/eng-123-foo` → `ENG-123`)
> 2. Fetch the Linear ticket using `mcp__linear-server__get_issue` with the ticket ID and `includeRelations: true`
> 3. Read the ticket context file at `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET_ID}.md` if it exists
> 4. Run `git log --oneline origin/main..HEAD` and `git diff origin/main...HEAD --stat` to understand all changes
> 5. Create a draft PR using `gh pr create --draft` with:
>    - Title: short summary derived from the ticket title and changes
>    - Body: structured description with sections for Summary, Linear ticket link, and Test plan
>    - Use HEREDOC for the body to preserve formatting
> 6. Return the PR URL and number

**Sub-agent allowed tools:** `Bash(git *), Bash(gh *), mcp__linear-server__get_issue, Read, Glob`

4. **If PR already exists**: just note the PR URL and number from the `gh pr view` output.

Store the result (PR URL and number) for the final summary.

### Step 10: Final Summary

Show what was implemented:
```
Work completed: {TICKET_ID}
Phase: Fresh start / Continuation
Change: [brief description of what was done]
Files modified: [count]
Pre-review: [N auto-fixes applied, M suggestions] or [clean]
Committed: [yes — commit hash] or [no — reason]
Ticket context updated: yes/no
PR: created #N <url> (draft) / pushed to existing #N <url>
```

Suggest next steps:
- `/ds:work-on <next change>` if more work needed

### Important Notes

- The plan should be detailed enough for another developer (or future you) to implement
- Include specific file paths and function names where applicable
- Note any assumptions made during planning
- If the ticket references external docs (Notion, Confluence, etc.), fetch and incorporate that context
- Context documents persist across worktrees, enabling continuity when switching branches
