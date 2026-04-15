#requires -Version 7.0
<#
bc-symbol-mcp.ps1 — Entry point for the bc-symbols stdio MCP server.

Invoked by Claude Code via .mcp.json:
  "bc-symbols": {
    "command": "pwsh",
    "args": ["-NoProfile", "-File", "<plugin>/skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1",
             "-PackageCachePath", "${workspaceFolder}/.alpackages"]
  }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PackageCachePath
)

$ErrorActionPreference = 'Stop'
# Route PowerShell warnings to stderr (not stdout) so they can't pollute JSON-RPC output.
$WarningPreference = 'SilentlyContinue'

. "$PSScriptRoot/lib/AppFileReader.ps1"
. "$PSScriptRoot/lib/SymbolIndex.ps1"
. "$PSScriptRoot/lib/Tools.ps1"
. "$PSScriptRoot/lib/McpServer.ps1"

[Console]::Error.WriteLine("bc-symbols: indexing $PackageCachePath ...")
$index = New-SymbolIndex -PackageCachePath $PackageCachePath
[Console]::Error.WriteLine("bc-symbols: indexed $($index.Apps.Count) apps, $($index.Objects.Count) objects")

$dispatch = @{
    'bc_find_object'        = { param($Index, $ToolArgs) Invoke-BcFindObjectTool        -Index $Index -ToolArgs $ToolArgs }
    'bc_get_fields'         = { param($Index, $ToolArgs) Invoke-BcGetFieldsTool         -Index $Index -ToolArgs $ToolArgs }
    'bc_get_procedures'     = { param($Index, $ToolArgs) Invoke-BcGetProceduresTool     -Index $Index -ToolArgs $ToolArgs }
    'bc_get_object_source'  = { param($Index, $ToolArgs) Invoke-BcGetObjectSourceTool   -Index $Index -ToolArgs $ToolArgs }
    'bc_search'             = { param($Index, $ToolArgs) Invoke-BcSearchTool            -Index $Index -ToolArgs $ToolArgs }
    'bc_list_apps'          = { param($Index, $ToolArgs) Invoke-BcListAppsTool          -Index $Index -ToolArgs $ToolArgs }
}

$schemas = @(
    @{
        name        = 'bc_find_object'
        description = 'Find a Business Central object (Table, Page, Codeunit, etc.) by name. Supports wildcards.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                name = @{ type = 'string'; description = "Object name (exact or wildcard like 'Sales*')" }
                type = @{ type = 'string'; description = "Optional: Table, Page, Codeunit, Enum, Interface, Report, Query, XmlPort, TableExtension, PageExtension" }
            }
            required   = @('name')
        }
    },
    @{
        name        = 'bc_get_fields'
        description = 'Get the fields of a Table or TableExtension, with optional substring filter.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                objectName = @{ type = 'string' }
                objectId   = @{ type = 'integer' }
                type       = @{ type = 'string'; enum = @('Table', 'TableExtension') }
                filter     = @{ type = 'string'; description = 'Optional substring filter on field name' }
            }
            required   = @('type')
        }
    },
    @{
        name        = 'bc_get_procedures'
        description = 'Get the procedures of a Codeunit, Page, or other procedure-bearing object.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                objectName = @{ type = 'string' }
                objectId   = @{ type = 'integer' }
                type       = @{ type = 'string' }
                filter     = @{ type = 'string'; description = 'Optional substring filter on procedure name' }
            }
            required   = @('type')
        }
    },
    @{
        name        = 'bc_get_object_source'
        description = 'Get the AL source of an object, if present in the .app package. v1: returns null with a reason.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                objectName = @{ type = 'string' }
                objectId   = @{ type = 'integer' }
                type       = @{ type = 'string' }
            }
            required   = @('type')
        }
    },
    @{
        name        = 'bc_search'
        description = 'Free-text search across object names, ranked by match quality.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                query = @{ type = 'string' }
                limit = @{ type = 'integer'; description = 'Max results, default 25' }
            }
            required   = @('query')
        }
    },
    @{
        name        = 'bc_list_apps'
        description = 'List all indexed .app files in the current package cache.'
        inputSchema = @{
            type       = 'object'
            properties = @{}
        }
    }
)

Start-McpServer -Index $index -ToolDispatch $dispatch -ToolSchemas $schemas
