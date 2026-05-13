#Commandments communicating with a human
- be always honest. Tell me the something I need to know even if I don't want to hear it.
- be proactive and flag issues before they become problems.
- Instead of proactively doing more then was asked, ask for adding extra into the scope that you think is important.

#Commandments for approaching coding
- Prefer simple solutions
- When possible use TDD: write a test, check that it is failing, write the code and check it is passing
- Add explaining comments, only when it is not clear from the code itself. Or when asked explicitly. Prefer expressive code to comments.
- Comments must describe what the code does now, not what changed to get here. Especially during refactoring: never write "refactored from X", "now uses Y instead of Z", "previously did W", "moved from A". Once the refactor is in the past, these comments become noise that misleads readers. Write comments that would still make sense to someone reading the code a year from now with no knowledge of its history.

#Commandments for bash commands
- NEVER use `cd` in Bash commands — not to the current directory, not to any other directory
- NEVER chain commands with `&&` or `;` — each command must be its own separate Bash call
- NEVER prefix commands with `GIT_DIR=` or `GIT_WORK_TREE=` environment variables
- For git commands in a different repo, use `git -C <path>`:
  - Bad: `cd "C:\work\github\myrepo" && git status`
  - Bad: `GIT_DIR="..." GIT_WORK_TREE="..." git status`
  - Good: `git -C C:/work/github/myrepo status`
- For non-git commands in a different directory, use absolute paths
- This allows granular permission control per command

# Local GitHub Repos

> **IMPORTANT**: When the user mentions ANY repo, package, SDK, library, or dependency by name — even casually — ALWAYS check the local filesystem FIRST before searching the web or claiming you can't access it. This includes references like `unified-to/unified-csharp-sdk`, "the unified SDK", "check the platform repo", etc.

Repos are stored at `C:\work\github\{org}\{repo-name}`.

**Resolution steps** (follow in order for every repo/library mention):
1. **Exact `org/repo`**: resolve directly to `C:\work\github\{org}\{repo}` and READ from that path
2. **Partial or ambiguous name**: read `${CLAUDE_REPO_MAP:-/c/work/claude-data/repo-map.md}` for the full repo list with descriptions, match by name or summary, then READ from the matched path
3. **Multiple matches**: show candidates and ask user to confirm
4. **Not found locally**: only then fall back to web search or tell the user the repo isn't available locally
5. **Before reading code**: if the resolved repo is not the current working directory, run `git pull` in that repo to ensure you're reading the latest code

Example: user says "look at `unified-to/unified-csharp-sdk`" → read files from `C:\work\github\unified-to\unified-csharp-sdk\`.

Regenerate the map: `bash ~/dotfiles/claude/scripts/update-repo-map.sh`

# Symlink Management

Files in this repo are symlinked to `~/.claude/` and `~/.bash.d/` by the install script. After creating new files that need to be symlinked, the install script must be re-run.

On Windows without Developer Mode, use `install-admin.ps1` in the repo root — it self-elevates to admin (UAC prompt) and runs `install.sh --home`.

# Ticket Context Documents

Session history for Linear tickets, stored outside the repo for worktree access.

## Configuration

Set the environment variable to customize the storage location:

```bash
export CLAUDE_TICKET_CONTEXTS_DIR="/c/work/ticket-contexts"
```

Default: `/c/work/ticket-contexts/`

## Structure

Each ticket gets its own file: `{TICKET-ID}.md` containing:
- Ticket info and Linear link
- Session history (accomplishments, decisions, files changed)

## Document Template

```markdown
# {TICKET-ID}: {Ticket Title}

## Ticket Info
- **Linear Link**: https://linear.app/team/issue/{TICKET-ID}
- **Created**: {YYYY-MM-DD}

## Sessions

### {YYYY-MM-DD HH:MM} - {Brief Session Title}
**Branch**: `{branch-name}`
**Repository**: `{repo-name}`

#### Accomplished
- {bullet list}

#### Key Decisions
- {decision}: {rationale}

#### Files Changed
- `{path}` - {description}

---
```

# Repo Map

A generated index of all local GitHub repos with README-derived summaries. Used for resolving partial or ambiguous repo references.

## Configuration

Set the environment variable to customize the storage location:

```bash
export CLAUDE_REPO_MAP="/c/work/claude-data/repo-map.md"
```

Default: `/c/work/claude-data/repo-map.md`

Regenerate: `bash ~/dotfiles/claude/scripts/update-repo-map.sh`

# MLflow telemetry (dev env)

- Server: `https://mlflow-devweu.devds.net`, experiment id `9` (DataSnipper agents-and-tools dev).
- Chat-session UUID lives in trace `request_metadata` under `mlflow.trace.session`.
  Search filter: `metadata.\`mlflow.trace.session\` = '<uuid>'` (NOT `tags.`).
- For full per-trace span data, use `GET /api/3.0/mlflow/traces/get?trace_id=…`.
  `GET /ajax-api/2.0/mlflow/get-trace-artifact` is the pre-3.3.0 artifact path
  and returns only a UI subset of spans — do not use it on this server.
- Responses regularly exceed 10 MB. **Do not pull traces through `WebFetch`.**
  Use `~/dotfiles/claude/scripts/mlflow_dump.py` instead — it writes compact projections
  to `~/.cache/mlflow-dump/` and only emits full span payloads on demand.
  The `/ds:analyze-mlflow` slash command wraps this for chat-session analysis.