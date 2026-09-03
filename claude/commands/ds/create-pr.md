---
description: Create PR for ticket — stacked on its parent branch when the current branch is stacked
allowed-tools: Bash, mcp__claude_ai_Linear__get_issue
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
   - Fetch ticket details from Linear using `mcp__claude_ai_Linear__get_issue` with the extracted ticket ID
     - Extract the **ticket title** and **description** (this is the goal/motivation)
     - Extract the **ticket URL** for linking in the PR body (falls back to `https://linear.app/issue/{TICKET-ID}` if not available)
   - Check for ticket context file at `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET-ID}.md`
   - If the context file exists, read it to gather:
     - **Accomplishments** from session history — these become the PR summary
     - **Key decisions** — include in PR description if any exist
   - Combine Linear ticket context + ticket context document for the most informative PR description

3. **Verify Git State**
   - Run `git status` to ensure changes are committed
   - If there are uncommitted changes, inform the user to commit them first
   - Check if current branch tracks a remote branch

4. **Analyze Commits**
   - Run `git log origin/main..HEAD --oneline` (or appropriate base branch)
   - Understand what was changed across all commits
   - This informs the PR description

5. **Detect the Base Branch**
   - Run `stack-parent` (a `bash.d` helper; `stack-parent --help` states the rule). It prints
     `<parent-branch> <pr-number>` when the branch is stacked on another feature branch,
     `<parent-branch> -` when that parent has no open PR, and nothing (exit 1) when the branch is
     based on main.
   - **Nothing** → `BASE_BRANCH=main`; this is an ordinary PR
   - **`<parent> <num>`** → `BASE_BRANCH=<parent>`, `PARENT_PR_NUM=<num>`; this is a stacked PR
   - **`<parent> -`** → warn: "Parent branch `<parent>` has no open PR — create one first, then
     re-run to link the stack." Target `--base <parent>` anyway (basing on main would drag the
     parent's commits into your diff), but skip the linking and the stacked-PR notice

6. **Create PR Description**
   - Title: `[TICKET-ID] <brief summary from ticket>`
   - Body structure:
     - **Stacked-PR notice** (stacked PRs only — first line of the body):
       `> ⚡ Stacked on #PARENT_PR_NUM (\`<parent>\`) — will retarget to main when that branch merges.`
     - **Goal**: the motivation/why from the Linear ticket description (keep concise — 1-3 sentences)
     - **Summary**: what was accomplished (from commits + ticket context accomplishments)
     - **Key Decisions** (optional): from ticket context key decisions, only if any exist — omit this section entirely if there are none
     - Linear ticket link at the bottom: `[TICKET-ID](<linear-url>)`
   - Keep it focused and scannable

7. **Push and Create PR**
   - Push branch to remote with `-u` flag if needed: `git push -u origin <branch>`
   - Create PR using `gh` CLI with HEREDOC format:
     ```bash
     gh pr create --title "[TICKET-ID] <title>" --draft --body "$(cat <<'EOF'
     ## Goal
     <motivation from Linear ticket description>

     ## Summary
     <what was accomplished>

     ## Key Decisions
     - <decision>: <rationale>

     [TICKET-ID](<linear-url>)
     EOF
     )"
     ```
   - Omit the `## Key Decisions` section entirely if no decisions were captured
   - For a **stacked PR**, add `--base "$BASE_BRANCH"` to the `gh pr create` call, then register the
     stack with GitHub's native stacked-PR system:
     ```bash
     GH_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" gh stack link "$BASE_BRANCH" "$(git branch --show-current)"
     ```
     Install the extension first if missing: `gh extension list | grep -q gh-stack || gh extension install github/gh-stack`.
     `GH_REPO` is required, not decorative: the extension parses `origin` itself and rejects an SSH
     host alias (`git@github-work:owner/repo.git`) that `gh` core resolves fine, dying with "none of
     the git remotes … point to a known GitHub host". Linking also pushes every branch in the stack
     to `origin`, which is why it runs after the push above. Create the PR before linking — left to
     itself `gh stack link` opens it with its own generated title and not as a draft.
     **A link failure is not fatal**: the PR exists and already targets the right base; report the
     error and carry on.
{{#if (contains $ARGUMENTS "--ready")}}
   - **Note:** User passed `--ready` — omit the `--draft` flag to create a ready-for-review PR
{{/if}}

8. **Output Results**
   - Display the PR URL
   - Show the PR number clearly
   - For a stacked PR, show the base branch and the `gh stack link` result (or the error, if linking failed)
   - Remind user: `Use /ds:polish-pr to address review comments`

### Important Notes

- The PR description should be concise and user-facing
- Ensure all commits are pushed before creating the PR
- If `gh` CLI is not authenticated, guide the user to run `gh auth login`
{{#if (contains $ARGUMENTS "--ready")}}
- Creating as **ready-for-review** PR (user passed `--ready`)
{{else}}
- Creating as **draft** PR (default). Pass `--ready` to create a ready-for-review PR instead
{{/if}}
