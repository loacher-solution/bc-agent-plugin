#requires -Version 7.0
<#
McpServer.ps1 — Minimal stdio JSON-RPC 2.0 loop for the MCP protocol.

Supported methods:
  - initialize
  - tools/list
  - tools/call

Protocol framing: one JSON-RPC message per line on stdin, one response per line on stdout.
Full MCP spec uses Content-Length framing for HTTP; Claude Code's stdio MCP clients also
accept newline-delimited JSON. We write newline-delimited.

Errors go to stderr (visible to the agent's tool output) and also become structured
error responses.
#>

function Start-McpServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [Parameter(Mandatory)] [hashtable] $ToolDispatch,
        [Parameter(Mandatory)] [array] $ToolSchemas
    )

    while ($true) {
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $msg = $line | ConvertFrom-Json -Depth 20
        } catch {
            _WriteError -Id $null -Code -32700 -Message "Parse error: $($_.Exception.Message)"
            continue
        }

        $id = if ($msg.PSObject.Properties['id']) { $msg.id } else { $null }
        $method = $msg.method

        try {
            switch ($method) {
                'initialize' {
                    _WriteResult -Id $id -Result @{
                        protocolVersion = '2024-11-05'
                        capabilities = @{ tools = @{} }
                        serverInfo = @{ name = 'bc-symbols'; version = '0.1.0' }
                    }
                }
                'tools/list' {
                    _WriteResult -Id $id -Result @{ tools = $ToolSchemas }
                }
                'tools/call' {
                    $toolName = $msg.params.name
                    $argsObj  = $msg.params.arguments
                    if (-not $ToolDispatch.ContainsKey($toolName)) {
                        _WriteError -Id $id -Code -32601 -Message "Unknown tool: $toolName"
                        continue
                    }
                    $toolArgsHash = @{}
                    if ($argsObj) {
                        $argsObj.PSObject.Properties | ForEach-Object { $toolArgsHash[$_.Name] = $_.Value }
                    }
                    $handler = $ToolDispatch[$toolName]
                    $result = & $handler -Index $Index -ToolArgs $toolArgsHash
                    $content = @(
                        @{ type = 'text'; text = ($result | ConvertTo-Json -Depth 20 -Compress) }
                    )
                    _WriteResult -Id $id -Result @{ content = $content }
                }
                default {
                    _WriteError -Id $id -Code -32601 -Message "Unknown method: $method"
                }
            }
        } catch {
            _WriteError -Id $id -Code -32603 -Message "Internal error: $($_.Exception.Message)"
            [Console]::Error.WriteLine("ERROR handling $method`: $($_.Exception.Message)")
        }
    }
}

function _WriteResult {
    param($Id, $Result)
    $obj = @{
        jsonrpc = '2.0'
        id      = $Id
        result  = $Result
    }
    [Console]::Out.WriteLine(($obj | ConvertTo-Json -Depth 20 -Compress))
    [Console]::Out.Flush()
}

function _WriteError {
    param($Id, [int]$Code, [string]$Message)
    $obj = @{
        jsonrpc = '2.0'
        id      = $Id
        error   = @{ code = $Code; message = $Message }
    }
    [Console]::Out.WriteLine(($obj | ConvertTo-Json -Depth 20 -Compress))
    [Console]::Out.Flush()
}
