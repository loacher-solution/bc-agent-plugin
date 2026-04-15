#requires -Version 5.1
<#
copy-test-toolkit-symbols.ps1 — After `New-BcContainer -includeTestToolkit` has run,
copy the Test Toolkit .app files (Test Runner, Test Framework, Library Assert,
Library Variable Storage, System Application Test Library, Any, etc.) out of the
container and into the project's .alpackages folder so the AL compiler can resolve
them for test project builds.

Output JSON: { status, copied: [filename, ...], message }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ProjectRoot,
    [Parameter(Mandatory)] [string] $ContainerName
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([string]$Status, [array]$Copied, [string]$Message)
    [pscustomobject]@{
        status  = $Status
        copied  = $Copied
        message = $Message
    } | ConvertTo-Json -Depth 5 -Compress
}

if (-not (Get-Module -ListAvailable BcContainerHelper)) {
    Write-Result -Status 'error' -Copied @() -Message "BcContainerHelper module not installed"
    exit 1
}
Import-Module BcContainerHelper -Force

$alpackages = Join-Path $ProjectRoot '.alpackages'
New-Item -ItemType Directory -Force -Path $alpackages | Out-Null

$targetNames = @(
    'Test Runner',
    'Any',
    'Library Assert',
    'Library Variable Storage',
    'Test Framework',
    'System Application Test Library',
    'Base Application Test Library'
)

$copied = @()
try {
    # BcContainerHelper exposes Get-BcContainerAppInfo which lists published apps
    # and Get-BcContainerApp which can extract an app's .app file
    $apps = Get-BcContainerAppInfo -containerName $ContainerName -symbolsOnly -ErrorAction Stop
} catch {
    Write-Result -Status 'error' -Copied @() -Message "Could not query apps in container $ContainerName`: $($_.Exception.Message)"
    exit 1
}

foreach ($app in $apps) {
    if ($targetNames -contains $app.Name) {
        try {
            Get-BcContainerApp -containerName $ContainerName `
                -appName $app.Name -publisher $app.Publisher `
                -appVersion $app.Version -appFile (Join-Path $alpackages ("{0}_{1}_{2}.app" -f $app.Publisher, $app.Name, $app.Version)) `
                -ErrorAction Stop | Out-Null
            $copied += ("{0}_{1}_{2}.app" -f $app.Publisher, $app.Name, $app.Version)
        } catch {
            Write-Warning "Could not copy $($app.Name): $($_.Exception.Message)"
        }
    }
}

Write-Result -Status 'ok' -Copied $copied -Message "Copied $($copied.Count) test toolkit apps to $alpackages"
exit 0
