---
description: Work on a Linear ticket — auto-detects fresh start vs continuation. Flags: +auto-plan (skip approval gate), +simplify (run refactor step)
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, AskUserQuestion, EnterPlanMode, TodoWrite
argument-hint: [+auto-plan] [+simplify] [extra context]
---

You are helping the user work on a Linear ticket. This command auto-detects whether to start fresh or continue previous work.

### Auto-Plan Mode

{{#if $ARGUMENTS}}
{{!-- Check if +auto-plan flag is present in arguments. Uses + prefix instead of -- to avoid Claude CLI consuming it as a CLI flag --}}
If the text "{{$ARGUMENTS}}" contains `+auto-plan`, then **auto-plan mode is active**. In this mode:
- You still enter plan mode and write a full plan
- But you call `ExitPlanMode` and **immediately proceed to implementation** without waiting for user approval
- Strip `+auto-plan` from the arguments before processing the rest as extra context
{{/if}}

{{#if $ARGUMENTS}}
If the text "{{$ARGUMENTS}}" contains `+simplify`, then **simplify mode is active**. In this mode:
- Step 4 (Simplify sub-agent) runs normally
- Strip `+simplify` from the arguments before processing the rest as extra context
{{/if}}

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

### Step 0.5: Pre-Seed Post-Implementation Todo Items

**Before doing anything else**, use TodoWrite to create the following fixed items. These ensure post-implementation steps are NEVER skipped — they will be visible in the todo list throughout the entire session.

Create these todo items (all with status `pending`):
1. `🔧 Implementation` — placeholder, will be replaced with plan tasks in Step 3
2. `🧹 Simplify: launch sub-agent` — see Step 4
3. `🔍 Pre-review: launch sub-agent` — see Step 5
4. `📋 Handle pre-review suggestions` — see Step 6
5. `💾 Commit: launch sub-agent` — see Step 7
6. `📝 Update ticket context: launch sub-agent` — see Step 8
7. `🚀 Push & PR` — see Step 9
8. `✅ Final summary` — see Step 10

These items act as a persistent checklist. Implementation tasks from the plan will be inserted as sub-items or replace item 1.

### Ticket Context Configuration

Context path: `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}`
Context file: `{context-path}/{TICKET_ID}.md`

### Critical Rules
- **MANDATORY**: You MUST call `EnterPlanMode` before any implementation work. NEVER write or modify code without an approved plan.
- **If auto-plan mode is active**: After writing the plan, call `ExitPlanMode` and immediately proceed to Step 3 (implementation) without waiting for user approval. The plan is still displayed for transparency.
- **If auto-plan mode is NOT active**: After writing the plan, call `ExitPlanMode`. The user will get a permission prompt to review and approve. NEVER auto-proceed to implementation.

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

Do NOT include post-implementation steps in the plan — those are already pre-seeded in the todo list from Step 0.5 and will run automatically after implementation.

After writing the plan, call ExitPlanMode. If **auto-plan mode is active**, proceed directly to Step 3 without waiting for approval. Otherwise, wait for user approval before continuing.

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

Do NOT include post-implementation steps in the plan — those are already pre-seeded in the todo list from Step 0.5 and will run automatically after implementation.

After writing the plan, call ExitPlanMode. If **auto-plan mode is active**, proceed directly to Step 3 without waiting for approval. Otherwise, wait for user approval before continuing.

Then proceed to **Step 3** (shared flow).

### Step 3: Implement the Plan

Use TodoWrite to replace the `🔧 Implementation` placeholder with specific implementation tasks from the plan. Each task should be a separate todo item.

Implement the plan directly — do NOT use a sub-agent. The main agent has full context from the planning phase (codebase exploration, ticket details, clarifying questions) which leads to better implementation.

1. Execute each implementation task sequentially
2. Run tests and verify as you go
3. Use TodoWrite to mark each implementation task as `completed` as you go
4. **Then continue to the post-implementation steps.** Do NOT stop after implementation.

## Post-Implementation Steps

The following steps correspond to the todo items pre-seeded in Step 0.5. Work through them in order — use TodoWrite to mark each item `in_progress` when starting and `completed` when done.

### Step 4: Simplify Sub-Agent

Mark `🧹 Simplify: launch sub-agent` as `in_progress` via TodoWrite.

If **simplify mode is NOT active**: mark `🧹 Simplify: launch sub-agent` as `completed` immediately with note "Skipped (use +simplify to enable)". Skip the rest of this step.

Otherwise, launch a Task sub-agent to review uncommitted changes for code reuse, quality, and efficiency issues — then fix any found.

**Sub-agent prompt:**
> Review the uncommitted changes in the current repo for code reuse, quality, and efficiency issues. Fix the issues you find.
>
> IMPORTANT: Ignore any gitStatus snapshot from the conversation context — it is stale. You MUST run fresh git commands to see the actual current state.
>
> 1. Get the diff: run `git diff` (unstaged) and `git diff --cached` (staged). Review both.
> 2. Read the repo's `CLAUDE.md` at the repo root for conventions.
> 3. Analyze the diff for: code duplication (copy-paste that could be extracted), quality issues (dead code, overly complex logic, unclear naming), and efficiency improvements (unnecessary operations, redundant work).
> 4. Do NOT flag style issues, naming conventions, architecture, security, or test coverage — those are handled by other steps.
> 5. For each finding, apply the fix directly using Edit. Prefer simple, targeted changes over large refactors.
> 6. Return a structured report:
>    - **Fixes applied**: list of changes made (file, line, description). Empty if none.
>    - If nothing found, return: "Simplify passed — no issues found."

**Sub-agent allowed tools:** `Bash(git diff*), Read, Edit, Grep, Glob`

Mark `🧹 Simplify: launch sub-agent` as `completed` via TodoWrite.

### Step 5: Pre-Review Sub-Agent

Mark `🔍 Pre-review: launch sub-agent` as `in_progress` via TodoWrite.

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

Mark `🔍 Pre-review: launch sub-agent` as `completed` via TodoWrite.

### Step 6: Handle Pre-Review Suggestions

Mark `📋 Handle pre-review suggestions` as `in_progress` via TodoWrite.

If the pre-review sub-agent returned suggestions:
1. Display the suggestions report to the user
2. Use AskUserQuestion: "Apply all suggestions / Skip"
3. If **"Apply all"**: apply each suggestion using the Edit tool
4. If **"Skip"**: proceed without changes

If the pre-review returned no suggestions (only auto-fixes or clean pass), proceed silently.

Mark `📋 Handle pre-review suggestions` as `completed` via TodoWrite.

### Step 7: Commit Sub-Agent

Mark `💾 Commit: launch sub-agent` as `in_progress` via TodoWrite.

Launch a **general-purpose** sub-agent (`subagent_type: "general-purpose"`, `model: "sonnet"`) to commit all changes (implementation + any pre-review fixes).

Do NOT use `subagent_type: "git-commit-writer"` — that agent type lacks Bash access and cannot run git commands.

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

Mark `💾 Commit: launch sub-agent` as `completed` via TodoWrite.

### Step 8: Update Ticket Context

Mark `📝 Update ticket context: launch sub-agent` as `in_progress` via TodoWrite.

Use the Task tool with a subagent (`model: "haiku"`) to update the ticket context document. Pass the subagent all session details:
- Ticket ID: `{TICKET_ID}`
- Context file path
- Branch name
- Repository name
- What was accomplished
- Key decisions made
- Files changed

The subagent should append a new session entry following the existing document format.

Mark `📝 Update ticket context: launch sub-agent` as `completed` via TodoWrite.

### Step 9: Push & Create/Update PR

Mark `🚀 Push & PR` as `in_progress` via TodoWrite.

Push the branch and handle PR creation:

1. Push the branch: `git push -u origin <branch-name>`
2. Check if a PR already exists: `gh pr view --json url,number` (exit code 0 = exists)
3. **If no PR exists**: launch a Task sub-agent (`model: "sonnet"`) to create a draft PR.

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

Mark `🚀 Push & PR` as `completed` via TodoWrite.

### Step 10: Final Summary

Mark `✅ Final summary` as `in_progress` via TodoWrite.

Show what was implemented:
```
Work completed: {TICKET_ID}
Phase: Fresh start / Continuation
Change: [brief description of what was done]
Files modified: [count]
Simplify: [N fixes applied] or [clean] or [skipped (use +simplify to enable)]
Pre-review: [N auto-fixes applied, M suggestions] or [clean]
Committed: [yes — commit hash] or [no — reason]
Ticket context updated: yes/no
PR: created #N <url> (draft) / pushed to existing #N <url>
```

Mark `✅ Final summary` as `completed` via TodoWrite.

Suggest next steps:
- `/ds:work-on <next change>` if more work needed

### Important Notes

- The plan should be detailed enough for another developer (or future you) to implement
- Include specific file paths and function names where applicable
- Note any assumptions made during planning
- If the ticket references external docs (Notion, Confluence, etc.), fetch and incorporate that context
- Context documents persist across worktrees, enabling continuity when switching branches
