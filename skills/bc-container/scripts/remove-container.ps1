#requires -Version 5.1
<#
remove-container.ps1 — Remove a BC container and clean up project metadata and
credential files.

Output JSON: { status, message }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ProjectRoot,
    [string] $ContainerName,
    [string] $CredentialStoreRoot = (Join-Path $env:LOCALAPPDATA 'bc-agent-plugin\containers')
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([string]$Status, [string]$Message)
    [pscustomobject]@{ status=$Status; message=$Message } | ConvertTo-Json -Compress
}

$metadataPath = Join-Path $ProjectRoot '.bc-agent/container.json'

if (-not $ContainerName) {
    if (Test-Path $metadataPath) {
        try {
            $meta = Get-Content $metadataPath -Raw | ConvertFrom-Json
            $ContainerName = $meta.name
        } catch {
            Write-Result -Status 'error' -Message "Could not read container name from $metadataPath"
            exit 1
        }
    } else {
        Write-Result -Status 'error' -Message "No -ContainerName given and no .bc-agent/container.json found"
        exit 1
    }
}

if (-not (Get-Module -ListAvailable BcContainerHelper)) {
    Write-Result -Status 'error' -Message "BcContainerHelper module not installed"
    exit 1
}
Import-Module BcContainerHelper -Force

try {
    Remove-BcContainer -containerName $ContainerName
} catch {
    Write-Result -Status 'error' -Message "Remove-BcContainer failed: $($_.Exception.Message)"
    exit 1
}

Remove-Item $metadataPath -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $CredentialStoreRoot "$ContainerName.json") -Force -ErrorAction SilentlyContinue

Write-Result -Status 'ok' -Message "Removed container $ContainerName and cleaned up metadata"
exit 0
