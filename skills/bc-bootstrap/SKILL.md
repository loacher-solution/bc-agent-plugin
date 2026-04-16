---
name: bc-bootstrap
description: Initializes a Business Central project for Claude Code. Resolves the AL toolchain, offers to install BcContainerHelper, writes .mcp.json with almcp and bc-symbols MCP server entries, and creates CLAUDE.md. Run once per project before using the bc-developer subagent.
---

# bc-bootstrap

First-run setup for a Business Central AL project. Idempotent: running it twice is a no-op if everything is already in place.

## When to use

- The user opens a folder with `app.json` but no `.mcp.json` entry for `almcp`.
- The user says "set up Claude for this BC project" or similar.
- Another BC skill fails with "AL toolchain not found".

## Steps

Run these steps in order, using the `Bash` tool to invoke the PowerShell scripts.

### 1. Verify `app.json` exists

If there is no `app.json` at the project root, stop and tell the user: "Run this from a Business Central project root (the folder containing `app.json`)."

### 2. Check that PowerShell 7 is installed

```bash
pwsh -NoProfile -File <plugin>/skills/bc-bootstrap/scripts/ensure-pwsh7.ps1
```

If the result is `status: "missing"` or `"outdated"`, ask the user whether to install PowerShell 7 via winget: `winget install --id Microsoft.PowerShell --source winget`. Do not run the install without confirmation.

### 3. Resolve the AL toolchain

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin>/skills/bc-bootstrap/scripts/resolve-al-tools.ps1
```

Parse the JSON output.

- `status: "ok"` → note the `toolsPath` and proceed to step 5.
- `status: "not-found"` → proceed to step 4 (download from marketplace).

### 4. Download the AL vsix (fallback)

Ask the user: "The AL toolchain was not found on this machine. Download the AL Language extension from the Visual Studio Marketplace into the plugin's cache? This is a one-time download of ~100 MB." Only proceed on confirmation.

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin>/skills/bc-bootstrap/scripts/download-al-vsix.ps1
```

If the result is `status: "error"`, surface the message to the user and stop.

### 5. Offer to install BcContainerHelper if missing

```bash
powershell -NoProfile -Command "if (Get-Module -ListAvailable BcContainerHelper) { 'installed' } else { 'missing' }"
```

If the output is `missing`, tell the user: "BcContainerHelper is required for container mode (debug/test workflows). It is not needed for compile-only work. Install now? (`Install-Module BcContainerHelper -Scope CurrentUser -Force`)" Only install on confirmation. Do not fail bootstrap if the user declines — container mode will fail later if attempted.

### 6. Write `.mcp.json` and `CLAUDE.md`

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin>/skills/bc-bootstrap/scripts/write-mcp-config.ps1 -ProjectRoot "<abs-project-root>" -AlToolsPath "<from-step-3-or-4>" -PluginRoot "<plugin-install-root>"
```

### 7. Summarize and instruct restart

Report to the user:

- Where the AL toolchain lives
- Which MCP servers were registered
- Whether `CLAUDE.md` was created or left untouched

**Critical:** The `almcp` and `bc-symbols` MCP servers were just registered in `.mcp.json` but are **not yet connected** in this session. Claude Code only reads `.mcp.json` at session start.

Tell the user:

> "Bootstrap complete. **Please restart this Claude Code session** (close and reopen, or start a new conversation in this project folder) so the `almcp` and `bc-symbols` MCP servers connect. After restarting, use `/bc <task>` to start working — the `al_downloadsymbols` and `bc_find_object` tools will be available."

**Do NOT attempt to call `almcp` tools (like `al_downloadsymbols` or `al_build`) in this same session.** They won't be available until after the restart. Do not try to work around this by shelling out to `altool.exe` directly — that defeats the MCP architecture.

## Failure modes

- Missing `app.json` → "Run this from a BC project root (folder containing `app.json`)."
- AL toolchain unreachable and network download declined → "AL toolchain not found. Set `$env:BC_AGENT_AL_TOOLS_PATH`, install the VS Code AL extension, or re-run with network access."
- Existing `CLAUDE.md` → never overwritten; a note is printed instead.
