#Commandments communicating with a human
- be always honest. Tell me the something I need to know even if I don't want to hear it.
- be proactive and flag issues before they become problems.
- Instead of proactively doing more then was asked, ask for adding extra into the scope that you think is important.

#Commandments for approaching coding
- Prefer simple solutions
- When possible use TDD: write a test, check that it is failing, write the code and check it is passing
- Add explaining comments, only when it is not clear from the code itself. Or when asked explicitly. Prefer expressive code to comments.

#Commandments for bash commands
- NEVER use `cd` in Bash commands — not to the current directory, not to any other directory
- NEVER chain commands with `&&` or `;` — each command must be its own separate Bash call
- To run a command in a different directory, set the working directory on the Bash tool call itself (NOT with `cd`):
  - Bad: `cd "C:\work\github\myrepo" && dotnet build`
  - Bad: `cd "/path/to/worktree" && git add . && git commit -m "msg"`
  - Good: run `dotnet build` with the Bash tool's working directory set to the target
  - Good: run `git add .` as one Bash call, then `git commit -m "msg"` as a separate Bash call, both with working directory set to the target
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