---
name: bc-symbol-lookup
description: Offline Business Central symbol lookup via a local MCP server. Provides bc_find_object, bc_get_fields, bc_get_procedures, bc_search, and bc_list_apps tools that parse .app files in the project's .alpackages/ folder. Use this instead of guessing object IDs, field names, or procedure signatures.
---

# bc-symbol-lookup

This skill is a **local stdio MCP server** that parses Business Central `.app` files offline and answers object/field/procedure queries. Register it in your project's `.mcp.json` — `bc-bootstrap` does this automatically.

## When to use

Whenever you need to know something about a BC object — your own, a BC standard object, or a third-party extension — before referencing it in AL code. Examples:

- "What fields does the Customer table have?" → `bc_get_fields`
- "What's the signature of `Sales-Post.Run`?" → `bc_get_procedures`
- "Is there an object called Vendor Card?" → `bc_find_object`
- "Find everything with 'Item' in the name" → `bc_search`
- "Which apps are currently indexed?" → `bc_list_apps`

## Hard rule

**Never guess an object ID, field name, or procedure signature. Look it up first.**

If a field, procedure, or object you need isn't in the index, the project's `.alpackages/` is missing that app's symbols. Call `al_downloadsymbols` via the `almcp` MCP server with `globalSourcesOnly=true` to pull them, then re-run your lookup.

## How it works

The server strips the 40-byte header from each `.app` file, detects Ready2Run wrappers and unwraps the inner `.app` (whose location varies across BC versions — we search any `.app` entry inside the outer zip), extracts `SymbolReference.json`, and walks the recursive `Namespaces` tree to build a flat in-memory index. Re-indexing runs on demand when `.alpackages/` changes.

Object kinds handled: Table, TableExtension, Page, PageExtension, Codeunit, Report, ReportExtension, Query, XmlPort, Enum (both `Enums` and `EnumTypes` JSON shapes), EnumExtension, Interface, ControlAddIn, PermissionSet.

The server is pure read-only — it never touches the network, never calls a BC server, never runs the AL compiler.

## Registered via

```json
"bc-symbols": {
  "command": "pwsh",
  "args": ["-NoProfile", "-File", "<plugin>/skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1",
           "-PackageCachePath", "${workspaceFolder}/.alpackages"]
}
```
