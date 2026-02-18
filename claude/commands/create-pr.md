---
description: Create PR for ticket
allowed-tools: Bash(git *), Bash(gh *)
argument-hint: <ticket-id> [--draft]
---

You are creating a pull request for an implemented ticket.

## Your Task

{{#if $1}}
Create a pull request for ticket: **{{$1}}**
{{#if $2}}{{#if (eq $2 "--draft")}}
**Mode:** Creating as Draft PR
{{/if}}{{/if}}

### Steps to Follow

1. **Verify Git State**
   - Run `git status` to ensure changes are committed
   - If there are uncommitted changes, inform the user to commit them first
   - Check if current branch tracks a remote branch

2. **Analyze Commits**
   - Run `git log origin/main..HEAD --oneline` (or appropriate base branch)
   - Understand what was changed across all commits
   - This informs the PR description

3. **Create Concise PR Description**
   - Title: `[{{$1}}] <brief summary from ticket>`
   - Body should include:
     - High-level summary (2-3 sentences)
     - Link to Linear ticket: `Closes {{$1}}`
     - Brief test plan or verification steps
   - Keep it focused and scannable

4. **Push and Create PR**
   - Push branch to remote with `-u` flag if needed: `git push -u origin <branch>`
   - Create PR using `gh` CLI with HEREDOC format:
     ```bash
     gh pr create --title "[{{$1}}] <title>" {{#if $2}}{{#if (eq $2 "--draft")}}--draft {{/if}}{{/if}}--body "$(cat <<'EOF'
     ## Summary
     <2-3 sentences>

     ## Verification
     <bullet points>

     Closes {{$1}}
     EOF
     )"
     ```

5. **Output Results**
   - Display the PR URL
   - Show the PR number clearly
   - Remind user: `Use /polish-pr <pr-number> to address review comments`

### Important Notes

- The PR description should be concise and user-facing
- Ensure all commits are pushed before creating the PR
- If `gh` CLI is not authenticated, guide the user to run `gh auth login`

{{else}}
**Error:** No ticket ID provided.

Usage: `/create-pr <ticket-id> [--draft]`

Examples:
- `/create-pr LIN-123` - Create a regular PR
- `/create-pr LIN-123 --draft` - Create a draft PR
{{/if}}
