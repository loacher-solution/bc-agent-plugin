---
name: bc-container
description: Create, use, and remove Business Central containers via BcContainerHelper. Use when the user needs a local BC server for publish, debug, or running tests — NOT for symbol-only work, which al_downloadsymbols handles without a container.
---

# bc-container

Wraps BcContainerHelper's container lifecycle with project-aware defaults. The agent uses this skill when a task actually needs a running BC server.

## When to use

- The user asks to create / set up / spin up a container.
- The user asks to run tests, and `.bc-agent/container.json` does not exist.
- The user asks to publish and debug, and there is no container yet.
- The user asks to remove / clean up the container.

**Do NOT use this skill** for:

- Compile-only work → that needs symbols, and `al_downloadsymbols` via `almcp` handles that with no container.
- Symbol lookup → use the `bc-symbols` MCP server.

## Creating a container

### 1. Verify Docker Desktop

```bash
pwsh -NoProfile -File <plugin>/skills/bc-container/scripts/verify-docker.ps1
```

If `status` is `not-running` or `not-installed`, surface the message and stop.

### 2. Read the target version from `app.json`

```bash
pwsh -NoProfile -File <plugin>/skills/bc-container/scripts/read-bc-version.ps1 -AppJsonPath "<project>/app.json"
```

If `status` is `missing-versions`, ask the user for the platform/application version and offer to write them into `app.json`.

### 3. Create the container

Propose a container name (default: the project folder name) and ask the user to confirm. Then:

```bash
pwsh -NoProfile -File <plugin>/skills/bc-container/scripts/new-container.ps1 `
    -ProjectRoot "<abs-project-root>" `
    -ContainerName "<name>" `
    -Platform "<from-step-2>" `
    -Application "<from-step-2>"
```

This generates a random admin password, stores it in `%LOCALAPPDATA%\bc-agent-plugin\containers\<name>.json` with restricted ACLs, resolves the artifact URL, and calls `New-BcContainer` with `-accept_eula -includeAL -includeTestToolkit`.

### 4. Copy Test Toolkit symbols into `.alpackages/`

```bash
pwsh -NoProfile -File <plugin>/skills/bc-container/scripts/copy-test-toolkit-symbols.ps1 -ProjectRoot "<abs>" -ContainerName "<name>"
```

This gives the compiler visibility into the Test Runner / Library Assert / etc. symbols that `al_downloadsymbols` (global sources) cannot provide.

### 5. Summarize

Report to the user:

- Container name
- API port
- Where credentials are stored
- Metadata path (`<project>/.bc-agent/container.json`) so future sessions find the container automatically

## Removing a container

```bash
pwsh -NoProfile -File <plugin>/skills/bc-container/scripts/remove-container.ps1 -ProjectRoot "<abs>"
```

The script reads the container name from `.bc-agent/container.json` if not given explicitly. Always confirm with the user before running this — container removal is destructive.

## Using an existing container

Before creating a new container, always check whether `.bc-agent/container.json` exists. If yes, read it — the container may already exist and be reusable. Only create a new container if:

- `.bc-agent/container.json` is missing, or
- The user explicitly asks for a fresh one

## Failure modes

- Docker not running → "Start Docker Desktop and retry."
- BcContainerHelper not installed → "Run `/bc-setup` first to install prerequisites."
- `app.json` missing platform/application → ask the user for the target version.
- `New-BcContainer` fails → surface the BcContainerHelper error verbatim; the root cause is usually clear (image pull, EULA, port conflict).
