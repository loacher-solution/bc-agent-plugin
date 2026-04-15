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
