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

3. **Scope Assessment**

   Assess the overall effort of unresolved comments to determine whether to process all at once or split into rounds.

   a. **Classify each comment** by effort level:
      - **Low** (1 point): typo, naming, style, simple one-liner fix
      - **Medium** (2 points): logic change in a single function, add validation, adjust error handling
      - **High** (3 points): refactoring across files, architectural change, new abstraction needed

   b. **Calculate total effort**: sum up effort points across all unresolved comments

   c. **Display effort summary**: show a table of comments with file, reviewer summary, and effort classification

   d. **Evaluate scope**:
      - **If total effort > 8 OR (any single comment is High AND there are >3 comments total)**:
        - Suggest splitting into rounds
        - Recommend which comments to address in this round (prioritize Low/Medium first, or group by file)
        - Use `AskUserQuestion` with options:
          - **"Address all"** — proceed with everything
          - **"Address recommended batch"** — process only the suggested subset
          - **"Let me pick"** — user selects which comments to handle
        - Comments not selected for this round are recorded as **deferred** (not processed, not replied to)
      - **If scope is manageable**: proceed with all comments (no change to existing flow)

4. **Triage Already-Addressed Threads**

   Before entering the Plan Phase, triage unresolved threads that already have replies (more than just the original review comment). Only triage threads that are **in scope** (not deferred). This step is silent — no user interaction needed.

   For each in-scope unresolved thread with replies:
   1. Read the full thread conversation (original comment + all replies)
   2. Check the current state of the code at the commented location
   3. Assess whether the reviewer's concern has already been addressed — either by a code change, an explanatory reply, or both
   4. **If addressed**: Exclude from processing. Record the thread and the reason it was considered addressed (e.g., "code changed in commit abc123", "explanatory reply given")
   5. **If NOT addressed**: Keep it in the processing queue (e.g., reply was a question back to the reviewer, code wasn't actually changed, reply acknowledged but didn't fix)

   After triage, display:
   - How many threads were auto-skipped as already addressed
   - For each skipped thread: the file, reviewer comment summary, and why it was considered addressed

5. **Plan Phase - For Each Remaining Unresolved Comment (One-by-One):**

   **IMPORTANT**: Process comments ONE AT A TIME. Only process threads that are **in scope** and were NOT auto-skipped in the triage step. For each comment:

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
      - If user selected "Dismiss comment", automatically use the agent's thinking buddy assessment as the rationale — no additional prompt needed
      - Record the dismissed comment with the agent's reasoning as rationale for the reply phase

   f. **Create Todo List**
      - After ALL comments are planned and approved, use TodoWrite
      - Format: "Address comment by @reviewer: <brief summary>"
      - Only include approved fixes in the todo list

6. **Implementation Phase - For Each Approved Fix:**

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

7. **Push All Changes**
   - **If there are NO deferred comments** (all unresolved comments were in scope):
     - Push as before:
       ```bash
       git push
       ```
   - **If there ARE deferred comments**:
     - Show summary: "Addressed X of Y comments. Z comments deferred to next round."
     - List deferred comments with their effort classification
     - **Do NOT push by default** — every push triggers a CI review round, so pushing partial work wastes CI cycles
     - Use `AskUserQuestion`:
       - **"Don't push yet (Recommended)"** — keep changes local, run `/polish-pr` again to continue with remaining comments
       - **"Push now"** — push what's done, accept that next round will trigger another CI run

8. **Update PR Description**
   - **Always run this step** — never auto-skip. After pushing, check whether the description still accurately reflects the PR.
   - **If no push was made** (user chose "Don't push yet"): skip this step entirely — description updates only make sense after pushing.
   - **Detect staleness** by checking each of these (any "yes" means the description needs updating):
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
       - Were files removed or significantly changed that the description doesn't reflect?
       - Were tests added or removed (test count in Verification section stale)?
       - Was documentation (README, CLAUDE.md, etc.) added or updated?
       - Did the approach or design change from what the summary describes?
       - Were new dependencies, helpers, or utilities introduced?
   - **Present findings** — show the user what's stale vs current, then use `AskUserQuestion`:
     - **"Update description"** — Revise the PR description to match current state
     - **"Skip"** — Keep the existing description as-is
   - **If approved, revise in-place:**
     - Keep the existing structure (Summary section, Verification section, Closes link)
     - Update the Summary section to reflect what the PR actually does now
     - Update the Verification section if test counts or steps changed
     - Preserve the `Closes <ticket>` link and any other metadata
     - Update using:
       ```bash
       gh pr edit {{$1}} --body "$(cat <<'EOF'
       <updated PR body>
       EOF
       )"
       ```

9. **Final Summary**
   - List all comments that were addressed with commit SHAs
   - List any threads that were auto-skipped as already addressed (from triage step), with the reason for each
   - List any comments that were skipped (with replies posted explaining the rationale)
   - List any comments that were dismissed (with replies posted explaining why)
   - If comments were deferred: "Run `/polish-pr` again to address remaining N comments" with a list of deferred comments and their effort classification
   - Note whether the PR description was updated
   - Remind user to manually resolve conversations after reviewing the changes

### Important Notes

- **Be Opinionated (Thinking Buddy)**: If a review comment is a style preference disguised as a bug, or if the existing code was actually correct, say so. Present your reasoning and let the user decide.
- **Reviewer Comments Are Suggestions, Not Mandates**: Evaluate each comment on its merit. Some may be wrong, some may have better alternatives. Your job is to give the PR author a second opinion.
- **Scope Management**: When many comments exist or comments imply significant refactoring, the agent assesses effort and may suggest splitting into multiple rounds. This prevents session overload and keeps each round focused.
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
- **PR Description Updates**: Always run the description check — never auto-skip. Present what's stale (new files, removed tests, doc changes, stale test counts) and let the user decide. Only truly cosmetic changes (typo fix, variable rename) warrant skipping without asking.
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

3. **Scope Assessment**

   Assess the overall effort of unresolved comments to determine whether to process all at once or split into rounds.

   a. **Classify each comment** by effort level:
      - **Low** (1 point): typo, naming, style, simple one-liner fix
      - **Medium** (2 points): logic change in a single function, add validation, adjust error handling
      - **High** (3 points): refactoring across files, architectural change, new abstraction needed

   b. **Calculate total effort**: sum up effort points across all unresolved comments

   c. **Display effort summary**: show a table of comments with file, reviewer summary, and effort classification

   d. **Evaluate scope**:
      - **If total effort > 8 OR (any single comment is High AND there are >3 comments total)**:
        - Suggest splitting into rounds
        - Recommend which comments to address in this round (prioritize Low/Medium first, or group by file)
        - Use `AskUserQuestion` with options:
          - **"Address all"** — proceed with everything
          - **"Address recommended batch"** — process only the suggested subset
          - **"Let me pick"** — user selects which comments to handle
        - Comments not selected for this round are recorded as **deferred** (not processed, not replied to)
      - **If scope is manageable**: proceed with all comments (no change to existing flow)

4. **Triage Already-Addressed Threads**

   Before entering the Plan Phase, triage unresolved threads that already have replies (more than just the original review comment). Only triage threads that are **in scope** (not deferred). This step is silent — no user interaction needed.

   For each in-scope unresolved thread with replies:
   1. Read the full thread conversation (original comment + all replies)
   2. Check the current state of the code at the commented location
   3. Assess whether the reviewer's concern has already been addressed — either by a code change, an explanatory reply, or both
   4. **If addressed**: Exclude from processing. Record the thread and the reason it was considered addressed (e.g., "code changed in commit abc123", "explanatory reply given")
   5. **If NOT addressed**: Keep it in the processing queue (e.g., reply was a question back to the reviewer, code wasn't actually changed, reply acknowledged but didn't fix)

   After triage, display:
   - How many threads were auto-skipped as already addressed
   - For each skipped thread: the file, reviewer comment summary, and why it was considered addressed

5. **Plan Phase - For Each Remaining Unresolved Comment (One-by-One):**

   **IMPORTANT**: Process comments ONE AT A TIME. Only process threads that are **in scope** and were NOT auto-skipped in the triage step. For each comment:

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
      - If user selected "Dismiss comment", automatically use the agent's thinking buddy assessment as the rationale — no additional prompt needed
      - Record the dismissed comment with the agent's reasoning as rationale for the reply phase

   f. **Create Todo List**
      - After ALL comments are planned and approved, use TodoWrite
      - Format: "Address comment by @reviewer: <brief summary>"
      - Only include approved fixes in the todo list

6. **Implementation Phase - For Each Approved Fix:**

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

7. **Push All Changes**
   - **If there are NO deferred comments** (all unresolved comments were in scope):
     - Push as before:
       ```bash
       git push
       ```
   - **If there ARE deferred comments**:
     - Show summary: "Addressed X of Y comments. Z comments deferred to next round."
     - List deferred comments with their effort classification
     - **Do NOT push by default** — every push triggers a CI review round, so pushing partial work wastes CI cycles
     - Use `AskUserQuestion`:
       - **"Don't push yet (Recommended)"** — keep changes local, run `/polish-pr` again to continue with remaining comments
       - **"Push now"** — push what's done, accept that next round will trigger another CI run

8. **Update PR Description**
   - **Always run this step** — never auto-skip. After pushing, check whether the description still accurately reflects the PR.
   - **If no push was made** (user chose "Don't push yet"): skip this step entirely — description updates only make sense after pushing.
   - **Detect staleness** by checking each of these (any "yes" means the description needs updating):
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
       - Were files removed or significantly changed that the description doesn't reflect?
       - Were tests added or removed (test count in Verification section stale)?
       - Was documentation (README, CLAUDE.md, etc.) added or updated?
       - Did the approach or design change from what the summary describes?
       - Were new dependencies, helpers, or utilities introduced?
   - **Present findings** — show the user what's stale vs current, then use `AskUserQuestion`:
     - **"Update description"** — Revise the PR description to match current state
     - **"Skip"** — Keep the existing description as-is
   - **If approved, revise in-place:**
     - Keep the existing structure (Summary section, Verification section, Closes link)
     - Update the Summary section to reflect what the PR actually does now
     - Update the Verification section if test counts or steps changed
     - Preserve the `Closes <ticket>` link and any other metadata
     - Update using:
       ```bash
       gh pr edit <pr-number> --body "$(cat <<'EOF'
       <updated PR body>
       EOF
       )"
       ```

9. **Final Summary**
   - List all comments that were addressed with commit SHAs
   - List any threads that were auto-skipped as already addressed (from triage step), with the reason for each
   - List any comments that were skipped (with replies posted explaining the rationale)
   - List any comments that were dismissed (with replies posted explaining why)
   - If comments were deferred: "Run `/polish-pr` again to address remaining N comments" with a list of deferred comments and their effort classification
   - Note whether the PR description was updated
   - Remind user to manually resolve conversations after reviewing the changes

### Important Notes

- **Be Opinionated (Thinking Buddy)**: If a review comment is a style preference disguised as a bug, or if the existing code was actually correct, say so. Present your reasoning and let the user decide.
- **Reviewer Comments Are Suggestions, Not Mandates**: Evaluate each comment on its merit. Some may be wrong, some may have better alternatives. Your job is to give the PR author a second opinion.
- **Scope Management**: When many comments exist or comments imply significant refactoring, the agent assesses effort and may suggest splitting into multiple rounds. This prevents session overload and keeps each round focused.
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
- **PR Description Updates**: Always run the description check — never auto-skip. Present what's stale (new files, removed tests, doc changes, stale test counts) and let the user decide. Only truly cosmetic changes (typo fix, variable rename) warrant skipping without asking.
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
