#requires -Version 5.1
<#
ensure-pwsh7.ps1 — Verify PowerShell 7 is available on PATH (so `pwsh` launches).
The bc-symbols MCP server requires pwsh 7. If missing, emit an actionable message.

Output: JSON { status, pwshPath, message }
#>
[CmdletBinding()]
param()

function Write-Result {
    param([string]$Status, [string]$PwshPath, [string]$Message)
    [pscustomobject]@{ status=$Status; pwshPath=$PwshPath; message=$Message } | ConvertTo-Json -Compress
}

try {
    $cmd = Get-Command pwsh -ErrorAction Stop
    $version = & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>$null
    if ($LASTEXITCODE -eq 0 -and [int]$version -ge 7) {
        Write-Result -Status 'ok' -PwshPath $cmd.Source -Message "PowerShell $version detected at $($cmd.Source)"
        exit 0
    }
    Write-Result -Status 'outdated' -PwshPath $cmd.Source -Message "pwsh found but version is $version (need >= 7). Install: winget install --id Microsoft.PowerShell --source winget"
    exit 1
} catch {
    Write-Result -Status 'missing' -PwshPath '' -Message "PowerShell 7 (pwsh) not found. Install: winget install --id Microsoft.PowerShell --source winget"
    exit 1
}
