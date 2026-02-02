---
description: Refine a Linear ticket by collaboratively resolving ambiguities and capturing answers as acceptance criteria
allowed-tools: AskUserQuestion
argument-hint: <ticket-id>
---

You are helping refine a Linear ticket by identifying unclear aspects, questioning the user, and updating the ticket with clear acceptance criteria.

## Your Task

{{#if $1}}

Refine Linear ticket: **{{$1}}**

### Steps to Follow

#### 1. Fetch the Ticket

Use `mcp__linear-server__get_issue` with ticket ID `{{$1}}` and `includeRelations: true`.

Extract:
- Title
- Description (including current A/C if present)
- Comments
- Attachments
- Related issues
- Current state/status

Display a brief summary of the ticket to the user:
```
Ticket: {{$1}} - [Title]
Status: [Current Status]
Current Description: [Brief excerpt...]
```

#### 2. Analyze for Clarity

Review the ticket for common ambiguities:
- **Vague requirements**: "improve performance" without metrics, "make it better"
- **Missing/incomplete acceptance criteria**: No clear definition of done
- **Undefined terms**: Acronyms, domain-specific terminology not explained
- **Unclear scope boundaries**: What's included vs excluded from this ticket
- **Missing error handling**: What happens when things go wrong
- **Unstated assumptions**: Dependencies, prerequisites, constraints
- **Edge cases**: Boundary conditions, special scenarios not addressed
- **User interactions**: Missing details about UI/UX flows
- **Data requirements**: What data is needed, format, validation rules
- **Integration points**: How does this interact with other systems

If the ticket is already clear and well-defined, acknowledge this:
```
This ticket appears well-defined with clear acceptance criteria.
```

Then use `AskUserQuestion` to ask: "Would you like to add or refine anything?" with options:
- "Yes, let's refine further" - Continue with questioning
- "No, ticket is ready" - Exit gracefully

If the user chooses "No", exit without making changes.

#### 3. Interactive Questioning

Use the `AskUserQuestion` tool to clarify ambiguities:
- Group related questions together (max 4 questions per interaction)
- Use clear, specific questions with concrete options when possible
- For each question:
  - **header**: Short label (max 12 chars) like "Scope", "Error case", "Performance"
  - **question**: Full question ending with `?`
  - **options**: 2-4 distinct choices with descriptions
  - Set **multiSelect: true** when multiple choices can apply
- Continue iterations until all critical ambiguities are resolved
- Respect if user selects "Other" - they may have context you don't

**Example Questions:**

For vague performance requirement:
```
question: "What is the target response time for this operation?"
header: "Performance"
options:
  - label: "< 100ms"
    description: "Fast response for real-time interactions"
  - label: "< 500ms"
    description: "Acceptable for most user operations"
  - label: "< 2s"
    description: "Suitable for background operations"
```

For unclear scope:
```
question: "Which user roles should have access to this feature?"
header: "Access"
multiSelect: true
options:
  - label: "Admin"
    description: "Full administrative access"
  - label: "Standard User"
    description: "Regular authenticated users"
  - label: "Guest"
    description: "Unauthenticated visitors"
```

For error handling:
```
question: "What should happen if the operation fails?"
header: "Error case"
options:
  - label: "Show error message"
    description: "Display user-friendly error and allow retry"
  - label: "Silent fail"
    description: "Log error but don't block user flow"
  - label: "Rollback"
    description: "Undo partial changes and restore previous state"
```

#### 4. Update the Ticket

Format the refined requirements as acceptance criteria:

```markdown
## Acceptance Criteria
- User can perform action X when condition Y is met
- System displays Z when event occurs
- Error message "..." shown if validation fails on field A
- Performance: Operation completes within N seconds for M records
- Edge case: Handles empty/null/invalid input by doing X
```

**Guidelines**:
- Use bullet points starting with action verbs or clear states
- Be specific and measurable where possible
- Include both happy path and error scenarios
- Preserve any existing A/C that's still valid
- Place A/C section after the description, before any "Notes" or similar sections

Use `mcp__linear-server__update_issue` to update the description field with the new/updated A/C section. Update directly without separate approval.

#### 5. Add Audit Comment

Use `mcp__linear-server__create_comment` to document the refinement:

```markdown
## Ticket Refined via /refine

**Questions Asked:**
- [Question 1]
- [Question 2]

**Answers Provided:**
- [Answer 1]
- [Answer 2]

**Acceptance Criteria Added:**
- [New A/C 1]
- [New A/C 2]
```

#### 6. Summary

Display a concise summary to the user:
```
✓ Ticket refined: {{$1}}
✓ Questions asked: [N]
✓ Acceptance criteria updated

View ticket: [link to Linear ticket]
```

### Error Handling

- **Ticket not found**: Display clear error with suggestion to verify the ticket ID
  ```
  Error: Ticket {{$1}} not found. Please verify the ticket ID and try again.
  ```
- **Linear API fails**: Show error message and suggest retry
  ```
  Error: Failed to fetch ticket from Linear. Please try again.
  ```
- **User cancels mid-refinement**: If the user provides partial answers but doesn't complete, offer:
  ```
  Would you like to save the partial refinement as a comment on the ticket?
  ```
  Use `AskUserQuestion` with options:
  - "Yes, save as comment" - Add comment with partial progress
  - "No, discard" - Exit without changes

### Important Notes

- Focus on clarifying **what** needs to be done, not **how** to implement it
- Acceptance criteria should be testable/verifiable
- Keep the refinement collaborative - the human has context you may not have
- Don't add unnecessary requirements - only clarify what's ambiguous

{{else}}
**Error:** No ticket ID provided.

Usage: `/refine <ticket-id>`

Example:
- `/refine ENG-123`
- `/refine 550e8400-e29b-41d4-a716-446655440000`
{{/if}}
