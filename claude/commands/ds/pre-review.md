---
description: Pre-review PR diff for style, naming, and convention issues before human review
allowed-tools: Bash(git *), Read, Edit, Grep, Glob
---

You are performing an automated pre-review of the current branch's changes. Your goal is to catch style, naming, and convention issues *before* a human reviewer sees the PR — reducing low-value comments and making human review faster.

**Distinction from `/polish-pr`**: `/polish-pr` addresses human reviewer comments *after* they've been posted. You act *before* human review — proactively catching issues so the reviewer doesn't have to raise them.

## Your Task

### Step 1: Gather Diff

1. Detect the base branch:
   ```bash
   git rev-parse --verify origin/main 2>/dev/null && echo "main" || echo "master"
   ```
2. Get the diff summary:
   ```bash
   git diff origin/<base>...HEAD --stat
   ```
3. Get the full diff:
   ```bash
   git diff origin/<base>...HEAD
   ```
4. If there is no diff (no changes compared to base), inform the user and stop:
   > No changes found between current branch and `origin/<base>`. Nothing to review.

### Step 2: Load Conventions

1. **Read the repo's `CLAUDE.md`** (at the repo root). This is the entry point for all conventions.
2. **Scan CLAUDE.md for links** to review-relevant documents — style guides, review checklists, coding conventions, naming rules. Look for:
   - Explicit file paths (e.g., `docs/style-guide.md`, `docs/coding-conventions.md`)
   - References to convention/style documents
   - Sections about code style, naming, formatting
3. **Follow and read linked docs** (up to 5 documents, to avoid context explosion). Only follow links that are relevant to code review — skip architecture docs, setup guides, deployment docs.
4. If no CLAUDE.md exists, proceed with general best practices for the detected language(s).

### Step 3: Analyze Diff

Review all changed files against the loaded conventions. Focus on these categories:

**In scope (first iteration):**
- **Style**: formatting, spacing, indentation inconsistencies, line length
- **Naming**: variable/method/class/file names that don't follow conventions or are unclear
- **Obvious refactorings**: extract method candidates, reduce duplication, simplify conditionals, dead code
- **Convention violations**: anything explicitly mentioned in CLAUDE.md or linked docs that the diff violates

**Explicitly out of scope** (do NOT flag these):
- Architecture and design decisions
- Logic correctness or business logic issues
- Test coverage or test improvements
- Performance optimization
- Security concerns (except obvious ones like committed secrets)

For each finding, assess severity:
- **`auto-fix`**: Obvious, safe to change automatically. No judgment call needed. Examples: trailing whitespace, wrong naming convention applied consistently, missing/extra blank lines.
- **`suggestion`**: Requires judgment or has trade-offs. Examples: renaming a public API method, extracting a method (subjective boundary), simplifying a conditional that might reduce readability.

### Step 4: Present Findings Report

Present findings grouped by category. Format:

```
## Pre-Review Findings

### Style (N issues)
1. **[auto-fix]** `path/to/file.cs:42` — Trailing whitespace
2. **[suggestion]** `path/to/file.cs:78-82` — Inconsistent indentation (tabs vs spaces)

### Naming (N issues)
1. **[auto-fix]** `path/to/file.cs:15` — Variable `x` should be `customerCount` per naming conventions
2. **[suggestion]** `path/to/file.cs:30` — Method `DoStuff()` is vague — consider `ProcessPaymentRequest()`

### Refactoring (N issues)
1. **[suggestion]** `path/to/file.cs:50-75` — Duplicate logic in `HandleA()` and `HandleB()` — extract shared method

### Convention Violations (N issues)
1. **[auto-fix]** `path/to/file.cs:10` — Missing XML doc comment on public method (per CLAUDE.md convention)
```

After the detailed list, show a summary:
> **Summary**: X auto-fixable issues, Y suggestions. Z total findings.

If no issues found:
> **Pre-review passed** — no issues found. The diff looks clean against loaded conventions.

Then stop (skip steps 5-7).

### Step 5: User Decision

Use `AskUserQuestion` to ask how to proceed:

- **"Apply all auto-fixes"** — Apply only auto-fixable issues, skip suggestions
- **"Review one-by-one"** — Go through each finding individually for approval (like `/polish-pr` style)
- **"Apply all"** — Apply everything (auto-fixes + suggestions)
- **"Report only"** — Don't change anything, just keep the report for reference

### Step 6: Apply Fixes

Based on user's choice:

**"Apply all auto-fixes"**: Apply all `auto-fix` items. Skip all `suggestion` items.

**"Review one-by-one"**: For each finding, show the context and proposed fix, then use `AskUserQuestion`:
- **"Apply"** — Apply this fix
- **"Skip"** — Don't apply this fix
- **"Apply all remaining"** — Apply this and all remaining fixes without further prompts

**"Apply all"**: Apply everything without individual confirmation.

**"Report only"**: Skip to Step 7.

After applying fixes:
1. Stage changed files: `git add <specific files that were modified>`
2. Commit with a descriptive message:
   ```bash
   git commit -m "$(cat <<'EOF'
   Pre-review: <brief summary of changes>

   - <change 1>
   - <change 2>
   ...

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
3. Do NOT push — the user controls when to push.

### Step 7: Summary

Present a final summary:

- **Applied fixes**: List each fix that was applied (file, line, what changed)
- **Skipped suggestions**: List any suggestions that were not applied (for user awareness)
- **No push**: Remind the user that changes are committed but not pushed

If "Report only" was chosen:
- Reiterate the findings for reference
- Note that no changes were made

## Important Notes

- **Local only**: This command operates on the local diff. No GitHub API calls needed.
- **Non-destructive**: Always commit fixes as a separate commit. Never amend existing commits.
- **Convention-driven**: The quality of findings depends on how well the repo's CLAUDE.md documents conventions. If conventions are sparse, findings will be limited to general best practices.
- **Read before suggesting**: Always read the full file context around a finding before proposing a fix — don't suggest changes based solely on the diff hunks.
- **Respect existing patterns**: If the codebase consistently uses a pattern that differs from "standard" conventions, follow the codebase pattern (consistency > correctness for style issues).
- **Don't be noisy**: Only flag issues that a human reviewer would actually comment on. If something is borderline or trivial, skip it. Fewer high-quality findings > many low-quality ones.
