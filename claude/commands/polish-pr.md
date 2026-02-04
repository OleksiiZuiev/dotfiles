---
description: Address review comments on a PR
allowed-tools: Bash(git *), Bash(gh *), Read, Write, Edit, Grep, Glob, TodoWrite
argument-hint: [<pr-number>]
---

You are addressing review comments on a pull request by implementing fixes, committing them, replying to comments, and resolving conversations.

## Current Context

Working directory: !`pwd`
Current branch: !`git branch --show-current 2>/dev/null || echo "not in git repo"`

## Your Task

{{#if $1}}
Address review comments for PR: **#{{$1}}**

### Steps to Follow

1. **Fetch PR Review Comments**
   - Use `gh pr view {{$1}} --json comments,reviews` to get all comments and reviews
   - Parse the JSON to identify unresolved review comments
   - Use `gh api repos/{owner}/{repo}/pulls/{{$1}}/comments` for detailed review comments if needed
   - **IMPORTANT**: Fetch review threads with thread IDs (required for replying via GraphQL):
     ```bash
     gh api graphql -f query='
     query {
       repository(owner: "{owner}", name: "{repo}") {
         pullRequest(number: {{$1}}) {
           reviewThreads(first: 100) {
             nodes {
               id
               isResolved
               comments(first: 10) {
                 nodes {
                   id
                   databaseId
                   body
                   author { login }
                   path
                   line
                 }
               }
             }
           }
         }
       }
     }'
     ```
   - Filter for comments that need action (not resolved, not outdated)

2. **Display Comments Summary**
   - Show the total number of unresolved comments
   - Group comments by file/location for better context
   - Prepare to process each comment one-by-one

3. **Plan Phase - For Each Unresolved Comment (One-by-One):**

   **IMPORTANT**: Process comments ONE AT A TIME. For each comment:

   a. **Display Comment Context**
      - Show file path and line number
      - Show the code snippet being reviewed
      - Show the reviewer's comment
      - Show surrounding code for context (if helpful)

   b. **Analyze and Propose Fix**
      - Analyze the reviewer's concern
      - Propose a specific fix with explanation
      - Explain what changes will be made and why

   c. **Get User Approval**
      - Use `AskUserQuestion` to present options:
        - **"Approve fix"** - Proceed with this specific fix
        - **"Approve all similar"** - If pattern detected, batch similar fixes
        - **"Modify approach"** - User wants to change the proposed fix
        - **"Skip this comment"** - Don't address this comment now
      - Wait for user decision before proceeding to next comment
      - Record approved fixes for implementation phase

   d. **Handle Skipped Comments**
      - If user selected "Skip this comment", ask for the rationale using `AskUserQuestion`:
        - **"Not applicable"** - The comment doesn't apply to current code
        - **"Will address later"** - Plan to address in a future PR
        - **"Disagree with suggestion"** - Have a different approach in mind
        - **"Custom explanation"** - Provide custom rationale
      - Record the skipped comment and rationale for the reply phase

   e. **Create Todo List**
      - After ALL comments are planned and approved, use TodoWrite
      - Format: "Address comment by @reviewer: <brief summary>"
      - Only include approved fixes in the todo list

4. **Implementation Phase - For Each Approved Fix:**

   a. **Implement the Fix**
      - Read the relevant code files
      - Make the requested changes using Edit or Write tools
      - Ensure the fix addresses the reviewer's concern
      - Test if applicable

   b. **Commit the Change**
      - Use descriptive commit message referencing the review:
        ```bash
        git add <files>
        git commit -m "$(cat <<'EOF'
        Address review: <brief description>

        - <what was changed>
        - Resolves comment by @reviewer

        Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
        EOF
        )"
        ```

   c. **Reply to the Comment**
      - Get the **thread ID** (not comment ID) from the earlier GraphQL fetch
      - Post a threaded reply using GraphQL mutation with Claude attribution:
        ```bash
        gh api graphql -f query='
        mutation {
          addPullRequestReviewThreadReply(input: {
            pullRequestReviewThreadId: "<thread_id>"
            body: "Fixed in <commit-sha>.\n\n<description of change>\n\n🤖 Generated with [Claude Code](https://claude.ai/claude-code)"
          }) {
            comment {
              id
              body
            }
          }
        }'
        ```
      - **Note**: Use thread ID (format: `PRRT_*`), NOT comment ID (format: `PRRC_*`)

   d. **Reply to Skipped Comments**
      - For each skipped comment, post a threaded reply explaining it won't be addressed:
        ```bash
        gh api graphql -f query='
        mutation {
          addPullRequestReviewThreadReply(input: {
            pullRequestReviewThreadId: "<thread_id>"
            body: "Won'\''t address in this PR.\n\n**Reason:** <rationale from user>\n\n🤖 Generated with [Claude Code](https://claude.ai/claude-code)"
          }) {
            comment {
              id
              body
            }
          }
        }'
        ```

   e. **Mark Todo Complete**
      - Update TodoWrite to mark this comment as completed

5. **Push All Changes**
   - After all comments are addressed:
     ```bash
     git push
     ```
   - This updates the PR with all fix commits

6. **Final Summary**
   - List all comments that were addressed
   - Show commit SHAs for each fix
   - List any comments that were skipped (with replies posted explaining the rationale)
   - Remind user to manually resolve conversations after reviewing the changes

### Important Notes

- **Two-Phase Approach**: ALWAYS complete the Plan Phase (get approval for ALL comments) before starting Implementation Phase
- **One-by-One Planning**: Process each comment individually during planning, getting user approval before moving to the next
- **Batch Approval**: When similar issues are detected (e.g., same type of fix across multiple files), offer "Approve all similar" option
- **No Auto-Implementation**: NEVER implement fixes without explicit user approval via AskUserQuestion
- **Thread IDs vs Comment IDs**: When replying to review comments, you must use the **thread ID** (format: `PRRT_*`), NOT the comment ID (format: `PRRC_*`). The REST API `/pulls/comments/{id}/replies` endpoint returns 404 - use GraphQL `addPullRequestReviewThreadReply` mutation instead.
- Make each fix a separate commit with a clear message
- **Always include attribution**: Every GitHub reply must include the Claude Code attribution line
- **Skipped Comments**: When a user chooses to skip a comment, always ask for rationale and post a reply explaining why it won't be addressed
- **Manual Resolution**: Conversations are NOT auto-resolved - humans will resolve them manually after reviewing the changes
- If a review comment is unclear, ask the user for clarification during the planning phase
- Use `gh api` for detailed operations not covered by `gh pr` commands
- Test critical changes before committing

### GitHub CLI Commands Reference

- View PR: `gh pr view <pr-number> --json comments,reviews`
- Get detailed review comments: `gh api repos/{owner}/{repo}/pulls/<pr-number>/comments`
- Fetch review threads (with thread IDs for replying):
  ```bash
  gh api graphql -f query='query { repository(owner: "{owner}", name: "{repo}") { pullRequest(number: {pr_number}) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 10) { nodes { id databaseId body author { login } path line } } } } } } }'
  ```
- Reply to comment (uses thread ID, not comment ID):
  ```bash
  gh api graphql -f query='mutation { addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: "<thread_id>" body: "..." }) { comment { id body } } }'
  ```
- Get repo info: `gh repo view --json owner,name`

{{else}}
**Auto-detecting PR from current branch...**

### Step 0: Detect PR Number

Run the following command to get the PR for the current branch:
```bash
gh pr view --json number --jq '.number'
```

- **If successful**: Use the returned number as the PR to polish, then proceed to Step 1 below
- **If failed** (no PR for current branch): Inform user with helpful guidance:
  - "No PR found for branch `<branch-name>`"
  - Suggestions:
    - Run `gh pr create` to create a PR first
    - Or specify PR number directly: `/polish-pr <pr-number>`

### Steps to Follow (after PR detected)

1. **Fetch PR Review Comments**
   - Use `gh pr view <pr-number> --json comments,reviews` to get all comments and reviews
   - Parse the JSON to identify unresolved review comments
   - Use `gh api repos/{owner}/{repo}/pulls/<pr-number>/comments` for detailed review comments if needed
   - **IMPORTANT**: Fetch review threads with thread IDs (required for replying via GraphQL):
     ```bash
     gh api graphql -f query='
     query {
       repository(owner: "{owner}", name: "{repo}") {
         pullRequest(number: <pr-number>) {
           reviewThreads(first: 100) {
             nodes {
               id
               isResolved
               comments(first: 10) {
                 nodes {
                   id
                   databaseId
                   body
                   author { login }
                   path
                   line
                 }
               }
             }
           }
         }
       }
     }'
     ```
   - Filter for comments that need action (not resolved, not outdated)

2. **Display Comments Summary**
   - Show the total number of unresolved comments
   - Group comments by file/location for better context
   - Prepare to process each comment one-by-one

3. **Plan Phase - For Each Unresolved Comment (One-by-One):**

   **IMPORTANT**: Process comments ONE AT A TIME. For each comment:

   a. **Display Comment Context**
      - Show file path and line number
      - Show the code snippet being reviewed
      - Show the reviewer's comment
      - Show surrounding code for context (if helpful)

   b. **Analyze and Propose Fix**
      - Analyze the reviewer's concern
      - Propose a specific fix with explanation
      - Explain what changes will be made and why

   c. **Get User Approval**
      - Use `AskUserQuestion` to present options:
        - **"Approve fix"** - Proceed with this specific fix
        - **"Approve all similar"** - If pattern detected, batch similar fixes
        - **"Modify approach"** - User wants to change the proposed fix
        - **"Skip this comment"** - Don't address this comment now
      - Wait for user decision before proceeding to next comment
      - Record approved fixes for implementation phase

   d. **Handle Skipped Comments**
      - If user selected "Skip this comment", ask for the rationale using `AskUserQuestion`:
        - **"Not applicable"** - The comment doesn't apply to current code
        - **"Will address later"** - Plan to address in a future PR
        - **"Disagree with suggestion"** - Have a different approach in mind
        - **"Custom explanation"** - Provide custom rationale
      - Record the skipped comment and rationale for the reply phase

   e. **Create Todo List**
      - After ALL comments are planned and approved, use TodoWrite
      - Format: "Address comment by @reviewer: <brief summary>"
      - Only include approved fixes in the todo list

4. **Implementation Phase - For Each Approved Fix:**

   a. **Implement the Fix**
      - Read the relevant code files
      - Make the requested changes using Edit or Write tools
      - Ensure the fix addresses the reviewer's concern
      - Test if applicable

   b. **Commit the Change**
      - Use descriptive commit message referencing the review:
        ```bash
        git add <files>
        git commit -m "$(cat <<'EOF'
        Address review: <brief description>

        - <what was changed>
        - Resolves comment by @reviewer

        Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
        EOF
        )"
        ```

   c. **Reply to the Comment**
      - Get the **thread ID** (not comment ID) from the earlier GraphQL fetch
      - Post a threaded reply using GraphQL mutation with Claude attribution:
        ```bash
        gh api graphql -f query='
        mutation {
          addPullRequestReviewThreadReply(input: {
            pullRequestReviewThreadId: "<thread_id>"
            body: "Fixed in <commit-sha>.\n\n<description of change>\n\n🤖 Generated with [Claude Code](https://claude.ai/claude-code)"
          }) {
            comment {
              id
              body
            }
          }
        }'
        ```
      - **Note**: Use thread ID (format: `PRRT_*`), NOT comment ID (format: `PRRC_*`)

   d. **Reply to Skipped Comments**
      - For each skipped comment, post a threaded reply explaining it won't be addressed:
        ```bash
        gh api graphql -f query='
        mutation {
          addPullRequestReviewThreadReply(input: {
            pullRequestReviewThreadId: "<thread_id>"
            body: "Won'\''t address in this PR.\n\n**Reason:** <rationale from user>\n\n🤖 Generated with [Claude Code](https://claude.ai/claude-code)"
          }) {
            comment {
              id
              body
            }
          }
        }'
        ```

   e. **Mark Todo Complete**
      - Update TodoWrite to mark this comment as completed

5. **Push All Changes**
   - After all comments are addressed:
     ```bash
     git push
     ```
   - This updates the PR with all fix commits

6. **Final Summary**
   - List all comments that were addressed
   - Show commit SHAs for each fix
   - List any comments that were skipped (with replies posted explaining the rationale)
   - Remind user to manually resolve conversations after reviewing the changes

### Important Notes

- **Two-Phase Approach**: ALWAYS complete the Plan Phase (get approval for ALL comments) before starting Implementation Phase
- **One-by-One Planning**: Process each comment individually during planning, getting user approval before moving to the next
- **Batch Approval**: When similar issues are detected (e.g., same type of fix across multiple files), offer "Approve all similar" option
- **No Auto-Implementation**: NEVER implement fixes without explicit user approval via AskUserQuestion
- **Thread IDs vs Comment IDs**: When replying to review comments, you must use the **thread ID** (format: `PRRT_*`), NOT the comment ID (format: `PRRC_*`). The REST API `/pulls/comments/{id}/replies` endpoint returns 404 - use GraphQL `addPullRequestReviewThreadReply` mutation instead.
- Make each fix a separate commit with a clear message
- **Always include attribution**: Every GitHub reply must include the Claude Code attribution line
- **Skipped Comments**: When a user chooses to skip a comment, always ask for rationale and post a reply explaining why it won't be addressed
- **Manual Resolution**: Conversations are NOT auto-resolved - humans will resolve them manually after reviewing the changes
- If a review comment is unclear, ask the user for clarification during the planning phase
- Use `gh api` for detailed operations not covered by `gh pr` commands
- Test critical changes before committing

### GitHub CLI Commands Reference

- View PR: `gh pr view <pr-number> --json comments,reviews`
- Get detailed review comments: `gh api repos/{owner}/{repo}/pulls/<pr-number>/comments`
- Fetch review threads (with thread IDs for replying):
  ```bash
  gh api graphql -f query='query { repository(owner: "{owner}", name: "{repo}") { pullRequest(number: {pr_number}) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 10) { nodes { id databaseId body author { login } path line } } } } } } }'
  ```
- Reply to comment (uses thread ID, not comment ID):
  ```bash
  gh api graphql -f query='mutation { addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: "<thread_id>" body: "..." }) { comment { id body } } }'
  ```
- Get repo info: `gh repo view --json owner,name`
{{/if}}
