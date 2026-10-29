---
name: uplink-wsl-devcontainer
description: WSL only. How to actually run UpLink's tooling from the WSL shell, where Claude runs in WSL but the Python toolchain lives only inside the dev container. Covers the `docker exec` bridge, `up-tools test` instead of raw pytest, running ruff from WSL, committing through the pre-commit hook, and the traps (root-owned files, the shared `.venv`, non-persistent container config). Use whenever work in the WSL clone `~/work/github/datasnipper-enterprise/UpLink` needs pytest, up-tools, basedpyright, terraform, a commit, or an answer to "why can't I run this here". Not for the Windows clone at `C:\work\github\datasnipper-enterprise\UpLink`, which runs `uplink-ui` natively.
---

# Running UpLink tooling from WSL

Claude runs in the **WSL shell** (`$HOME` = `/home/oleksiizuiev`). UpLink's Python toolchain
exists only inside the **dev container** (`/workspaces/uplink`, user `vscode`). They share the
repo through a bind mount — `..:/workspaces/uplink:cached` in
`.devcontainer/docker-compose.yml` — so both see the same files and the same `.git`, but not
the same PATH and not the same `$HOME`.

Bridge into the container rather than sending the user to another window.

## The bridge

```bash
docker exec -u vscode -w /workspaces/uplink uplink_devcontainer-app-1 <command>
```

If that name ever fails, discover it instead of guessing:

```bash
docker ps --filter "label=com.docker.compose.project=uplink_devcontainer" \
          --filter "label=com.docker.compose.service=app" --format '{{.Names}}'
```

Two flags that are not optional:

- **`-u vscode`.** Default `docker exec` runs as **root**, and anything it writes lands
  root-owned in the WSL checkout.
- **`-w`, never `cd`.** The global bash commandments forbid `cd`; `-w` sets the working
  directory directly.

The container has to be running. If `docker ps` comes back empty, the user must open the dev
container in VS Code — that cannot be triggered from here.

## What runs where

| Task | Where |
|---|---|
| Backend tests, `up-tools`, basedpyright, terraform, `uv` | **Container only**, through the bridge |
| `ruff check` / `ruff format` | **WSL**, via `.venv/bin/ruff` |
| Frontend: `pnpm` typecheck, Vitest, dev server | **WSL** natively (node 24 / pnpm 10 in `~/.local/bin`) |
| `git`, `gh` | **WSL** — both authenticated there |
| `git commit` | **Container**, so the hook runs |

## Backend tests: `up-tools test`, never raw `pytest`

```bash
docker exec -u vscode -w /workspaces/uplink uplink_devcontainer-app-1 \
  uv run up-tools test projects/uplink-api/tests/<path>
```

Raw `uv run pytest` fails before collection with **40 missing-field validation errors** on
`Settings`. `settings.py` constructs `Settings()` at import time and its `env_file` resolves
to `projects/uplink-api/src/.env`, which does not exist in this checkout. `up-tools test`
(`tools/dev-tools/src/uplink_dev_tools/test.py`) loads the committed root `.env.test` through
`dotenv_values` and injects it into the pytest subprocess. Nothing else does — CI included,
whose mechanism is still unexplained.

Router tests need the real Postgres from the dev-container compose stack; pure transport
tests (`httpx.MockTransport`, module-level helpers) do not.

## Ruff runs from WSL

`.venv` sits inside the bind mount and its interpreter symlink points at the *container's*
`/usr/bin/python3.11`, so `.venv/bin/pytest` dies with "required file not found". Ruff is the
exception — a standalone Rust binary with no interpreter dependency:

```bash
~/work/github/datasnipper-enterprise/UpLink/.venv/bin/ruff check <file>
~/work/github/datasnipper-enterprise/UpLink/.venv/bin/ruff format --check <file>
```

Reach for it instead of eyeballing line lengths (ruff's default is 88; the repo sets no
override). It is not on PATH, so `command -v ruff` finds nothing — call the venv path.

## Committing

`.git/hooks/pre-commit` is hardcoded to `/workspaces/uplink/.venv/bin/python`, a path that
exists only in the container, so from WSL the commit dies with "`pre-commit` not found".
Commit through the bridge and the real check runs:

```bash
docker exec -u vscode -w /workspaces/uplink uplink_devcontainer-app-1 \
  git commit -F .git/<message-file>
```

Write a long commit message to a file **under `.git/`** — it is inside the bind mount so the
container can read it, and git never reports it in `status`. Delete it afterwards.

The hook runs `uv run up-tools precommit-check`: ruff format, ruff lint, terraform fmt, then
**basedpyright**. Only basedpyright **errors** block — warnings do not, and the repo carries
dozens of pre-existing ones, so do not chase them. If the hook rewrites files it fails the
commit; `git add -u` and retry.

`--no-verify` is a last resort, needs the user's explicit approval, and is usually refused by
the permission classifier anyway.

## Traps

- **Never `uv sync` from WSL.** `.venv` is in the bind mount and shared with the container. A
  WSL sync rewrites its interpreter and breaks the container. A separate WSL environment would
  need `UV_PROJECT_ENVIRONMENT` pointing outside the repo.
- **`/home/vscode/.config` is not a volume.** `.devcontainer/docker-compose.yml` declares only
  `postgres`, `rabbitmq_data` and `mongo_data`. So `git config --global` or `gh auth login`
  run *inside* the container is lost on rebuild, even though `remoteEnv` points
  `GIT_CONFIG_GLOBAL` and `NPM_CONFIG_USERCONFIG` there. Git identity for UpLink is therefore
  set **repo-locally** in `.git/config`, which is in the bind mount and survives.
- **Two homes, two credential stores.** `gh` being authenticated in WSL says nothing about the
  container, and the reverse. Check which side you are on before assuming.
- **`/c/work/ticket-contexts`** (ticket-context documents) is a WSL-side path and is not
  reachable under that name inside the container.
- **basedpyright sees what ruff does not.** `azure-storage-blob` attaches `error_code` to
  `HttpResponseError` at runtime but azure-core never declares it, so a direct attribute
  access is an error there and clean everywhere else. Read it with
  `getattr(exc, "error_code", None)` annotated `object`.

## When a Python change cannot be verified

If the container is not running, say so plainly and do not call a backend change verified.
`python3 -m py_compile` and an AST pass for unused imports and undefined names are cheap
WSL-side sanity checks — name them as what they are, not as tests or type-checking.
