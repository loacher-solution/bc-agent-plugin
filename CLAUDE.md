# bc-agent-plugin

A Claude Code plugin for Business Central AL development.

## Critical constraints

- **Target: BC 2026 W1 (v28+) only.** Do not design for, test against, or support legacy BC versions. The plugin depends on `altool.exe launchmcpserver` (the `almcp` stdio MCP server) and the v28 `SymbolReference.json` namespace-nested format, neither of which exists in older versions.
- **Windows only.** BC is Windows-only; the plugin uses PowerShell, .NET `System.IO.Compression`, and BcContainerHelper. No cross-platform support.
- **PowerShell 5.1** for bootstrap scripts (stock Windows). **PowerShell 7** (`pwsh`) for the `bc-symbols` MCP server and tests.

## Architecture rules

- **Skills are thin.** Anything Microsoft already does (compile, publish, debug, symbol download) is delegated to `almcp`. Do not reimplement.
- **Never guess object IDs, field names, or procedure signatures.** The `bc-symbols` MCP server exists to look these up from `.app` files offline. Use it.
- **`bc-symbols` is read-only.** No network, no server calls, no compiler invocations. Pure projection over `.app` files on disk.

## Key paths

- `skills/bc-symbol-lookup/server/` — the bc-symbols stdio MCP server (PowerShell 7)
- `skills/bc-bootstrap/scripts/` — toolchain resolver, vsix downloader, .mcp.json writer
- `skills/bc-container/scripts/` — BcContainerHelper wrappers
- `agents/bc-developer.md` — the shared subagent prompt (~300 lines)
- `docs/roadmap.md` — v0.1.1 follow-ups and v2 deferred work
- `docs/superpowers/specs/` — design spec
- `docs/superpowers/plans/` — implementation plans A–E

## Commands

```bash
# Run all tests
pwsh -NoProfile -Command "Invoke-Pester -Path tests -Output Detailed"

# Run tests for one skill
pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup -Output Detailed"

# Regenerate test fixtures
pwsh -NoProfile -File tests/bc-symbol-lookup/Make-Fixtures.ps1
```

## Conventions

- Language: English for everything (code, comments, commits)
- Commit style: conventional commits (`feat`, `fix`, `test`, `docs`, `chore`)
- Parameter naming: use `$ToolArgs` not `$Args` (PowerShell automatic variable collision)
- Test framework: Pester 5.x
