#requires -Version 5.1
<#
read-bc-version.ps1 — Extract platform and application target versions from app.json.

Output JSON:
  { "status": "ok"|"missing-versions"|"not-found"|"error",
    "platform":    "28.0.0.0",
    "application": "28.0.0.0",
    "message":     "..." }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AppJsonPath
)

function Write-Result {
    param([string]$Status, [string]$Platform, [string]$Application, [string]$Message)
    [pscustomobject]@{
        status      = $Status
        platform    = $Platform
        application = $Application
        message     = $Message
    } | ConvertTo-Json -Compress
}

if (-not (Test-Path $AppJsonPath)) {
    Write-Result -Status 'not-found' -Platform '' -Application '' -Message "app.json not found at $AppJsonPath"
    exit 1
}

try {
    $app = Get-Content $AppJsonPath -Raw | ConvertFrom-Json
} catch {
    Write-Result -Status 'error' -Platform '' -Application '' -Message "Parse error: $($_.Exception.Message)"
    exit 1
}

$platform    = if ($app.PSObject.Properties['platform'])    { [string]$app.platform }    else { '' }
$application = if ($app.PSObject.Properties['application']) { [string]$app.application } else { '' }

if (-not $platform -or -not $application) {
    Write-Result -Status 'missing-versions' -Platform $platform -Application $application -Message "app.json is missing 'platform' and/or 'application' fields. Set them to the target BC version (e.g., '28.0.0.0')."
    exit 1
}

Write-Result -Status 'ok' -Platform $platform -Application $application -Message "Versions read successfully"
exit 0
