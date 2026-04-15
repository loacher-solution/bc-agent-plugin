---
description: Delegate a Business Central AL development task to the bc-developer subagent.
---

Delegate this task to the `bc-developer` subagent:

$ARGUMENTS

The subagent knows the BC toolchain (almcp MCP server, bc-symbols MCP server, BcContainerHelper) and will look up any standard or third-party BC objects via bc-symbols before editing code. It will compile via `al_build` and report structured diagnostics.
