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
/plugin marketplace add https://github.com/loacher-solution/bc-agent-plugin
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
