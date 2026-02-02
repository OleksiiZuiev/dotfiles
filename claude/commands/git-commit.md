---
description: Commit changes to git with an optional context parameter to guide the commit message
allowed-tools: Bash(git status:*), Bash(git add:*), Bash(git diff:*), Bash(git log:*), Bash(git commit:*)
argument-hint: "[context]"
---

Stage and commit changes directly using git commands (do NOT use Task tool or delegate to an agent).

## Steps

1. Run git commands to understand the current state:
   - `git status` - see untracked/modified files
   - `git diff` - see staged and unstaged changes
   - `git log --oneline -3` - follow repository's commit message style

2. Create a concise commit message (1-2 sentences, not verbose):
   - Use conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
   - Focus on "why" not "what"

3. Stage relevant files and commit using HEREDOC format:
   ```bash
   git add <files>
   git commit -m "$(cat <<'EOF'
   <message>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: <model-name> <noreply@anthropic.com>
   EOF
   )"
   ```

4. Run `git status` after to verify success.

{{#if $ARGUMENTS}}
The user has provided the following context for the commit: "{{$ARGUMENTS}}"

Please integrate this context into your commit message where appropriate. Use it to inform the commit summary and provide additional clarity about the purpose or motivation for these changes.
{{else}}
The user has not provided any additional context for the commit. Proceed with the standard approach of analyzing the changes and crafting an appropriate commit message.
{{/if}}
