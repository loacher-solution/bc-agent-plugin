#requires -Version 5.1
<#
new-container.ps1 — Create a Business Central container via BcContainerHelper and
write project-local metadata.

Steps:
  1. Generate a random password, save credentials to $CredentialStoreRoot/<name>.json
     with Windows ACLs restricted to the current user.
  2. Call Get-BcArtifactUrl to resolve the target version to a download URL.
  3. Call New-BcContainer with sensible defaults.
  4. Write $ProjectRoot/.bc-agent/container.json with container metadata.

DryRun mode: skips the BcContainerHelper calls (useful for unit tests) but still
writes credential + metadata files so tests can assert on their shape.

Output JSON: { status, name, metadataPath, message }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ProjectRoot,
    [Parameter(Mandatory)] [string] $ContainerName,
    [Parameter(Mandatory)] [string] $Platform,
    [Parameter(Mandatory)] [string] $Application,
    [string] $Country = 'w1',
    [string] $CredentialStoreRoot = (Join-Path $env:LOCALAPPDATA 'bc-agent-plugin\containers'),
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([string]$Status, [string]$Name, [string]$MetadataPath, [string]$Message)
    [pscustomobject]@{
        status       = $Status
        name         = $Name
        metadataPath = $MetadataPath
        message      = $Message
    } | ConvertTo-Json -Compress
}

function New-RandomPassword {
    param([int]$Length = 20)
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$'.ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

New-Item -ItemType Directory -Force -Path $CredentialStoreRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot '.bc-agent') | Out-Null

$username = 'admin'
$password = New-RandomPassword -Length 20
$credPath = Join-Path $CredentialStoreRoot "$ContainerName.json"

[pscustomobject]@{
    username     = $username
    password     = $password
    containerName = $ContainerName
    createdAt    = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content -Path $credPath -Encoding UTF8

try {
    icacls $credPath /inheritance:r | Out-Null
    icacls $credPath /grant:r "$($env:USERNAME):F" | Out-Null
} catch {
    Write-Warning "Could not set restrictive ACLs on $credPath - proceeding anyway"
}

$metadataPath = Join-Path $ProjectRoot '.bc-agent/container.json'

if ($DryRun) {
    $artifactUrl = "https://fakeartifact.local/$Platform/$Country"
    $apiPort = 7049
} else {
    if (-not (Get-Module -ListAvailable BcContainerHelper)) {
        Write-Result -Status 'error' -Name $ContainerName -MetadataPath '' -Message "BcContainerHelper module is not installed. Run: Install-Module BcContainerHelper -Scope CurrentUser -Force"
        exit 1
    }
    Import-Module BcContainerHelper -Force

    $artifactUrl = Get-BcArtifactUrl -type Sandbox -country $Country -version $Platform -select Latest
    if (-not $artifactUrl) {
        Write-Result -Status 'error' -Name $ContainerName -MetadataPath '' -Message "Could not resolve BC artifact URL for platform $Platform country $Country"
        exit 1
    }

    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

    try {
        New-BcContainer `
            -accept_eula `
            -accept_outdated `
            -containerName $ContainerName `
            -artifactUrl $artifactUrl `
            -auth NavUserPassword `
            -Credential $credential `
            -includeAL `
            -includeTestToolkit `
            -updateHosts
    } catch {
        Write-Result -Status 'error' -Name $ContainerName -MetadataPath '' -Message "New-BcContainer failed: $($_.Exception.Message)"
        exit 1
    }

    $apiPort = 7049
}

[pscustomobject]@{
    name            = $ContainerName
    platform        = $Platform
    application     = $Application
    country         = $Country
    artifactUrl     = $artifactUrl
    credentialsFile = $credPath
    apiPort         = $apiPort
    createdAt       = (Get-Date).ToString('o')
    dryRun          = [bool]$DryRun
} | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataPath -Encoding UTF8

Write-Result -Status 'ok' -Name $ContainerName -MetadataPath $metadataPath -Message "Container ready"
exit 0
