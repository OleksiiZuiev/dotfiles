# task-run source: Linear

Read by `/task-run` for a Linear ticket. The ticket context file is `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{ID}.md`; its template and conventions are in the `ticket-context` skill.

## Load

1. Fetch the ticket with `mcp__claude_ai_Linear__get_issue` (`includeRelations: true`): title, description, comments, linked resources. Fetch any Notion page linked in the description or comments.
2. The workspace is the repo key on the `Workspace:` line of the ticket body. With no such line, ask.
3. The plan link is the `Plan:` line of the ticket body, a Linear document's URL. The plan's slug is the entry of `plan list --json` with `home: linear-doc` whose `locator` names the same document: compare the last hyphen-separated part of the URL path (the document's slugId), because a renamed document keeps it and changes the rest. With no `Plan:` line, or no matching entry (say so), the ticket has no plan.
4. **Phase**: the context file exists and `git diff origin/main --stat` shows changes means a continuation; anything else is a fresh start.
   - Fresh start: read the context file if it exists and build on its decisions.
   - Continuation: summarise the previous sessions (count, latest date, what was accomplished, key decisions) and the ticket's comments since; the extra context in the arguments, or else a question to the user, is the follow-up change to plan.

## Finish

Nothing to write: Linear's own status follows the pull request.

## Record

Launch a subagent (`model: haiku`) that appends a session entry to the context file, or creates the file from the `ticket-context` skill's template when it does not exist. Give it the ticket ID, the file path, the branch, the repository name, what was accomplished, the files changed, and each decision with its rationale (the option chosen, the main alternative rejected, the reason) — a decision without a known rationale is passed alone, never with an invented one.
