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

## v0.1.1 follow-ups (from final review)

- **`FileSystemWatcher` re-index** in `bc-symbol-lookup` — currently indexes once at startup; document now says restart-only. Implementing the watcher unblocks mid-session symbol downloads.
- **`bc_search` over captions** — currently ranks by object name only; spec says "names and captions."
- **`McpServer.ps1` `continue` inside `switch`** — currently harmless (only used in the unknown-tool path) but the construct exits the switch, not the loop. Restructure before adding post-switch logic.
- **`bc_get_object_source` `objectId` parameter** — v1 stub ignores it. Wire it in when v2 actually returns source.
- ~~**Replace `TODO-org` GitHub URLs** — done, now points at `loacher-solution`.~~

## Agent quality

- Eval harness for the `bc-developer` subagent — a set of "can the agent correctly add feature X" scenarios, run automatically against new versions of the prompt.
- Automatic `CLAUDE.md` object ID registry maintenance — a hook that updates the ID table after every successful compile.
