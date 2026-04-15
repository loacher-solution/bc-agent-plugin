#requires -Version 5.1
<#
write-mcp-config.ps1 — Write or merge .mcp.json in the BC project root with entries
for almcp (Microsoft's MCP server via altool.exe launchmcpserver) and bc-symbols (ours).

Also writes .bc-agent/mcp-troubleshoot.template.json as a v2 template for the
BC-server-hosted Troubleshooting MCP endpoint.

Creates CLAUDE.md if missing; never overwrites an existing one.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ProjectRoot,
    [Parameter(Mandatory)] [string] $AlToolsPath,
    [Parameter(Mandatory)] [string] $PluginRoot
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([string]$Status, [string]$Message)
    [pscustomobject]@{ status=$Status; message=$Message } | ConvertTo-Json -Compress
}

if (-not (Test-Path $ProjectRoot)) {
    Write-Result -Status 'error' -Message "Project root does not exist: $ProjectRoot"
    exit 1
}

$altoolExe = [IO.Path]::Combine($AlToolsPath, 'altool.exe')
$bcSymbolsScript = [IO.Path]::Combine($PluginRoot, 'skills', 'bc-symbol-lookup', 'server', 'bc-symbol-mcp.ps1')
$mcpJsonPath = Join-Path $ProjectRoot '.mcp.json'
$bcAgentDir = Join-Path $ProjectRoot '.bc-agent'
$troubleshootTemplatePath = Join-Path $bcAgentDir 'mcp-troubleshoot.template.json'
$claudeMdPath = Join-Path $ProjectRoot 'CLAUDE.md'

# Load existing .mcp.json or start fresh
if (Test-Path $mcpJsonPath) {
    try {
        $existing = Get-Content $mcpJsonPath -Raw | ConvertFrom-Json
    } catch {
        Write-Result -Status 'error' -Message "Existing .mcp.json is not valid JSON: $($_.Exception.Message)"
        exit 1
    }
    if (-not $existing.PSObject.Properties['mcpServers']) {
        $existing | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force
    }
} else {
    $existing = [pscustomobject]@{ mcpServers = [pscustomobject]@{} }
}

# Build the almcp entry
$almcpEntry = [pscustomobject]@{
    command = $altoolExe
    args    = @('launchmcpserver', $ProjectRoot)
}

# Build the bc-symbols entry
$alpackages = Join-Path $ProjectRoot '.alpackages'
$bcSymbolsEntry = [pscustomobject]@{
    command = 'pwsh'
    args    = @('-NoProfile', '-File', $bcSymbolsScript, '-PackageCachePath', $alpackages)
}

# Merge (overwrite almcp and bc-symbols; leave other servers alone)
if ($existing.mcpServers.PSObject.Properties['almcp']) {
    $existing.mcpServers.PSObject.Properties.Remove('almcp')
}
$existing.mcpServers | Add-Member -NotePropertyName 'almcp' -NotePropertyValue $almcpEntry -Force

if ($existing.mcpServers.PSObject.Properties['bc-symbols']) {
    $existing.mcpServers.PSObject.Properties.Remove('bc-symbols')
}
$existing.mcpServers | Add-Member -NotePropertyName 'bc-symbols' -NotePropertyValue $bcSymbolsEntry -Force

# Write .mcp.json
$existing | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpJsonPath -Encoding UTF8

# Write .bc-agent/mcp-troubleshoot.template.json
New-Item -ItemType Directory -Force -Path $bcAgentDir | Out-Null
$troubleshootTemplate = [pscustomobject]@{
    '_comment'       = 'Template for v2 BC-server-hosted Troubleshooting MCP. Not registered automatically in v1.'
    'bc-troubleshoot' = [pscustomobject]@{
        type = 'http'
        url  = 'http://localhost:7049/mcp'
        '_note' = 'Port is the BC Server API port. Only reachable while a debug session is paused. Auth scheme TBD in v2.'
    }
}
$troubleshootTemplate | ConvertTo-Json -Depth 10 | Set-Content -Path $troubleshootTemplatePath -Encoding UTF8

# Create CLAUDE.md only if missing
if (-not (Test-Path $claudeMdPath)) {
    $claudeMd = @"
# Project: Business Central AL extension

This project is set up to work with the ``bc-agent-plugin`` Claude Code plugin.

## Preferred workflow

- For any BC development task, delegate to the ``bc-developer`` subagent via the ``/bc`` slash command.
- The agent uses the ``almcp`` MCP server for compile, publish, download-symbols, and debug.
- The agent uses the ``bc-symbols`` MCP server for offline object/field/procedure lookup against ``.alpackages/``.

## Conventions

- Target: Business Central 2026 W1 (v28+)
- Language: English for code, comments, commits.
- Object ID range: see ``app.json`` ``idRanges``.

## Object ID Registry

The ``bc-developer`` subagent maintains this table. Add rows as you create objects.

| ID | Type | Name | File |
|----|------|------|------|
|    |      |      |      |
"@
    $claudeMd | Set-Content -Path $claudeMdPath -Encoding UTF8
}

Write-Result -Status 'ok' -Message "Wrote $mcpJsonPath and $troubleshootTemplatePath"
exit 0
