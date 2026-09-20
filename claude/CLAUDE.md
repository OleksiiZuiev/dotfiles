#Commandments communicating with a human
- be always honest. Tell me the something I need to know even if I don't want to hear it.
- be proactive and flag issues before they become problems.
- Instead of proactively doing more than was asked, ask for adding extra into the scope that you think is important. When the two pull against each other, flagging wins: raise it, don't act on it.

#Commandments for writing style
- One word per concept in text that gets maintained — identifiers, comments, docstrings, test names, the README. Once a value has a name, use that word for it, and never introduce a synonym for a value that already has a name, or a reader has to work out whether the two words mean the same thing. Chat replies are exempt: you read those once.
- Never make the reader resolve shorthand — name the thing, then put the shorthand in parentheses. Shorthand is a number ("Skill 5.6", "step 3", "rule 2"), a section marker (`§4.2`, `#5.6`, `[3]`), a bare code (a ticket key, flag, env var, or filename dropped in with no gloss), or a positional pointer ("the second one", "as above"). Shorthand stands alone only when it is already visible where the reader is — you printed it earlier in this same reply, or it appears in the same document. Anything you picked up from a file I have not seen is opaque to me: I have to stop and ask what it means, and often it is nowhere in your output. So write "the bash commandment about not using `cd` (4th bullet)", not "bash rule 4"; "the stacked-PR parent-detection ticket (INT-739)", not "INT-739". This applies to everything you write — chat replies, code comments, PR and commit descriptions, docs. Numbers as data are fine: counts, versions, dates, measurements, `file.ts:42`.

#Commandments for approaching coding
- Prefer simple solutions
- When possible use TDD: write a test, check that it is failing, write the code and check it is passing
- Test only your own contract: don't write tests that re-verify a dependency's behaviour (the validation library, the framework) or a trivially-true invariant.
- Keep a test in the file or suite named for the subject it exercises; when a test's subject changes, move or rename it to match.
- Every test must be able to fail for the reason it exists. Reject an assertion that also holds when the observed surface is empty (`x not in caplog.text` passes on empty output), a test whose only proof is that a *different* exception wasn't raised, and an assertion that pins only the absence of a previous implementation. If the behaviour in the test's name isn't observable at the seam under test, assert what is and rename the test to match.
- Add explaining comments only when the code isn't self-evident, or when asked. Prefer expressive code to comments, and delete any comment, JSDoc, or docstring that merely restates the code, a field name, or a type — keep only the non-obvious *why*; when in doubt, cut.
- Comments must describe what the code does now, not what changed to get here. Especially during refactoring: never write "refactored from X", "now uses Y instead of Z", "previously did W", "moved from A". Once the refactor is in the past, these comments become noise that misleads readers. Write comments that would still make sense to someone reading the code a year from now with no knowledge of its history. The same applies to speculative or future-tense rationale ("in case a future flow needs this", "kept for when X") and references to abandoned approaches — and to test names: name a test for the behaviour it asserts, never for an intermediate approach that was dropped.
- When you move or change a line, re-read the comment attached to it and cut the part that is no longer true there. A comment that was accurate about the old code is worse than no comment once half of it describes something the line no longer does.
- Don't describe another module's internals, or a contract owned elsewhere (another service, another repo's payload), in a comment — it drifts stale. Point to the one authoritative definition instead.

#Commandments for bash commands
- NEVER use `cd` in Bash commands — not to the current directory, not to any other directory
- NEVER prefix commands with `GIT_DIR=` or `GIT_WORK_TREE=` environment variables
- For git commands in a different repo, use `git -C <path>`:
  - Bad: `cd "C:\work\github\myrepo" && git status`
  - Bad: `GIT_DIR="..." GIT_WORK_TREE="..." git status`
  - Good: `git -C C:/work/github/myrepo status`
- For non-git commands in a different directory, use absolute paths
- This allows granular permission control per command
- NEVER root a recursive Bash read (`grep -r`, `rg`, `cp -r`) at a repo root or `.` — pass explicit paths (`grep -rn "pattern" src docs package.json`), or use the `Grep` tool, which does not prompt.
- Why: org-pushed deny rules cover `.env`, `.env.*`, `secrets/**`, `*.pem` and `id_rsa`; since Claude Code 2.1.259 a recursive Bash command over a directory holding any denied file needs manual approval — even when `--include` filters mean it would never open one.

# Local GitHub Repos

> **IMPORTANT**: When the user mentions ANY repo, package, SDK, library, or dependency by name — even casually — ALWAYS check the local filesystem FIRST before searching the web or claiming you can't access it. This includes references like `unified-to/unified-csharp-sdk`, "the unified SDK", "check the platform repo", etc.

Repos are stored at `C:\work\github\{org}\{repo-name}`.

**Exception — UpLink.** It lives on ext4 in WSL at `~/work/github/datasnipper-enterprise/UpLink`; there is no Windows clone. A Windows shell cannot usefully edit it, so each OS keeps its own map: `~/.claude/repo-map.md` in WSL, `/c/work/claude-data/repo-map.md` on Windows (Windows repos only).

**Resolution steps** (follow in order for every repo/library mention):
1. **Exact `org/repo`**: resolve directly to `C:\work\github\{org}\{repo}` and READ from that path
2. **Partial or ambiguous name**: read `${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}` for the full repo list, match by name or summary, then READ from the path in its `Path` column
3. **Multiple matches**: show candidates and ask user to confirm
4. **Not found locally**: only then fall back to web search or tell the user the repo isn't available locally
5. **Pull only when currency matters**: if the answer depends on current state — a teammate's branch, whether a fix landed, a comparison against `main` — run `git pull` in the resolved repo and say in your reply that you pulled. Otherwise read what is on disk.

Example: user says "look at `unified-to/unified-csharp-sdk`" → read files from `C:\work\github\unified-to\unified-csharp-sdk\`.

Regenerate the map: `bash ~/.claude/scripts/update-repo-map.sh`

# Ticket Context Documents

Linear session history lives in `${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}/{TICKET-ID}.md`.
Path convention and the document template: the `ticket-context` skill.

# MLflow telemetry

DataSnipper MLflow lives on `*.devds.net` — corporate VPN required. Never pull traces through
`WebFetch`; use `~/.claude/scripts/mlflow_dump.py`. Env matrix, session-filter syntax and the
`prdeus` legacy-API quirk: the `datasnipper-mlflow` skill. `/ds:analyze-mlflow <id> <env> <prompt>`
wraps it end-to-end.
