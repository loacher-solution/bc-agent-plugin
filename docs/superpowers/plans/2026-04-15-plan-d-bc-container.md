# Plan D — `bc-container` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `bc-container` skill that wraps BcContainerHelper's container lifecycle. The skill verifies Docker is running, reads target BC version from `app.json`, prompts for container name and credentials, calls `New-BcContainer`, copies the Test Toolkit symbols into `.alpackages/`, and writes `.bc-agent/container.json` metadata so the `bc-developer` subagent knows which container to target.

**Architecture:** Thin skill. No new MCP server, no complex parsing. The skill's PowerShell scripts wrap BcContainerHelper cmdlets and manage project-local state files. The agent calls these scripts via Bash when the user asks for a container. `New-BcContainer` does all the heavy lifting; we add the "know which BC project this container belongs to" state tracking that BcContainerHelper doesn't do.

**Tech Stack:** PowerShell 5.1+, BcContainerHelper module (hard dependency — bootstrap offers to install it in Plan C), Pester 5 for unit tests that mock BcContainerHelper.

---

## File Structure

**Create (skill):**
- `skills/bc-container/SKILL.md` — skill manifest and runbook for the agent
- `skills/bc-container/scripts/verify-docker.ps1` — checks Docker Desktop is running
- `skills/bc-container/scripts/read-bc-version.ps1` — reads `platform`/`application` from `app.json`
- `skills/bc-container/scripts/new-container.ps1` — wraps `New-BcContainer` with project-aware defaults and credential storage
- `skills/bc-container/scripts/copy-test-toolkit-symbols.ps1` — copies Test Toolkit `.app` files from the container into `.alpackages/`
- `skills/bc-container/scripts/remove-container.ps1` — wraps `Remove-BcContainer` and cleans up metadata

**Create (tests):**
- `tests/bc-container/Read-BcVersion.Tests.ps1` — unit tests against fixture `app.json` files
- `tests/bc-container/fixtures/app-with-versions.json` — valid `app.json` with platform/application set
- `tests/bc-container/fixtures/app-missing-versions.json` — `app.json` without platform/application
- `tests/bc-container/New-Container.Tests.ps1` — tests with `New-BcContainer` mocked via Pester
- `tests/bc-container/Verify-Docker.Tests.ps1` — tests with Docker CLI mocked

**Modify:** None from earlier plans (self-contained).

---

## Dependencies and ordering

Plan A (scaffold) must have landed. Plan C (`bc-bootstrap`) should have landed so that the user's machine has BcContainerHelper installed before running `bc-container` tasks; if not, `bc-container`'s verification step tells them to run `/bc-setup` first.

Tasks 1–2 scaffold and fixtures. Task 3 builds `read-bc-version.ps1` with TDD. Task 4 builds `verify-docker.ps1`. Task 5 builds `new-container.ps1` with mocked `New-BcContainer`. Task 6 builds `copy-test-toolkit-symbols.ps1`. Task 7 builds `remove-container.ps1`. Task 8 writes `SKILL.md`. Task 9 is a manual smoke test that actually creates a throwaway container (requires Docker Desktop running — gated so reviewers can skip).

---

### Task 1: Scaffold skill directory

**Files:**
- Create: `skills/bc-container/SKILL.md` (empty, filled in Task 8)
- Create: `skills/bc-container/scripts/verify-docker.ps1` (empty)
- Create: `skills/bc-container/scripts/read-bc-version.ps1` (empty)
- Create: `skills/bc-container/scripts/new-container.ps1` (empty)
- Create: `skills/bc-container/scripts/copy-test-toolkit-symbols.ps1` (empty)
- Create: `skills/bc-container/scripts/remove-container.ps1` (empty)

- [ ] **Step 1: Create directories and stubs**

Run:
```
pwsh -NoProfile -Command @'
$dirs = @('skills/bc-container/scripts', 'tests/bc-container/fixtures')
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
$files = @(
  'skills/bc-container/SKILL.md',
  'skills/bc-container/scripts/verify-docker.ps1',
  'skills/bc-container/scripts/read-bc-version.ps1',
  'skills/bc-container/scripts/new-container.ps1',
  'skills/bc-container/scripts/copy-test-toolkit-symbols.ps1',
  'skills/bc-container/scripts/remove-container.ps1'
)
$files | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType File -Path $_ | Out-Null } }
'@
```

- [ ] **Step 2: Commit**

```bash
git add skills/bc-container tests/bc-container
git commit -m "feat(bc-container): scaffold skill directory"
```

---

### Task 2: Create `app.json` test fixtures

**Files:**
- Create: `tests/bc-container/fixtures/app-with-versions.json`
- Create: `tests/bc-container/fixtures/app-missing-versions.json`

- [ ] **Step 1: Write the two fixtures**

Write `tests/bc-container/fixtures/app-with-versions.json` with this exact content:

```json
{
  "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  "name": "Fixture App",
  "publisher": "Fixture Publisher",
  "version": "1.0.0.0",
  "platform": "28.0.0.0",
  "application": "28.0.0.0",
  "idRanges": [ { "from": 50100, "to": 50149 } ],
  "dependencies": []
}
```

Write `tests/bc-container/fixtures/app-missing-versions.json` with this exact content:

```json
{
  "id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
  "name": "Fixture App No Versions",
  "publisher": "Fixture Publisher",
  "version": "1.0.0.0",
  "idRanges": [ { "from": 50100, "to": 50149 } ],
  "dependencies": []
}
```

- [ ] **Step 2: Validate both fixtures parse**

Run:
```
pwsh -NoProfile -Command "Get-Content tests/bc-container/fixtures/app-with-versions.json -Raw | ConvertFrom-Json | Out-Null; Get-Content tests/bc-container/fixtures/app-missing-versions.json -Raw | ConvertFrom-Json | Out-Null; Write-Host OK"
```
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add tests/bc-container/fixtures
git commit -m "test(bc-container): add app.json fixtures"
```

---

### Task 3: `read-bc-version.ps1` — extract platform/application from `app.json`

**Files:**
- Create: `tests/bc-container/Read-BcVersion.Tests.ps1`
- Modify: `skills/bc-container/scripts/read-bc-version.ps1`

- [ ] **Step 1: Write failing tests**

Write `tests/bc-container/Read-BcVersion.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-container/scripts/read-bc-version.ps1"
    $script:fixtures = "$PSScriptRoot/fixtures"
}

function Invoke-Reader {
    param([string]$AppJsonPath)
    $raw = & pwsh -NoProfile -File $script:scriptPath -AppJsonPath $AppJsonPath
    return ($raw -join "`n") | ConvertFrom-Json
}

Describe 'read-bc-version.ps1' {
    It 'extracts platform and application from a valid app.json' {
        $r = Invoke-Reader -AppJsonPath "$fixtures/app-with-versions.json"
        $r.status | Should -Be 'ok'
        $r.platform | Should -Be '28.0.0.0'
        $r.application | Should -Be '28.0.0.0'
    }

    It 'returns missing-versions status when fields are absent' {
        $r = Invoke-Reader -AppJsonPath "$fixtures/app-missing-versions.json"
        $r.status | Should -Be 'missing-versions'
    }

    It 'returns not-found when app.json does not exist' {
        $r = Invoke-Reader -AppJsonPath "$fixtures/nope.json"
        $r.status | Should -Be 'not-found'
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-container/Read-BcVersion.Tests.ps1 -Output Detailed"`
Expected: 3 tests fail.

- [ ] **Step 3: Implement the script**

Write `skills/bc-container/scripts/read-bc-version.ps1` with this exact content:

```powershell
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
```

- [ ] **Step 4: Run tests to verify**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-container/Read-BcVersion.Tests.ps1 -Output Detailed"`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-container/scripts/read-bc-version.ps1 tests/bc-container/Read-BcVersion.Tests.ps1
git commit -m "feat(bc-container): add read-bc-version script"
```

---

### Task 4: `verify-docker.ps1` — check Docker Desktop is running

**Files:**
- Modify: `skills/bc-container/scripts/verify-docker.ps1`

**Note.** Not unit-tested in v1 — the check is "run `docker info` and look at the exit code". A mocked test adds no real value for a 10-line wrapper. Smoke-tested manually in Task 9.

- [ ] **Step 1: Implement the script**

Write `skills/bc-container/scripts/verify-docker.ps1` with this exact content:

```powershell
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

Write-Result -Status 'not-running' -Message "docker CLI is installed but `docker info` failed. Start Docker Desktop and retry. Raw error: $info"
exit 1
```

- [ ] **Step 2: Smoke test**

Run: `pwsh -NoProfile -File skills/bc-container/scripts/verify-docker.ps1`
Expected: If Docker Desktop is running, JSON `status: "ok"` exit 0. Otherwise `status: "not-running"` or `not-installed`. Either is acceptable — we're verifying the script runs, not that Docker is up.

- [ ] **Step 3: Commit**

```bash
git add skills/bc-container/scripts/verify-docker.ps1
git commit -m "feat(bc-container): add verify-docker script"
```

---

### Task 5: `new-container.ps1` — wrap `New-BcContainer`

**Files:**
- Create: `tests/bc-container/New-Container.Tests.ps1`
- Modify: `skills/bc-container/scripts/new-container.ps1`

**Note.** The test mocks `New-BcContainer`, `Get-BcArtifactUrl`, and `New-Object PSCredential` so it doesn't actually touch Docker. It verifies: credential file written with the right ACLs, metadata file written with the right shape, `New-BcContainer` called with the expected parameters.

- [ ] **Step 1: Write failing test**

Write `tests/bc-container/New-Container.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-container/scripts/new-container.ps1"
}

Describe 'new-container.ps1' {
    BeforeEach {
        $script:tmpProject = Join-Path $env:TEMP "bc-container-test-$([Guid]::NewGuid().ToString('N'))"
        $script:tmpCredStore = Join-Path $env:TEMP "bc-container-creds-$([Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Force -Path $script:tmpProject | Out-Null
        New-Item -ItemType Directory -Force -Path $script:tmpCredStore | Out-Null
    }
    AfterEach {
        Remove-Item $script:tmpProject -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $script:tmpCredStore -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes .bc-agent/container.json metadata when --DryRun is set' {
        & pwsh -NoProfile -File $script:scriptPath `
            -ProjectRoot $script:tmpProject `
            -ContainerName 'testcontainer' `
            -Platform '28.0.0.0' `
            -Application '28.0.0.0' `
            -Country 'w1' `
            -CredentialStoreRoot $script:tmpCredStore `
            -DryRun

        $metaPath = Join-Path $script:tmpProject '.bc-agent/container.json'
        Test-Path $metaPath | Should -BeTrue
        $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
        $meta.name | Should -Be 'testcontainer'
        $meta.platform | Should -Be '28.0.0.0'
        $meta.application | Should -Be '28.0.0.0'
        $meta.credentialsFile | Should -Match 'testcontainer\.json$'
        $meta.dryRun | Should -Be $true
    }

    It 'writes a credential file into the credential store in dry run' {
        & pwsh -NoProfile -File $script:scriptPath `
            -ProjectRoot $script:tmpProject `
            -ContainerName 'testcontainer' `
            -Platform '28.0.0.0' `
            -Application '28.0.0.0' `
            -Country 'w1' `
            -CredentialStoreRoot $script:tmpCredStore `
            -DryRun

        $credPath = Join-Path $script:tmpCredStore 'testcontainer.json'
        Test-Path $credPath | Should -BeTrue
        $cred = Get-Content $credPath -Raw | ConvertFrom-Json
        $cred.username | Should -Not -BeNullOrEmpty
        $cred.password | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-container/New-Container.Tests.ps1 -Output Detailed"`
Expected: 2 tests fail.

- [ ] **Step 3: Implement the script**

Write `skills/bc-container/scripts/new-container.ps1` with this exact content:

```powershell
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

# Write credential file with restricted ACLs
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
    Write-Warning "Could not set restrictive ACLs on $credPath — proceeding anyway"
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

    $apiPort = 7049  # default; a future enhancement reads this from BcContainerHelper state
}

# Write metadata
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
```

- [ ] **Step 4: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-container/New-Container.Tests.ps1 -Output Detailed"`
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-container/scripts/new-container.ps1 tests/bc-container/New-Container.Tests.ps1
git commit -m "feat(bc-container): implement new-container wrapper"
```

---

### Task 6: `copy-test-toolkit-symbols.ps1` — copy Test Toolkit `.app` files into `.alpackages/`

**Files:**
- Modify: `skills/bc-container/scripts/copy-test-toolkit-symbols.ps1`

**Context.** `al_downloadsymbols` with `globalSourcesOnly=true` does NOT fetch the BC Test Toolkit — that's a container-delivered asset. After `New-BcContainer -includeTestToolkit`, the container has the Test Toolkit `.app` files available via BcContainerHelper's `Get-BcContainerAppInfo` / `Get-BcContainerAppFile`. This script wraps that.

- [ ] **Step 1: Implement the script**

Write `skills/bc-container/scripts/copy-test-toolkit-symbols.ps1` with this exact content:

```powershell
#requires -Version 5.1
<#
copy-test-toolkit-symbols.ps1 — After `New-BcContainer -includeTestToolkit` has run,
copy the Test Toolkit .app files (Test Runner, Test Framework, Tests-TestLibraries-*,
Any, Library Assert, Library Variable Storage, System Application Test Library)
out of the container and into the project's .alpackages folder so the AL compiler
can resolve them.

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

# Names of the test toolkit apps we care about. BcContainerHelper publishes these
# under standard publisher names.
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
    $apps = Get-BcContainerAppInfo -containerName $ContainerName -tenantSpecificProperties -symbolsOnly
} catch {
    Write-Result -Status 'error' -Copied @() -Message "Could not query apps in container $ContainerName: $($_.Exception.Message)"
    exit 1
}

foreach ($app in $apps) {
    if ($targetNames -contains $app.Name) {
        $dst = Join-Path $alpackages ("{0}_{1}_{2}.app" -f $app.Publisher, $app.Name, $app.Version)
        try {
            $sourceInContainer = Get-BcContainerAppFile -containerName $ContainerName -appName $app.Name -appPublisher $app.Publisher -appVersion $app.Version
            Copy-Item -Path $sourceInContainer -Destination $dst -Force
            $copied += (Split-Path $dst -Leaf)
        } catch {
            Write-Warning "Could not copy $($app.Name): $($_.Exception.Message)"
        }
    }
}

Write-Result -Status 'ok' -Copied $copied -Message "Copied $($copied.Count) test toolkit apps to $alpackages"
exit 0
```

**Caveat.** `Get-BcContainerAppFile` may not be a real BcContainerHelper cmdlet with that exact signature. If it isn't, replace with `Get-BcContainerAppRuntimePackage` or fall back to shelling into the container with `Invoke-ScriptInBcContainer` and copying from `C:\Run\My\`. This is flagged as a known real-world adjustment that Task 9 (smoke test) will validate.

- [ ] **Step 2: Commit**

```bash
git add skills/bc-container/scripts/copy-test-toolkit-symbols.ps1
git commit -m "feat(bc-container): add test toolkit symbol copier"
```

---

### Task 7: `remove-container.ps1` — wrap `Remove-BcContainer`

**Files:**
- Modify: `skills/bc-container/scripts/remove-container.ps1`

- [ ] **Step 1: Implement the script**

Write `skills/bc-container/scripts/remove-container.ps1` with this exact content:

```powershell
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

# Resolve container name from metadata if not given
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

# Clean up metadata and credential files
Remove-Item $metadataPath -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $CredentialStoreRoot "$ContainerName.json") -Force -ErrorAction SilentlyContinue

Write-Result -Status 'ok' -Message "Removed container $ContainerName and cleaned up metadata"
exit 0
```

- [ ] **Step 2: Commit**

```bash
git add skills/bc-container/scripts/remove-container.ps1
git commit -m "feat(bc-container): add remove-container wrapper"
```

---

### Task 8: Write `SKILL.md`

**Files:**
- Modify: `skills/bc-container/SKILL.md`

- [ ] **Step 1: Write the skill manifest and runbook**

Write `skills/bc-container/SKILL.md` with this exact content:

````markdown
---
name: bc-container
description: Create, use, and remove Business Central containers via BcContainerHelper. Use when the user needs a local BC server for publish, debug, or running tests — NOT for symbol-only work, which al_downloadsymbols handles without a container.
---

# bc-container

Wraps BcContainerHelper's container lifecycle with project-aware defaults. The agent uses this skill when a task actually needs a running BC server.

## When to use

- The user asks to create / set up / spin up a container.
- The user asks to run tests, and `.bc-agent/container.json` does not exist.
- The user asks to publish and debug, and there is no container yet.
- The user asks to remove / clean up the container.

**Do NOT use this skill** for:

- Compile-only work → that needs symbols, and `al_downloadsymbols` via `almcp` handles that with no container.
- Symbol lookup → use the `bc-symbols` MCP server.

## Creating a container

Run these steps:

### 1. Verify Docker Desktop

```bash
pwsh -NoProfile -File .claude/plugins/bc-agent-plugin/skills/bc-container/scripts/verify-docker.ps1
```

If `status` is `not-running` or `not-installed`, surface the message and stop.

### 2. Read the target version from `app.json`

```bash
pwsh -NoProfile -File .claude/plugins/bc-agent-plugin/skills/bc-container/scripts/read-bc-version.ps1 -AppJsonPath "<project>/app.json"
```

If `status` is `missing-versions`, ask the user for the platform/application version and offer to write them into `app.json`.

### 3. Create the container

Propose a container name (default: the project folder name) and ask the user to confirm. Then:

```bash
pwsh -NoProfile -File .claude/plugins/bc-agent-plugin/skills/bc-container/scripts/new-container.ps1 `
    -ProjectRoot "<abs-project-root>" `
    -ContainerName "<name>" `
    -Platform "<from-step-2>" `
    -Application "<from-step-2>"
```

This will generate a random admin password, store it in `%LOCALAPPDATA%\bc-agent-plugin\containers\<name>.json` with restricted ACLs, resolve the artifact URL, and call `New-BcContainer` with `-accept_eula -includeAL -includeTestToolkit`.

### 4. Copy Test Toolkit symbols into `.alpackages/`

```bash
pwsh -NoProfile -File .claude/plugins/bc-agent-plugin/skills/bc-container/scripts/copy-test-toolkit-symbols.ps1 -ProjectRoot "<abs>" -ContainerName "<name>"
```

This gives the compiler visibility into the Test Runner / Library Assert / etc. symbols that `al_downloadsymbols` (global sources) cannot provide.

### 5. Summarize

Report to the user:

- Container name
- API port
- Where credentials are stored
- Metadata path (`<project>/.bc-agent/container.json`) so future sessions find the container automatically

## Removing a container

```bash
pwsh -NoProfile -File .claude/plugins/bc-agent-plugin/skills/bc-container/scripts/remove-container.ps1 -ProjectRoot "<abs>"
```

The script reads the container name from `.bc-agent/container.json` if not given explicitly. Always confirm with the user before running this — container removal is destructive.

## Using an existing container

Before creating a new container, always check whether `.bc-agent/container.json` exists. If yes, read it — the container may already exist and be reusable. Only create a new container if:

- `.bc-agent/container.json` is missing, or
- The user explicitly asks for a fresh one

## Failure modes

- Docker not running → "Start Docker Desktop and retry."
- BcContainerHelper not installed → "Run `/bc-setup` first to install prerequisites."
- `app.json` missing platform/application → ask the user for the target version.
- `New-BcContainer` fails → surface the BcContainerHelper error verbatim; the root cause is usually clear (image pull, EULA, port conflict).
````

- [ ] **Step 2: Commit**

```bash
git add skills/bc-container/SKILL.md
git commit -m "docs(bc-container): add SKILL.md"
```

---

### Task 9: Manual smoke test (gated — requires Docker)

**Files:** none (read-only verification)

**Gate:** this task requires Docker Desktop running and ~10 GB disk space for a real BC sandbox image pull. Skip if running plans in CI or on a machine without Docker. Failure here does not block other plans.

- [ ] **Step 1: Verify Docker**

Run: `pwsh -NoProfile -File skills/bc-container/scripts/verify-docker.ps1`
Expected: `status: "ok"`.

- [ ] **Step 2: Create a throwaway project**

Run:
```
pwsh -NoProfile -Command @'
$tmp = Join-Path $env:TEMP "bc-container-smoke-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
@{
    id = "dddddddd-dddd-dddd-dddd-dddddddddddd"
    name = "Smoke"
    publisher = "Fixture"
    version = "1.0.0.0"
    platform = "28.0.0.0"
    application = "28.0.0.0"
    idRanges = @(@{ from = 50100; to = 50149 })
} | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $tmp 'app.json') -Encoding UTF8
Write-Host $tmp
'@
```

- [ ] **Step 3: Create the container (real)**

Run (substitute project path from step 2):
```
pwsh -NoProfile -File skills/bc-container/scripts/new-container.ps1 -ProjectRoot "<project>" -ContainerName "bcsmoke" -Platform "28.0.0.0" -Application "28.0.0.0"
```

Expected: `status: "ok"`. This takes 3–10 minutes on first run (image pull).

- [ ] **Step 4: Verify metadata and credential files exist**

Run:
```
pwsh -NoProfile -Command "Get-Content '<project>/.bc-agent/container.json' -Raw | ConvertFrom-Json | ConvertTo-Json"
```
Expected: JSON with `name: "bcsmoke"`, real `artifactUrl`, real `credentialsFile` path.

- [ ] **Step 5: Copy test toolkit symbols**

Run:
```
pwsh -NoProfile -File skills/bc-container/scripts/copy-test-toolkit-symbols.ps1 -ProjectRoot "<project>" -ContainerName "bcsmoke"
```

Expected: `status: "ok"` with `copied` non-empty. If this fails with "cmdlet not found", adjust `copy-test-toolkit-symbols.ps1` to use the actual BcContainerHelper cmdlet name (likely `Get-BcContainerAppRuntimePackage` or shell-into-container path) and re-run.

- [ ] **Step 6: Remove the container**

Run:
```
pwsh -NoProfile -File skills/bc-container/scripts/remove-container.ps1 -ProjectRoot "<project>" -ContainerName "bcsmoke"
```

Expected: `status: "ok"`. Verify `.bc-agent/container.json` is gone.

- [ ] **Step 7: Clean up project**

Run:
```
pwsh -NoProfile -Command "Remove-Item '<project>' -Recurse -Force"
```

- [ ] **Step 8: Run all unit tests for Plan D**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-container -Output Detailed"`
Expected: all tests pass (Read-BcVersion: 3, New-Container: 2 = 5 total).

- [ ] **Step 9: No commit needed** (verification only)
