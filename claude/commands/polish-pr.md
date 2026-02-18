---
description: Address review comments on a PR
allowed-tools: Bash(git *), Bash(gh *), Read, Write, Edit, Grep, Glob, TodoWrite
argument-hint: [<pr-number>]
---

You are addressing review comments on a pull request by implementing fixes, committing them, replying to comments, and resolving conversations.

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
   - Note how many threads have existing replies (candidates for auto-skip triage)
   - Prepare to process each comment one-by-one

3. **Triage Already-Addressed Threads**

   Before entering the Plan Phase, triage unresolved threads that already have replies (more than just the original review comment). This step is silent — no user interaction needed.

   For each unresolved thread with replies:
   1. Read the full thread conversation (original comment + all replies)
   2. Check the current state of the code at the commented location
   3. Assess whether the reviewer's concern has already been addressed — either by a code change, an explanatory reply, or both
   4. **If addressed**: Exclude from processing. Record the thread and the reason it was considered addressed (e.g., "code changed in commit abc123", "explanatory reply given")
   5. **If NOT addressed**: Keep it in the processing queue (e.g., reply was a question back to the reviewer, code wasn't actually changed, reply acknowledged but didn't fix)

   After triage, display:
   - How many threads were auto-skipped as already addressed
   - For each skipped thread: the file, reviewer comment summary, and why it was considered addressed

4. **Plan Phase - For Each Remaining Unresolved Comment (One-by-One):**

   **IMPORTANT**: Process comments ONE AT A TIME. Only process threads that were NOT auto-skipped in the triage step. For each comment:

   a. **Display Comment Context**
      - Show file path and line number
      - Show the code snippet being reviewed
      - Show the reviewer's comment
      - Show surrounding code for context (if helpful)

   b. **Assess Comment & Propose Fix**

      **Part 1 — Thinking Buddy Assessment:**
      - **Evaluate the comment's merit**: Does the suggestion actually improve the code? Is it a valid concern or a style preference? Does it address a real problem?
      - **Flag disagreements**: If the suggested approach has downsides or the existing code was correct, say so with reasoning
      - **Suggest alternatives**: If there's a better way to address the reviewer's underlying concern than what they suggested, propose it
      - **Categorize**: Indicate whether this is a "strong agree", "agree with modifications", "minor/style preference", or "disagree — here's why"

      **Part 2 — Proposed Fix:**
      - Based on the assessment, propose a specific fix (may differ from what the reviewer suggested if you have a better idea)
      - Explain what changes will be made and why
      - If you disagree with the comment, still propose what you would do if asked (but clearly communicate the disagreement)

   c. **Get User Approval**
      - Use `AskUserQuestion` to present options:
        - **"Approve fix"** - Proceed with this specific fix
        - **"Approve all similar"** - If pattern detected, batch similar fixes
        - **"Modify approach"** - User wants to change the proposed fix
        - **"Skip this comment"** - Don't address this comment now (deal with later)
        - **"Dismiss comment"** - Agree with agent's assessment that this comment doesn't warrant a change
      - Wait for user decision before proceeding to next comment
      - Record approved fixes for implementation phase

   d. **Handle Skipped Comments**
      - If user selected "Skip this comment", ask for the rationale using `AskUserQuestion`:
        - **"Not applicable"** - The comment doesn't apply to current code
        - **"Will address later"** - Plan to address in a future PR
        - **"Disagree with suggestion"** - Have a different approach in mind
        - **"Custom explanation"** - Provide custom rationale
      - Record the skipped comment and rationale for the reply phase

   e. **Handle Dismissed Comments**
      - If user selected "Dismiss comment", ask for the rationale using `AskUserQuestion`:
        - **"Use agent's reasoning"** - Use the thinking buddy assessment as the rationale
        - **"Not applicable"** - The comment doesn't apply to current code
        - **"Disagree with suggestion"** - Have a different technical opinion
        - **"Custom explanation"** - Provide custom rationale
      - Record the dismissed comment and rationale for the reply phase

   f. **Create Todo List**
      - After ALL comments are planned and approved, use TodoWrite
      - Format: "Address comment by @reviewer: <brief summary>"
      - Only include approved fixes in the todo list

5. **Implementation Phase - For Each Approved Fix:**

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

   e. **Reply to Dismissed Comments**
      - For each dismissed comment, post a threaded reply explaining why no change is warranted:
        ```bash
        gh api graphql -f query='
        mutation {
          addPullRequestReviewThreadReply(input: {
            pullRequestReviewThreadId: "<thread_id>"
            body: "Won'\''t be changing this.\n\n**Reason:** <rationale>\n\n🤖 Generated with [Claude Code](https://claude.ai/claude-code)"
          }) {
            comment {
              id
              body
            }
          }
        }'
        ```

   f. **Mark Todo Complete**
      - Update TodoWrite to mark this comment as completed

6. **Push All Changes**
   - After all comments are addressed:
     ```bash
     git push
     ```
   - This updates the PR with all fix commits

7. **Update PR Description (if scope changed)**
   - After pushing, check whether polishing changed the PR's scope enough to warrant a description update
   - **Detect scope changes:**
     - Fetch the current PR description:
       ```bash
       gh pr view {{$1}} --json body --jq '.body'
       ```
     - Fetch the full diff stat of the PR:
       ```bash
       gh pr view {{$1}} --json baseRefName --jq '.baseRefName'
       # then:
       git diff origin/<base-branch>...HEAD --stat
       ```
     - Compare the description against the actual PR state:
       - Are there new files in the diff not mentioned in the description?
       - Were files/features removed that the description still references?
       - Did the approach change from what the summary describes?
     - **Skip this step entirely** if the polishing was only style/formatting fixes (no new logic, no new files, no changed approach)
   - **Offer to update** — use `AskUserQuestion`:
     - **"Update description"** — Revise the PR description to match current state
     - **"Skip"** — Keep the existing description as-is
   - **If approved, revise in-place:**
     - Keep the existing structure (Summary section, Verification section, Closes link)
     - Update the Summary section to reflect what the PR actually does now
     - Update the Verification section if new test steps are needed
     - Preserve the `Closes <ticket>` link and any other metadata
     - Update using:
       ```bash
       gh pr edit {{$1}} --body "$(cat <<'EOF'
       <updated PR body>
       EOF
       )"
       ```

8. **Final Summary**
   - List all comments that were addressed with commit SHAs
   - List any threads that were auto-skipped as already addressed (from triage step), with the reason for each
   - List any comments that were skipped (with replies posted explaining the rationale)
   - List any comments that were dismissed (with replies posted explaining why)
   - Note whether the PR description was updated
   - Remind user to manually resolve conversations after reviewing the changes

### Important Notes

- **Be Opinionated (Thinking Buddy)**: If a review comment is a style preference disguised as a bug, or if the existing code was actually correct, say so. Present your reasoning and let the user decide.
- **Reviewer Comments Are Suggestions, Not Mandates**: Evaluate each comment on its merit. Some may be wrong, some may have better alternatives. Your job is to give the PR author a second opinion.
- **Already-Addressed Detection**: Before entering the Plan Phase, threads with existing replies are triaged. If the reviewer's concern appears already addressed (code was changed, explanatory reply was given), the thread is skipped entirely — no assessment, no user prompt, no reply posted. These are listed in the summary.
- **Two-Phase Approach**: ALWAYS complete the Plan Phase (get approval for ALL comments) before starting Implementation Phase
- **One-by-One Planning**: Process each comment individually during planning, getting user approval before moving to the next
- **Batch Approval**: When similar issues are detected (e.g., same type of fix across multiple files), offer "Approve all similar" option
- **No Auto-Implementation**: NEVER implement fixes without explicit user approval via AskUserQuestion
- **Thread IDs vs Comment IDs**: When replying to review comments, you must use the **thread ID** (format: `PRRT_*`), NOT the comment ID (format: `PRRC_*`). The REST API `/pulls/comments/{id}/replies` endpoint returns 404 - use GraphQL `addPullRequestReviewThreadReply` mutation instead.
- Make each fix a separate commit with a clear message
- **Always include attribution**: Every GitHub reply must include the Claude Code attribution line
- **Skipped vs Dismissed**: "Skip" means "deal with later" (won't address in this PR). "Dismiss" means "I've considered it and chosen not to change anything" (won't be changing this). Use the appropriate reply template for each.
- **Manual Resolution**: Conversations are NOT auto-resolved - humans will resolve them manually after reviewing the changes
- **PR Description Updates**: Only offer to update the description when polishing meaningfully changed the PR's scope (new files, removed features, changed approach). Style/formatting fixes don't warrant a description update.
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
   - Note how many threads have existing replies (candidates for auto-skip triage)
   - Prepare to process each comment one-by-one

3. **Triage Already-Addressed Threads**

   Before entering the Plan Phase, triage unresolved threads that already have replies (more than just the original review comment). This step is silent — no user interaction needed.

   For each unresolved thread with replies:
   1. Read the full thread conversation (original comment + all replies)
   2. Check the current state of the code at the commented location
   3. Assess whether the reviewer's concern has already been addressed — either by a code change, an explanatory reply, or both
   4. **If addressed**: Exclude from processing. Record the thread and the reason it was considered addressed (e.g., "code changed in commit abc123", "explanatory reply given")
   5. **If NOT addressed**: Keep it in the processing queue (e.g., reply was a question back to the reviewer, code wasn't actually changed, reply acknowledged but didn't fix)

   After triage, display:
   - How many threads were auto-skipped as already addressed
   - For each skipped thread: the file, reviewer comment summary, and why it was considered addressed

4. **Plan Phase - For Each Remaining Unresolved Comment (One-by-One):**

   **IMPORTANT**: Process comments ONE AT A TIME. Only process threads that were NOT auto-skipped in the triage step. For each comment:

   a. **Display Comment Context**
      - Show file path and line number
      - Show the code snippet being reviewed
      - Show the reviewer's comment
      - Show surrounding code for context (if helpful)

   b. **Assess Comment & Propose Fix**

      **Part 1 — Thinking Buddy Assessment:**
      - **Evaluate the comment's merit**: Does the suggestion actually improve the code? Is it a valid concern or a style preference? Does it address a real problem?
      - **Flag disagreements**: If the suggested approach has downsides or the existing code was correct, say so with reasoning
      - **Suggest alternatives**: If there's a better way to address the reviewer's underlying concern than what they suggested, propose it
      - **Categorize**: Indicate whether this is a "strong agree", "agree with modifications", "minor/style preference", or "disagree — here's why"

      **Part 2 — Proposed Fix:**
      - Based on the assessment, propose a specific fix (may differ from what the reviewer suggested if you have a better idea)
      - Explain what changes will be made and why
      - If you disagree with the comment, still propose what you would do if asked (but clearly communicate the disagreement)

   c. **Get User Approval**
      - Use `AskUserQuestion` to present options:
        - **"Approve fix"** - Proceed with this specific fix
        - **"Approve all similar"** - If pattern detected, batch similar fixes
        - **"Modify approach"** - User wants to change the proposed fix
        - **"Skip this comment"** - Don't address this comment now (deal with later)
        - **"Dismiss comment"** - Agree with agent's assessment that this comment doesn't warrant a change
      - Wait for user decision before proceeding to next comment
      - Record approved fixes for implementation phase

   d. **Handle Skipped Comments**
      - If user selected "Skip this comment", ask for the rationale using `AskUserQuestion`:
        - **"Not applicable"** - The comment doesn't apply to current code
        - **"Will address later"** - Plan to address in a future PR
        - **"Disagree with suggestion"** - Have a different approach in mind
        - **"Custom explanation"** - Provide custom rationale
      - Record the skipped comment and rationale for the reply phase

   e. **Handle Dismissed Comments**
      - If user selected "Dismiss comment", ask for the rationale using `AskUserQuestion`:
        - **"Use agent's reasoning"** - Use the thinking buddy assessment as the rationale
        - **"Not applicable"** - The comment doesn't apply to current code
        - **"Disagree with suggestion"** - Have a different technical opinion
        - **"Custom explanation"** - Provide custom rationale
      - Record the dismissed comment and rationale for the reply phase

   f. **Create Todo List**
      - After ALL comments are planned and approved, use TodoWrite
      - Format: "Address comment by @reviewer: <brief summary>"
      - Only include approved fixes in the todo list

5. **Implementation Phase - For Each Approved Fix:**

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

   e. **Reply to Dismissed Comments**
      - For each dismissed comment, post a threaded reply explaining why no change is warranted:
        ```bash
        gh api graphql -f query='
        mutation {
          addPullRequestReviewThreadReply(input: {
            pullRequestReviewThreadId: "<thread_id>"
            body: "Won'\''t be changing this.\n\n**Reason:** <rationale>\n\n🤖 Generated with [Claude Code](https://claude.ai/claude-code)"
          }) {
            comment {
              id
              body
            }
          }
        }'
        ```

   f. **Mark Todo Complete**
      - Update TodoWrite to mark this comment as completed

6. **Push All Changes**
   - After all comments are addressed:
     ```bash
     git push
     ```
   - This updates the PR with all fix commits

7. **Update PR Description (if scope changed)**
   - After pushing, check whether polishing changed the PR's scope enough to warrant a description update
   - **Detect scope changes:**
     - Fetch the current PR description:
       ```bash
       gh pr view <pr-number> --json body --jq '.body'
       ```
     - Fetch the full diff stat of the PR:
       ```bash
       gh pr view <pr-number> --json baseRefName --jq '.baseRefName'
       # then:
       git diff origin/<base-branch>...HEAD --stat
       ```
     - Compare the description against the actual PR state:
       - Are there new files in the diff not mentioned in the description?
       - Were files/features removed that the description still references?
       - Did the approach change from what the summary describes?
     - **Skip this step entirely** if the polishing was only style/formatting fixes (no new logic, no new files, no changed approach)
   - **Offer to update** — use `AskUserQuestion`:
     - **"Update description"** — Revise the PR description to match current state
     - **"Skip"** — Keep the existing description as-is
   - **If approved, revise in-place:**
     - Keep the existing structure (Summary section, Verification section, Closes link)
     - Update the Summary section to reflect what the PR actually does now
     - Update the Verification section if new test steps are needed
     - Preserve the `Closes <ticket>` link and any other metadata
     - Update using:
       ```bash
       gh pr edit <pr-number> --body "$(cat <<'EOF'
       <updated PR body>
       EOF
       )"
       ```

8. **Final Summary**
   - List all comments that were addressed with commit SHAs
   - List any threads that were auto-skipped as already addressed (from triage step), with the reason for each
   - List any comments that were skipped (with replies posted explaining the rationale)
   - List any comments that were dismissed (with replies posted explaining why)
   - Note whether the PR description was updated
   - Remind user to manually resolve conversations after reviewing the changes

### Important Notes

- **Be Opinionated (Thinking Buddy)**: If a review comment is a style preference disguised as a bug, or if the existing code was actually correct, say so. Present your reasoning and let the user decide.
- **Reviewer Comments Are Suggestions, Not Mandates**: Evaluate each comment on its merit. Some may be wrong, some may have better alternatives. Your job is to give the PR author a second opinion.
- **Already-Addressed Detection**: Before entering the Plan Phase, threads with existing replies are triaged. If the reviewer's concern appears already addressed (code was changed, explanatory reply was given), the thread is skipped entirely — no assessment, no user prompt, no reply posted. These are listed in the summary.
- **Two-Phase Approach**: ALWAYS complete the Plan Phase (get approval for ALL comments) before starting Implementation Phase
- **One-by-One Planning**: Process each comment individually during planning, getting user approval before moving to the next
- **Batch Approval**: When similar issues are detected (e.g., same type of fix across multiple files), offer "Approve all similar" option
- **No Auto-Implementation**: NEVER implement fixes without explicit user approval via AskUserQuestion
- **Thread IDs vs Comment IDs**: When replying to review comments, you must use the **thread ID** (format: `PRRT_*`), NOT the comment ID (format: `PRRC_*`). The REST API `/pulls/comments/{id}/replies` endpoint returns 404 - use GraphQL `addPullRequestReviewThreadReply` mutation instead.
- Make each fix a separate commit with a clear message
- **Always include attribution**: Every GitHub reply must include the Claude Code attribution line
- **Skipped vs Dismissed**: "Skip" means "deal with later" (won't address in this PR). "Dismiss" means "I've considered it and chosen not to change anything" (won't be changing this). Use the appropriate reply template for each.
- **Manual Resolution**: Conversations are NOT auto-resolved - humans will resolve them manually after reviewing the changes
- **PR Description Updates**: Only offer to update the description when polishing meaningfully changed the PR's scope (new files, removed features, changed approach). Style/formatting fixes don't warrant a description update.
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
