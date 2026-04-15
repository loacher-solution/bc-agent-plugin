# bc-agent-plugin — Design

**Status:** Draft v1
**Date:** 2026-04-15
**Author:** Marcel Loacher (with Claude)
**Target:** Business Central 2026 W1 (v28+) only

---

## 1. Vision & Scope

`bc-agent-plugin` is a shareable Claude Code plugin (installable via marketplace, same mechanism as `superpowers`) that gives an AI agent everything it needs to develop Microsoft Dynamics 365 Business Central AL extensions end-to-end — without a human in the VS Code UI. It targets BC 2026 W1 (v28+) only; legacy versions are not supported.

### Core architectural bet

Microsoft already ships most of the heavy lifting as standalone binaries in the AL Language extension — specifically `altool.exe launchmcpserver` (the `almcp` stdio MCP server exposing `al_build`, `al_compile`, `al_publish`, `al_downloadsymbols`, `al_debug`, `al_setbreakpoint`, `al_getdiagnostics`) and the BC-server-hosted Troubleshooting MCP HTTP endpoint.

The plugin's job is **not** to reimplement those. It is to:

1. Reliably provision the AL toolchain (find or download the binaries).
2. Register Microsoft's MCP servers with Claude Code via `.mcp.json`.
3. Fill the gaps Microsoft does not cover.
4. Provide a skilled subagent that knows when to use each tool.

### The gaps Microsoft does not fill — what this plugin owns

- **Offline symbol lookup.** Parsing `.app` files directly so the agent never hallucinates object IDs, field names, or procedure signatures, and never needs access to private Microsoft repositories. This is the primary pain point from the previous agent.
- **Environment provisioning.** BcContainerHelper wrappers for full container lifecycle (create, credential storage, symbol copy). Artifact-only symbol download is delegated to `al_downloadsymbols` with `globalSourcesOnly=true`.
- **Toolchain auto-provisioning.** Resolving `altool.exe` / `alc.exe` / `almcp` from wherever they happen to live on the user's machine, falling back to downloading the AL vsix from the Visual Studio Marketplace and unzipping it into a plugin cache.
- **Shared agent persona.** A `bc-developer` subagent that knows when to reach for `almcp` tools vs. the symbol-lookup MCP server vs. the container skill, and knows AL conventions and common error idioms.

### v1 scope — the walking skeleton

Three skills, one subagent, two slash commands, marketplace-installable:

1. **`bc-bootstrap`** — toolchain provisioning, writes project `.mcp.json`, offers BcContainerHelper install.
2. **`bc-container`** — container lifecycle (`New-BcContainer`, credentials, symbol copy).
3. **`bc-symbol-lookup`** — local stdio MCP server parsing `.app` files offline. The pain-D solution.

Plus `agents/bc-developer.md` (the subagent) and two commands: `/bc-setup` and `/bc`.

### Out of scope for v1 — tracked in roadmap

- `bc-test-runner` skill (no headless CLI exists; needs BcContainerHelper + Test Runner codeunit orchestration)
- `bc-debug` skill and `bc-troubleshoot` HTTP MCP wiring (open question whether `al_debug` works without a VS Code host)
- `bc-e2e` page scripting (port from old agent)
- BCPT performance tooling, upgrade/install code debugging, multi-project workspaces, cloud sandbox targeting

### Non-goals, ever

- Reimplementing the AL compiler
- Shipping Microsoft binaries in the plugin repository
- Supporting non-Windows hosts (BC is Windows-only)
- Supporting BC versions below v28

---

## 2. Architecture

### Layout (matches `superpowers` conventions)

```
bc-agent-plugin/
├── .claude-plugin/
│   ├── plugin.json              # manifest
│   └── marketplace.json         # enables install via /plugin install
├── skills/
│   ├── bc-bootstrap/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── resolve-al-tools.ps1
│   │       ├── download-al-vsix.ps1
│   │       └── write-mcp-config.ps1
│   ├── bc-container/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── new-container.ps1
│   │       └── copy-symbols-from-container.ps1
│   └── bc-symbol-lookup/
│       ├── SKILL.md
│       └── server/
│           ├── bc-symbol-mcp.ps1         # stdio MCP server entry point
│           └── lib/
│               ├── AppFileReader.ps1     # strip header, unzip, handle Ready2Run
│               ├── SymbolIndex.ps1       # walk Namespaces tree
│               └── Tools.ps1             # MCP tool handlers
├── agents/
│   └── bc-developer.md          # subagent persona
├── commands/
│   ├── bc-setup.md              # /bc-setup → runs bc-bootstrap
│   └── bc.md                    # /bc → delegates to bc-developer
├── tests/
│   ├── bc-bootstrap/*.Tests.ps1
│   └── bc-symbol-lookup/
│       ├── fixtures/*.app
│       └── *.Tests.ps1
├── docs/
│   └── roadmap.md               # v2+ plan and parked decisions
├── README.md
└── LICENSE
```

### The three MCP servers in a running project

After `bc-bootstrap` runs, the user's BC project has a `.mcp.json` registering:

1. **`almcp`** (Microsoft's, stdio) — launched via `altool.exe launchmcpserver <projectPath>`. Gives the agent `al_build`, `al_compile`, `al_publish`, `al_downloadsymbols`, `al_debug`, `al_setbreakpoint`, `al_getdiagnostics`. Registered unconditionally.

2. **`bc-symbols`** (ours, stdio) — launched via `pwsh bc-symbol-mcp.ps1 <packageCachePath>`. Offline parser over `.app` files in the project's `.alpackages/`. Exposes `bc_find_object`, `bc_get_fields`, `bc_get_procedures`, `bc_get_object_source`, `bc_search`, `bc_list_apps`. Always on; zero network, zero server dependencies.

3. **`bc-troubleshoot`** (Microsoft's, HTTP) — `http://<host>:<apiPort>/mcp`. In v1, a template entry is written to `.bc-agent/mcp-troubleshoot.template.json` (not `.mcp.json` itself, since Claude Code's `.mcp.json` has no disabled flag). v2 activates it in `.mcp.json` once auth and activation semantics are understood.

### Data flow — primary agent loop (edit → compile → fix)

```
User → /bc <task> → bc-developer subagent
                     │
                     ├─ reads CLAUDE.md, app.json
                     ├─ "what fields does Sales Header have?"
                     │     └─ bc-symbols MCP → bc_get_fields("Sales Header")
                     │          └─ reads .alpackages/Microsoft_Base Application_*.app
                     │              (strip 40-byte header, unzip, strip inner 40-byte
                     │               Ready2Run header, parse SymbolReference.json,
                     │               walk Namespaces tree)
                     ├─ edits AL files
                     └─ compiles
                           └─ almcp MCP → al_build
                                └─ if errors → al_getdiagnostics → iterate
```

### Toolchain resolution order (`bc-bootstrap`)

1. `$env:BC_AGENT_AL_TOOLS_PATH` if set
2. `$env:USERPROFILE\.vscode\extensions\ms-dynamics-smb.al-*\bin\win32\` (latest version by folder name)
3. `$env:LOCALAPPDATA\bc-agent-plugin\al-tools\bin\win32\` (plugin's own cache)
4. Extract from `C:\ProgramData\BcContainerHelper\Extensions\bc-gt\ALLanguage.vsix` if present
5. Download AL vsix from Visual Studio Marketplace (`https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-dynamics-smb/vsextensions/al/latest/vspackage`), unzip into plugin cache, use that

The resolved path is written into the project's `.mcp.json` as the `almcp` command, so subsequent runs skip resolution.

### Separation of concerns — key design rules

- **Skills are thin.** Anything Microsoft already does (compile, publish, debug, symbol download) is delegated to `almcp`. Skills only add work that Microsoft does not do.
- **The symbol-lookup MCP server is pure read-only.** It never mutates anything, never touches the network, never calls a BC server, never runs the AL compiler. It is a projection over files on disk.
- **`bc-bootstrap` must run on PowerShell 5.1** (stock Windows). The `bc-symbol-lookup` MCP server may require PowerShell 7 (`pwsh.exe`); if absent, `bc-bootstrap` offers to install it via winget before writing `.mcp.json`.
- **No skill reads or writes outside:** the current project folder, `$env:LOCALAPPDATA\bc-agent-plugin\`, and `C:\bcartifacts.cache\`. No global state mutation.

---

## 3. The three v1 skills

### Skill 1 — `bc-bootstrap`

**Purpose.** First-run setup for a BC project. Idempotent.

**Trigger conditions** (SKILL.md frontmatter): user opens a folder containing `app.json` but no `.mcp.json` entry for `almcp`; or user says "set up Claude for this BC project"; or any other BC skill fails with "AL toolchain not found".

**Steps:**

1. Verify `app.json` exists at project root. If not, fail with: "Run this from a BC project root (folder containing app.json)."
2. Resolve AL toolchain path using the 5-step order in Section 2. Cache the result at `$env:LOCALAPPDATA\bc-agent-plugin\toolchain.json`.
3. Verify `BcContainerHelper` PowerShell module is installed. If missing, ask the user: "BcContainerHelper is required for container mode. Install it now? (Install-Module BcContainerHelper -Scope CurrentUser -Force)". Install on confirmation.
4. Detect whether `.alpackages/` exists and has content. If empty, print a note: "Symbols not yet downloaded. The bc-developer agent will run `al_downloadsymbols` when needed."
5. Write or merge `.mcp.json` at project root with two active entries: `almcp` (pointing at the resolved `altool.exe`) and `bc-symbols` (pointing at `bc-symbol-mcp.ps1` with the project's `.alpackages/` as argument). Write a template for the v2 `bc-troubleshoot` server to `.bc-agent/mcp-troubleshoot.template.json` for future use.
6. Write or update a minimal `CLAUDE.md` at project root containing: BC version target, artifact cache path, and instructions for future Claude sessions to prefer the `bc-developer` subagent for BC work. If `CLAUDE.md` already exists, ask before overwriting; offer to merge.
7. Print a summary: resolved toolchain path, MCP servers registered, suggested next step.

**Explicitly does not:** download artifacts, create containers, install VS Code, touch any global state outside `$env:LOCALAPPDATA\bc-agent-plugin\`.

**Failure modes:**

- Missing `app.json` → "Run this from a BC project root (folder containing app.json)."
- Missing BcContainerHelper + user declines install → "BcContainerHelper is required for container mode. Install with: Install-Module BcContainerHelper -Scope CurrentUser -Force" (non-fatal — bootstrap continues; container mode will fail later if attempted).
- No network + no local toolchain → "AL toolchain not found. Checked: <5 paths>. Install the AL extension in VS Code, or set `$env:BC_AGENT_AL_TOOLS_PATH`."

### Skill 2 — `bc-container`

**Purpose.** Create and manage a local BC container for the full dev loop (publish, debug, tests). Only used when the user explicitly needs a running BC server; ordinary compile work doesn't need it.

**Not for symbol download.** Symbol download is handled by `almcp.al_downloadsymbols` with `globalSourcesOnly=true`, directly invoked by the `bc-developer` subagent. This skill does not reimplement that.

**Steps:**

1. Verify Docker Desktop is running. If not, fail with: "Docker Desktop is not running. Start it and retry."
2. Read `app.json` for target platform/application version. If absent, ask the user or default to latest sandbox W1.
3. Prompt for container name (default: project folder name) and credentials (default: generate a random password, store at `$env:LOCALAPPDATA\bc-agent-plugin\containers\<name>.json` with Windows ACLs restricted to the current user via `icacls /inheritance:r /grant:r "%USERNAME%:F"`).
4. Call `New-BcContainer` with sensible defaults:
   ```powershell
   New-BcContainer -accept_eula -accept_outdated `
     -containerName $name `
     -artifactUrl (Get-BcArtifactUrl -type Sandbox -country w1 -version $version) `
     -auth NavUserPassword -credential $cred `
     -includeAL -includeTestToolkit -updateHosts
   ```
5. After the container is up, copy symbol `.app` files from the container's Extensions share into `.alpackages/` — specifically the Test Toolkit apps that `al_downloadsymbols` does not provide.
6. Write container metadata to `.bc-agent/container.json` at project root: `{name, artifactUrl, createdAt, credentialsFile, apiPort}`. The `bc-developer` subagent reads this to know whether a container exists.
7. Print a summary: container name, ports, credentials file location, what to do next.

**Explicitly does not:** publish apps (use `almcp.al_publish`), run tests (v2 `bc-test-runner` skill), start debug sessions (v2 `bc-debug` skill).

**Failure modes:**

- Docker not running → clear message, no retry loop.
- Version mismatch between `app.json` platform and requested container version → warn and offer to proceed or abort.
- `New-BcContainer` failure → surface BcContainerHelper's error verbatim; these errors are usually clear about the root cause (image pull failure, license acceptance, port conflict).

### Skill 3 — `bc-symbol-lookup` ⭐ the pain-D solution

**Purpose.** Answer "what fields does X have / what's the signature of Y / where is Z defined?" **offline**, without guessing, without needing a running BC server, and without access to Microsoft private repositories.

**Shape.** A local stdio MCP server written in PowerShell (`server/bc-symbol-mcp.ps1`), registered in the project's `.mcp.json` as the `bc-symbols` server. The `SKILL.md` is a thin instruction layer telling the agent when to reach for this server's tools versus `almcp`.

**Startup sequence.** When Claude Code launches the `bc-symbols` server, the server:

1. Receives the package cache path as a CLI argument (default: `<cwd>\.alpackages`).
2. Enumerates `*.app` files there.
3. For each file: strips the 40-byte header, unzips, detects v28 Ready2Run wrappers (by presence of `readytorunappmanifest.json`), strips the inner 40-byte header, extracts `SymbolReference.json`, caches parsed JSON in memory keyed by `{AppId, Version}`.
4. Builds a flat index by recursively walking `Namespaces[*].Namespaces[*]...Tables | Pages | PageExtensions | Codeunits | Enums | Interfaces | Queries | Reports | XmlPorts`. Each object gets an entry: `{id, type, name, fullyQualifiedName, namespace, sourceApp, sourceAppVersion, fields?, procedures?}`.
5. Watches the `.alpackages/` folder via `FileSystemWatcher` and re-indexes on-change. Individual `.app` files are 5–50 MB; full re-index is fast enough to run on any change.
6. Begins serving stdio MCP requests.

**MCP tools exposed:**

| Tool | Parameters | Returns |
|------|------------|---------|
| `bc_find_object` | `name` (string, fuzzy); `type` (optional: Table, Page, Codeunit, Enum, …) | Array of matching objects: `{id, type, name, namespace, sourceApp, appVersion}` |
| `bc_get_fields` | `objectName` or `objectId`; `type` (Table or TableExtension); `filter` (optional substring) | Field array: `{id, name, typeName, typeLength?, caption?, enabled?}` |
| `bc_get_procedures` | `objectName` or `objectId`; `type` (Codeunit, Page, …); `filter` (optional) | Procedure array: `{name, scope (Public/Internal/Local), parameters: [{name, typeName, isVar}], returnType?}` |
| `bc_get_object_source` | `objectName` or `objectId`; `type` | The AL source text from the `.app`'s `src/` folder when available; else `null` |
| `bc_search` | `query` (string); `limit` (default 25) | Free-text search across names and captions, ranked by match quality |
| `bc_list_apps` | (none) | Array of indexed apps: `{id, name, publisher, version, path}` |

**Key design choices:**

- **No arbitrary truncation in wire format.** MCP tool results stream structured JSON; the agent pages naturally via tool calls. No need for response size limits.
- **Deterministic and offline.** The server never touches the network, never calls a BC server, never runs the AL compiler. Pure projection over disk.
- **Read-only.** No write tools. Ever.
- **Version-aware.** If `.alpackages/` has two versions of the same app (transient upgrade state), both are indexed and the agent disambiguates via `appVersion`.
- **Error-tolerant.** Corrupt or unparseable `.app` files log a warning and are skipped; the server still starts.

**Out of scope for v1 (on roadmap):** cross-app dependency walking (`bc_find_extenders_of`), XML-doc / caption-ladder extraction, full source retrieval for all objects (`bc_get_object_source` returns `null` for objects whose source is not present in the `.app`).

**Failure modes:**

- Empty `.alpackages/` → server starts and returns "no apps indexed" on every query; tools return a structured response directing the agent to run `al_downloadsymbols`.
- `SymbolReference.json` schema drift in a future BC version → server logs a schema warning and degrades gracefully (missing fields return null rather than crashing).

---

## 4. Subagent & slash commands

### The `bc-developer` subagent

**File.** `agents/bc-developer.md`, Markdown with YAML frontmatter.

**Frontmatter:**

```yaml
---
name: bc-developer
description: Use for any Business Central AL development task — building features, fixing bugs, running tests, debugging, looking up objects/fields/procedures, managing containers. Knows the BC toolchain (almcp, bc-symbols, BcContainerHelper), the v28+ object model, AL conventions, and project layout. Prefers offline symbol lookup over guessing.
tools: all
---
```

**System prompt contents** (~400–600 lines):

1. **Identity & scope.** "You are a Business Central AL developer agent. You work on AL extensions targeting BC 2026 W1 (v28+). You do not support legacy versions."

2. **Tool inventory and routing:**
   - Compile → `almcp.al_build` (never shell out to `alc.exe`)
   - Get build errors → `almcp.al_getdiagnostics`
   - Download symbols → `almcp.al_downloadsymbols` with `globalSourcesOnly=true` by default; fall back to `globalSourcesOnly=false` with server params from `.bc-agent/container.json` if a container exists; otherwise ask the user for server/tenant/environment
   - Look up object / field / procedure → `bc-symbols.bc_find_object`, `bc_get_fields`, `bc_get_procedures`, `bc_get_object_source`, `bc_search`
   - Publish → `almcp.al_publish` (`skipbuild=false` default; pass server target from container metadata)
   - Debug → `almcp.al_debug` (v2); then `bc-troubleshoot` HTTP MCP for stack/variables when paused (v2)
   - Create/manage container → `bc-container` skill
   - First-run setup → `bc-bootstrap` skill

3. **The "look before you leap" rule.** Before editing any AL file that references a BC standard object or a third-party extension, the agent must verify names and types via `bc-symbols`. Phrased as a hard rule with red-flag thoughts ("I remember this field name" → STOP, look it up).

4. **AL conventions pack.** Object ID ranges, namespace naming, Name vs Caption, TableRelation, field categorization, procedure visibility defaults, `internal` vs `public`, `[NonDebuggable]`, `[Test]` / `[HandlerFunctions]`, English-only for code/comments/commits. Short and declarative, not a tutorial.

5. **Error interpretation idioms.** Common AL compile errors and their usual causes:
   - `AL0185` / `AL0432` (missing type/name) → symbols not downloaded → run `al_downloadsymbols`
   - `AL0606` (duplicate object ID) → check CLAUDE.md ID registry
   - `AL0246` (no definition found) → verify signature via `bc_get_procedures`
   - `AL0161` (ambiguous procedure reference) → namespace issue → verify via `bc_find_object`

6. **Project state conventions.** Where to find things:
   - `app.json` — project metadata, dependencies, ID range
   - `.alpackages/` — symbol cache
   - `.bc-agent/container.json` — container metadata (if any)
   - `.mcp.json` — written by `bc-bootstrap`
   - `CLAUDE.md` — project-specific notes, object ID registry; read on startup, update after creating new objects

7. **Explicit anti-patterns** (learned from the old agent):
   - Do not grep BaseApp source on disk — use `bc_get_fields`.
   - Do not shell out to `alc.exe` — use `almcp.al_build`.
   - Do not reimplement `Download-Artifacts` — use `al_downloadsymbols`.
   - Do not assume a container exists; check `.bc-agent/container.json` first.
   - Do not ask the user for things readable from `app.json`.

8. **Hand-off rules.** Defer to the main conversation for: user-visible decisions (ID range, container name, credential storage), network credentials, destructive operations on project state.

**What the subagent does not contain.** No compile scripts, no symbol parser, no container lifecycle logic. Pure knowledge and orchestration.

### Slash commands

**`/bc-setup`** (`commands/bc-setup.md`) — expands to: "Use the `bc-bootstrap` skill to initialize this Business Central project for Claude Code. Resolve the AL toolchain, write `.mcp.json`, and report the result."

**`/bc`** (`commands/bc.md`) — expands to: "Delegate this task to the `bc-developer` subagent: $ARGUMENTS". Example: `/bc add a field "Region Code" to the Customer table and a page extension to show it on the Customer Card`.

That is all for slash commands in v1. No `/bc-compile`, `/bc-test`, `/bc-debug` — those are subagent-internal concerns.

---

## 5. Distribution, prerequisites, testing, roadmap

### Plugin distribution

**`.claude-plugin/plugin.json`:**

```json
{
  "name": "bc-agent-plugin",
  "description": "Business Central AL development agent for Claude Code — compile, debug, test, and look up symbols offline without guessing",
  "version": "0.1.0",
  "author": { "name": "Marcel Loacher" },
  "homepage": "https://github.com/<TODO-org>/bc-agent-plugin",
  "repository": "https://github.com/<TODO-org>/bc-agent-plugin",
  "license": "MIT",
  "keywords": ["business-central", "al", "microsoft-dynamics", "erp"]
}
```

**`.claude-plugin/marketplace.json`** — single-plugin marketplace, matching `superpowers` shape.

**Installation UX:**

```
/plugin marketplace add <repo-url>
/plugin install bc-agent-plugin
```

After that, the plugin's skills, agents, and commands are available in any Claude Code session. First use on a BC project: user types `/bc-setup` → `bc-bootstrap` runs → `.mcp.json` is written → subsequent sessions auto-load `almcp` and `bc-symbols`.

### Prerequisites (final)

**Hard requirements on the user's machine:**

- Windows 10/11
- PowerShell 5.1 (stock)
- Network access on first run

**Hard requirements the plugin auto-provisions or offers to install:**

- `BcContainerHelper` PowerShell module — `bc-bootstrap` offers install
- AL toolchain binaries — `bc-bootstrap` resolves via 5-step order

**Optional, container mode only:**

- Docker Desktop with Windows containers enabled
- Hyper-V or equivalent

**Explicitly NOT required:**

- VS Code (the plugin reuses AL extension binaries if present but runs fine without VS Code ever being installed)
- GitHub Copilot
- Any Microsoft account or MSDN license (global sources symbol download is anonymous)
- An existing BC container (symbol work needs none)

### Error handling philosophy

1. **Fail loud, early, specific.** No silent fallbacks. Errors name exactly which paths were checked and what the user can do about it.
2. **Three error classes, distinguished in output:** user-actionable, transient, plugin bug. Messages are tailored per class.
3. **MCP servers never swallow exceptions.** Log to stderr in a format Claude Code surfaces; return structured error responses; never die silently.
4. **Writes are guarded.** Before writing `.mcp.json` or `CLAUDE.md`, check existence and either merge (for `.mcp.json`) or ask for confirmation (for `CLAUDE.md`). No clobbering.

### Testing & validation plan for v1

**1. Pester unit tests per skill script.**

- `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1` — five path-resolution scenarios (env var, VS Code extension, bc-gt vsix, plugin cache, marketplace download mocked).
- `tests/bc-bootstrap/Download-AlVsix.Tests.ps1` — mock marketplace endpoint; verify extraction handles both 40-byte-header and plain-zip cases.
- `tests/bc-bootstrap/Write-McpConfig.Tests.ps1` — merge vs. create, disabled `bc-troubleshoot` entry written correctly.

**2. `bc-symbol-lookup` server tests.**

- `tests/bc-symbol-lookup/fixtures/*.app` — small real fixtures: stripped System Application, subset of Base Application, one Ready2Run wrapper.
- Parser tests: 40-byte-header strip, Ready2Run detection and inner header strip, `SymbolReference.json` Namespace walk.
- MCP protocol tests: spawn the server as a subprocess, send JSON-RPC `tools/list` and `tools/call` for each tool, assert response shapes.
- Negative tests: corrupt `.app`, truncated JSON, empty `.alpackages/` — server must degrade gracefully.

**3. End-to-end smoke test (manual, per release).**

- **Symbol-only mode:** fresh folder, `app.json` with platform/application set, run `/bc-setup`, ask agent to "add an empty codeunit named Greeting Helper in range 50100" and compile. Verify: `.mcp.json` written, symbols downloaded via `al_downloadsymbols`, codeunit compiles, `bc_find_object` returns the new codeunit after compile.
- **Container mode:** same fresh folder, run `/bc-setup`, then `/bc create a container for this project`, then same add-codeunit task. Verify container is up, app publishes, `bc_find_object` still works.

**4. Regression fixture.** The existing `business-central-agentic-workflow` project becomes a living regression test. v1 is "done" when the `bc-developer` subagent can perform, from scratch, the same object additions that project contains today — with fewer symbol-lookup mistakes than the old agent made.

**Not in v1:** eval harness for subagent prompt (v2), load tests for the MCP server (v2), cross-version compatibility tests (we target v28+ only).

### v2+ roadmap

Captured in `docs/roadmap.md`.

**Deferred from v1:**

- **`bc-test-runner` skill.** Wrap `Run-TestsInBcContainer`, orchestrate publish-test-app + Test Runner codeunit, parse XML results. Open question: can the VS Code Test Explorer LSP command be driven programmatically from outside VS Code?
- **`bc-debug` skill + `bc-troubleshoot` MCP wiring.** Determine whether `almcp.al_debug` needs a VS Code host. If yes, shim it; if no, auto-enable the `bc-troubleshoot` HTTP MCP in `.mcp.json` when a session is paused. Resolve auth scheme for the `/mcp` endpoint.
- **`bc-e2e` skill.** Port page scripting from the old agent; adapt for the new architecture.

**Symbol-lookup enhancements:**

- **Cross-app dependency walking.** `bc_find_extenders_of("Sales Header")` — requires tracking TableExtension, PageExtension, event subscribers during indexing.
- **XML-doc / caption / tooltip extraction.**
- **Full source retrieval.** Expose inner-zip `src/*.al` when present.
- **Compiled implementation.** Consider rewriting the MCP server in C#/.NET if profiling shows PowerShell parsing is too slow.

**Bootstrap & environment:**

- Multi-project workspace support
- Headless CI mode (no prompts)
- Cross-plugin `.mcp.json` conflict detection

**Container lifecycle:**

- Container pooling / reuse
- `/bc-container clean` cleanup command
- Cloud sandbox targeting (publish/test against online sandboxes)

**Agent quality:**

- Eval harness for the `bc-developer` subagent
- Automatic CLAUDE.md object ID registry maintenance

**Known unknowns to resolve before v2:**

- Auth scheme for the BC-server-hosted `/mcp` HTTP endpoint (basic/AAD/session — unknown from research)
- Whether `almcp.al_debug` operates without a VS Code debug adapter host
- Exact route the embedded `ModelContextProtocol.AspNetCore` uses inside `almcp` (was 404 on `/mcp` during the research probe)

---

## Appendix — research findings referenced in this design

Two research passes were conducted during brainstorming. Key findings:

**Pass 1: AL extension programmatic surface.**

- AL toolchain lives at `~/.vscode/extensions/ms-dynamics-smb.al-<version>/bin/win32/` — `alc.exe`, `altool.exe`, `almcp.exe`, `almcp.dll`, `Microsoft.Dynamics.Nav.LanguageModelTools.dll`.
- `altool.exe launchmcpserver <project>` starts a stdio MCP server exposing ~15 language model tools including `al_build`, `al_compile`, `al_publish`, `al_downloadsymbols`, `al_debug`, `al_setbreakpoint`, `al_getdiagnostics`. This is the primary integration point.
- The BC-server-hosted Troubleshooting MCP is an HTTP endpoint at `/mcp` on `mcpServicePort`, gated by `alExtensionActive && inDebugMode`. Reachable by any MCP client that knows the port.
- `.app` files are 40-byte-prefixed zips. v28 apps are Ready2Run wrappers with a second 40-byte-prefixed zip inside. Innermost zip contains `SymbolReference.json` plus `src/*.al`.
- `SymbolReference.json` in v28 uses a nested `Namespaces` tree; object kinds (`Tables`, `Pages`, `Codeunits`, etc.) live inside namespace nodes, not at root.

**Pass 2: `al_downloadsymbols` detail.**

- Two tools with the same name exist: the VS Code LM tool (parameterless wrapper around `al.downloadSymbols` command) and the standalone `almcp` tool (rich parameters: `globalSourcesOnly`, `force`, `noCache`, `serverUrl`, `tenant`, `environmentName`, `useInteractiveLogin`).
- The `almcp` variant with `globalSourcesOnly=true` downloads `.app` symbol packages from Microsoft/AppSource without a server, container, or auth. This is what the plugin delegates to for artifact-free symbol provisioning.
- Target versions are read from `app.json` (`platform`, `application`, `dependencies[].version`) — no explicit version parameter.
- The tool writes to `.alpackages/` and honors existing files unless `force=true`. It does not reuse `bcartifacts.cache`.
- `al_downloadsymbols` fetches compiled `.app` symbol packages only, not full BC artifacts (platform DLLs, base-app source, test toolkit). Container mode remains the path for anything beyond symbols.
