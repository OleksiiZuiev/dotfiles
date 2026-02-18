---
description: Create PR for ticket
allowed-tools: Bash(git *), Bash(gh *), mcp__linear-server__get_issue
argument-hint: [--ready]
---

You are creating a pull request for an implemented ticket.

## Your Task

### Steps to Follow

1. **Extract Ticket ID from Branch Name**
   - Run `git branch --show-current` to get the current branch name
   - The branch follows the pattern `{type}/{ticket-id}-{slug}` (e.g., `feature/eng-123-add-user-auth`)
   - Strip everything before the first `/`, then take the first two hyphen-separated segments as the ticket ID (e.g., `eng-123`)
   - Convert to uppercase for display (e.g., `ENG-123`)
   - If extraction fails (branch doesn't match pattern), inform the user and exit:
     > Could not extract ticket ID from branch name. Expected format: `{type}/{prefix-number}-{slug}` (e.g., `feature/eng-123-add-auth`).

2. **Load Context**
   - Fetch ticket details from Linear using `mcp__linear-server__get_issue` with the extracted ticket ID — use the ticket title and description for the PR summary
   - Check for ticket context file at `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET-ID}.md`
   - If the context file exists, read it to gather:
     - **Accomplishments** from session history — these become the PR summary
     - **Key decisions** — worth mentioning in the PR description
     - **Files changed** — useful for the verification section
   - Combine Linear ticket context + ticket context document for the most informative PR description

3. **Verify Git State**
   - Run `git status` to ensure changes are committed
   - If there are uncommitted changes, inform the user to commit them first
   - Check if current branch tracks a remote branch

4. **Analyze Commits**
   - Run `git log origin/main..HEAD --oneline` (or appropriate base branch)
   - Understand what was changed across all commits
   - This informs the PR description

5. **Create Concise PR Description**
   - Title: `[TICKET-ID] <brief summary from ticket>`
   - Body should include:
     - High-level summary (2-3 sentences)
     - Link to Linear ticket: `Closes TICKET-ID`
     - Brief test plan or verification steps
   - Keep it focused and scannable

6. **Push and Create PR**
   - Push branch to remote with `-u` flag if needed: `git push -u origin <branch>`
   - Create PR using `gh` CLI with HEREDOC format:
     ```bash
     gh pr create --title "[TICKET-ID] <title>" --draft --body "$(cat <<'EOF'
     ## Summary
     <2-3 sentences>

     ## Verification
     <bullet points>

     Closes TICKET-ID
     EOF
     )"
     ```
{{#if (contains $ARGUMENTS "--ready")}}
   - **Note:** User passed `--ready` — omit the `--draft` flag to create a ready-for-review PR
{{/if}}

7. **Output Results**
   - Display the PR URL
   - Show the PR number clearly
   - Remind user: `Use /polish-pr to address review comments`

### Important Notes

- The PR description should be concise and user-facing
- Ensure all commits are pushed before creating the PR
- If `gh` CLI is not authenticated, guide the user to run `gh auth login`
{{#if (contains $ARGUMENTS "--ready")}}
- Creating as **ready-for-review** PR (user passed `--ready`)
{{else}}
- Creating as **draft** PR (default). Pass `--ready` to create a ready-for-review PR instead
{{/if}}
