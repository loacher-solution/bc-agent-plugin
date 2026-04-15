#requires -Version 5.1
<#
verify-docker.ps1 — Check that Docker Desktop is running and responding.

Output JSON: { "status": "ok"|"not-running"|"not-installed", "message": "..." }
#>
[CmdletBinding()]
param()

function Write-Result {
    param([string]$Status, [string]$Message)
    [pscustomobject]@{ status=$Status; message=$Message } | ConvertTo-Json -Compress
}

try {
    $null = Get-Command docker -ErrorAction Stop
} catch {
    Write-Result -Status 'not-installed' -Message "docker CLI not found on PATH. Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    exit 1
}

$info = & docker info 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Result -Status 'ok' -Message "Docker is running"
    exit 0
}

Write-Result -Status 'not-running' -Message "docker CLI is installed but 'docker info' failed. Start Docker Desktop and retry. Raw error: $info"
exit 1
