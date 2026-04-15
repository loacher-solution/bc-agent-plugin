# Plan A — Plugin Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a marketplace-installable Claude Code plugin skeleton with manifest, marketplace descriptor, README, LICENSE, stub subagent, and two slash commands — so `/plugin install bc-agent-plugin` works and the plugin is ready for the real skills to be added in Plans B–E.

**Architecture:** Mirror the directory layout of `C:/Repos/superpowers`. Create `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` as the install entrypoints. Add empty-but-valid skeletons for `agents/bc-developer.md`, `commands/bc-setup.md`, `commands/bc.md` so the plugin loads without errors. No skill directories yet (Plans B–D add those). No PowerShell scripts yet.

**Tech Stack:** Markdown, JSON. No runtime dependencies.

---

## File Structure

**Create:**
- `.claude-plugin/plugin.json` — plugin manifest (name, version, description)
- `.claude-plugin/marketplace.json` — marketplace entry enabling `/plugin install`
- `README.md` — user-facing installation and usage instructions
- `LICENSE` — MIT license text
- `.gitignore` — ignore PowerShell cache, fixture extract output, editor junk
- `agents/bc-developer.md` — stub subagent with frontmatter and a one-paragraph body; full prompt lands in Plan E
- `commands/bc-setup.md` — `/bc-setup` slash command; stub text until Plan C implements `bc-bootstrap`
- `commands/bc.md` — `/bc` slash command; delegates to `bc-developer`
- `docs/roadmap.md` — v2+ roadmap captured from the spec

**Modify:** None (new project).

---

### Task 1: Create `.claude-plugin/plugin.json`

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create the manifest file**

Write `.claude-plugin/plugin.json` with this exact content:

```json
{
  "name": "bc-agent-plugin",
  "description": "Business Central AL development agent for Claude Code — compile, debug, test, and look up symbols offline without guessing",
  "version": "0.1.0",
  "author": {
    "name": "Marcel Loacher"
  },
  "homepage": "https://github.com/TODO-org/bc-agent-plugin",
  "repository": "https://github.com/TODO-org/bc-agent-plugin",
  "license": "MIT",
  "keywords": [
    "business-central",
    "al",
    "microsoft-dynamics",
    "erp",
    "claude-code"
  ]
}
```

- [ ] **Step 2: Validate JSON**

Run: `pwsh -NoProfile -Command "Get-Content .claude-plugin/plugin.json -Raw | ConvertFrom-Json | Out-Null; Write-Host OK"`
Expected: `OK` printed, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat(scaffold): add plugin.json manifest"
```

---

### Task 2: Create `.claude-plugin/marketplace.json`

**Files:**
- Create: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Create the marketplace descriptor**

Write `.claude-plugin/marketplace.json` with this exact content:

```json
{
  "name": "bc-agent-plugin-marketplace",
  "owner": {
    "name": "Marcel Loacher"
  },
  "plugins": [
    {
      "name": "bc-agent-plugin",
      "source": "./",
      "description": "Business Central AL development agent for Claude Code",
      "version": "0.1.0",
      "category": "development",
      "tags": ["business-central", "al", "erp"]
    }
  ]
}
```

- [ ] **Step 2: Validate JSON**

Run: `pwsh -NoProfile -Command "Get-Content .claude-plugin/marketplace.json -Raw | ConvertFrom-Json | Out-Null; Write-Host OK"`
Expected: `OK` printed, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat(scaffold): add marketplace.json for /plugin install"
```

---

### Task 3: Create `LICENSE`

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: Write MIT license**

Write `LICENSE` with this exact content:

```
MIT License

Copyright (c) 2026 Marcel Loacher

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Commit**

```bash
git add LICENSE
git commit -m "docs: add MIT license"
```

---

### Task 4: Create `.gitignore`

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write gitignore**

Write `.gitignore` with this exact content:

```
# PowerShell module cache
*.psm1.cache

# Test fixture extraction output
tests/**/fixtures/*.extracted/
tests/**/fixtures/*.unwrapped/

# Editor junk
.vs/
.vscode/*
!.vscode/settings.json.sample

# OS junk
Thumbs.db
desktop.ini
.DS_Store

# Plugin runtime cache (should never land in repo)
.bc-agent/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore"
```

---

### Task 5: Create stub `agents/bc-developer.md`

**Files:**
- Create: `agents/bc-developer.md`

- [ ] **Step 1: Write stub agent file**

Write `agents/bc-developer.md` with this exact content:

```markdown
---
name: bc-developer
description: Use for any Business Central AL development task — building features, fixing bugs, running tests, debugging, looking up objects/fields/procedures, managing containers. Knows the BC toolchain (almcp, bc-symbols, BcContainerHelper), the v28+ object model, AL conventions, and project layout. Prefers offline symbol lookup over guessing.
tools: all
---

# bc-developer subagent

You are a Business Central AL developer agent. You work on AL extensions targeting BC 2026 W1 (v28+).

**STATUS:** This is a v1 stub. The full system prompt is implemented in Plan E of the bc-agent-plugin implementation plans. Until Plan E lands, this subagent only provides identity and has no routing knowledge.

When invoked in the current state, tell the caller: "The bc-developer subagent prompt is not yet implemented. Run the tasks in Plan E to populate it."
```

- [ ] **Step 2: Commit**

```bash
git add agents/bc-developer.md
git commit -m "feat(scaffold): add bc-developer subagent stub"
```

---

### Task 6: Create `commands/bc-setup.md`

**Files:**
- Create: `commands/bc-setup.md`

- [ ] **Step 1: Write slash command**

Write `commands/bc-setup.md` with this exact content:

```markdown
---
description: Initialize a Business Central project for Claude Code — resolves the AL toolchain, writes .mcp.json, and registers the almcp and bc-symbols MCP servers.
---

Use the `bc-bootstrap` skill to initialize the current Business Central project for Claude Code.

Steps the skill performs:

1. Verify `app.json` exists at the project root.
2. Resolve the AL toolchain path (altool.exe, alc.exe, almcp).
3. Offer to install BcContainerHelper if missing.
4. Write or merge `.mcp.json` with `almcp` and `bc-symbols` entries.
5. Write or update `CLAUDE.md` with project-specific guidance.
6. Report the resolved toolchain path and next suggested step.

After `/bc-setup` completes, use `/bc <task>` to delegate BC work to the `bc-developer` subagent.
```

- [ ] **Step 2: Commit**

```bash
git add commands/bc-setup.md
git commit -m "feat(scaffold): add /bc-setup slash command"
```

---

### Task 7: Create `commands/bc.md`

**Files:**
- Create: `commands/bc.md`

- [ ] **Step 1: Write slash command**

Write `commands/bc.md` with this exact content:

```markdown
---
description: Delegate a Business Central AL development task to the bc-developer subagent.
---

Delegate this task to the `bc-developer` subagent:

$ARGUMENTS

The subagent knows the BC toolchain (almcp MCP server, bc-symbols MCP server, BcContainerHelper) and will look up any standard or third-party BC objects via bc-symbols before editing code. It will compile via `al_build` and report structured diagnostics.
```

- [ ] **Step 2: Commit**

```bash
git add commands/bc.md
git commit -m "feat(scaffold): add /bc slash command"
```

---

### Task 8: Create `README.md`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

Write `README.md` with this exact content:

````markdown
# bc-agent-plugin

A Claude Code plugin that turns Claude into a capable Business Central AL developer — compile, debug, test, look up symbols offline, and manage BC containers, without a human clicking around VS Code.

**Status:** v0.1.0 — walking skeleton. See `docs/superpowers/plans/` for the implementation plan and `docs/roadmap.md` for what's next.

## What it does

- Registers Microsoft's standalone `almcp` MCP server (`al_build`, `al_compile`, `al_publish`, `al_downloadsymbols`, `al_debug`, `al_setbreakpoint`, `al_getdiagnostics`) so Claude can drive the full AL build/publish/debug loop.
- Ships `bc-symbols`, a local MCP server that parses `.app` files offline and answers "what fields does Customer have", "what's the signature of Sales-Post.Run", "what extends Sales Header" — no hallucinations, no access to private Microsoft repositories needed.
- Provides `bc-container`, a skill wrapping BcContainerHelper's container lifecycle for full dev-loop work (publish, debug, test).
- Ships a `bc-developer` subagent that knows AL conventions and when to reach for each tool.

## Requirements

- Windows 10/11
- PowerShell 5.1 (stock); PowerShell 7 is installed automatically by `bc-bootstrap` if missing
- Network access on first run
- Optional: Docker Desktop (container mode only)

The plugin auto-provisions the AL toolchain — either by reusing a VS Code AL extension install, a BcContainerHelper vsix, or by downloading the vsix from the Visual Studio Marketplace into its own cache.

## Install

```
/plugin marketplace add https://github.com/TODO-org/bc-agent-plugin
/plugin install bc-agent-plugin
```

## First use on a BC project

```
/bc-setup
```

Then:

```
/bc add a field "Region Code" to the Customer table and a page extension showing it on the Customer Card
```

## License

MIT. See `LICENSE`.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

### Task 9: Create `docs/roadmap.md`

**Files:**
- Create: `docs/roadmap.md`

- [ ] **Step 1: Write roadmap**

Write `docs/roadmap.md` with this exact content:

```markdown
# Roadmap

Captures decisions deferred from v1 during brainstorming, plus known unknowns to resolve before working on them.

## v1 scope (current)

- `bc-bootstrap` — toolchain provisioning + `.mcp.json` writing (Plan C)
- `bc-container` — container lifecycle via BcContainerHelper (Plan D)
- `bc-symbol-lookup` — offline `.app` parser MCP server (Plan B)
- `bc-developer` subagent — shared AL knowledge and tool routing (Plan E)
- Plugin scaffold, slash commands, README, marketplace descriptor (Plan A)

## v2 deferred

### `bc-test-runner` skill

Wrap `Run-TestsInBcContainer` from BcContainerHelper. Orchestrate publish-test-app plus Test Runner codeunit invocation. Parse XML results into structured agent output.

Open question: can the VS Code Test Explorer LSP command be driven programmatically from outside VS Code?

### `bc-debug` skill and `bc-troubleshoot` MCP wiring

Start a debug session via `almcp.al_debug`. Determine empirically whether it needs a VS Code host. If yes, shim it; if no, auto-enable the BC-server-hosted Troubleshooting MCP HTTP endpoint in `.mcp.json` when a session is paused.

Open questions:

- Auth scheme for the BC-server-hosted `/mcp` HTTP endpoint (basic / AAD / session cookie — unknown)
- Whether `almcp.al_debug` operates without a VS Code debug adapter host
- Exact HTTP route the embedded `ModelContextProtocol.AspNetCore` uses inside `almcp` (was 404 on `/mcp` during the research probe)

### `bc-e2e` skill

Port the page scripting skill from `business-central-agentic-workflow`. Adapt for the new architecture.

## Symbol-lookup enhancements

- **Cross-app dependency walking.** `bc_find_extenders_of("Sales Header")` — requires tracking TableExtension, PageExtension, event subscribers during indexing.
- **XML-doc / caption / tooltip extraction.**
- **Full source retrieval.** Expose inner-zip `src/*.al` when present.
- **Compiled implementation.** Rewrite the MCP server in C#/.NET if profiling shows PowerShell parsing is too slow.

## Bootstrap and environment

- Multi-project workspace support (one `.mcp.json` at workspace root, multiple `app.json` folders beneath).
- Headless CI mode (no interactive prompts).
- Cross-plugin `.mcp.json` conflict detection.

## Container lifecycle

- Container pooling and reuse across runs.
- `/bc-container clean` cleanup command.
- Cloud sandbox targeting (publish and test against online sandboxes instead of local containers).

## Agent quality

- Eval harness for the `bc-developer` subagent — a set of "can the agent correctly add feature X" scenarios, run automatically against new versions of the prompt.
- Automatic `CLAUDE.md` object ID registry maintenance — a hook that updates the ID table after every successful compile.
```

- [ ] **Step 2: Commit**

```bash
git add docs/roadmap.md
git commit -m "docs: add v2+ roadmap"
```

---

### Task 10: Verification pass

- [ ] **Step 1: Verify directory layout matches spec**

Run: `pwsh -NoProfile -Command "Get-ChildItem -Recurse -File | Where-Object { \$_.FullName -notmatch '\.git' } | ForEach-Object { \$_.FullName.Replace((Get-Location).Path + '\', '') }"`

Expected output must include at least these lines (order may vary; other files from specs and plans folders are fine):

```
.claude-plugin\marketplace.json
.claude-plugin\plugin.json
.gitignore
LICENSE
README.md
agents\bc-developer.md
commands\bc-setup.md
commands\bc.md
docs\roadmap.md
```

- [ ] **Step 2: Validate both JSON files parse**

Run:
```
pwsh -NoProfile -Command "Get-Content .claude-plugin/plugin.json -Raw | ConvertFrom-Json | Out-Null; Get-Content .claude-plugin/marketplace.json -Raw | ConvertFrom-Json | Out-Null; Write-Host 'Both JSON files valid'"
```

Expected: `Both JSON files valid` printed.

- [ ] **Step 3: Verify agent frontmatter parses**

Run:
```
pwsh -NoProfile -Command "$c = Get-Content agents/bc-developer.md -Raw; if ($c -match '(?s)^---\r?\n(.+?)\r?\n---') { Write-Host 'Frontmatter present' } else { Write-Error 'No frontmatter' }"
```

Expected: `Frontmatter present` printed, exit code 0.

- [ ] **Step 4: No further commit needed**

Task 10 is verification only. If any step fails, go back and fix the offending earlier task.
