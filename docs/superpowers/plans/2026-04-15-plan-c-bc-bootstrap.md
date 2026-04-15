# Plan C — `bc-bootstrap` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `bc-bootstrap` skill that runs once per BC project to: verify `app.json`, resolve or provision the AL toolchain (5-step search order ending in a vsix download from the Visual Studio Marketplace), offer to install BcContainerHelper, write/merge `.mcp.json` with `almcp` and `bc-symbols` entries, and write/update `CLAUDE.md`. After `bc-bootstrap` runs, a fresh BC project has everything needed for the `bc-developer` subagent to work.

**Architecture:** A skill with a `SKILL.md` that tells Claude when and how to run it, plus three PowerShell scripts: one that resolves the AL toolchain, one that downloads the vsix as a fallback, and one that writes `.mcp.json`. The skill's SKILL.md orchestrates them via Bash tool calls the agent makes while executing the skill. No PowerShell module shipped — each script is standalone and idempotent.

**Tech Stack:** PowerShell 5.1-compatible scripts (stock Windows), `Invoke-WebRequest` for the vsix download, `System.IO.Compression.FileSystem` for zip extraction, Pester 5 for tests.

---

## File Structure

**Create (skill):**
- `skills/bc-bootstrap/SKILL.md` — skill manifest with frontmatter; body is the step-by-step runbook the agent follows
- `skills/bc-bootstrap/scripts/resolve-al-tools.ps1` — 5-step toolchain resolver, outputs JSON `{status, toolsPath, source, message}`
- `skills/bc-bootstrap/scripts/download-al-vsix.ps1` — downloads the AL vsix from the Visual Studio Marketplace and extracts it to the plugin cache
- `skills/bc-bootstrap/scripts/write-mcp-config.ps1` — merges or creates `.mcp.json` and writes the v2 `bc-troubleshoot` template to `.bc-agent/mcp-troubleshoot.template.json`
- `skills/bc-bootstrap/scripts/ensure-pwsh7.ps1` — detects PowerShell 7, offers to install via winget if missing

**Create (tests):**
- `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1` — unit tests for the 5-step resolver with mocked filesystem
- `tests/bc-bootstrap/Write-McpConfig.Tests.ps1` — unit tests for merge-vs-create, template file output
- `tests/bc-bootstrap/fixtures/fake-vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32/altool.exe` — empty placeholder (Task 2 creates)
- `tests/bc-bootstrap/fixtures/fake-vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32/alc.exe` — empty placeholder

**Modify:**
- `commands/bc-setup.md` — updated in Task 9 to reference the real skill instead of the Plan A stub

---

## Dependencies and ordering

Plan B (bc-symbol-lookup) should land first so the `.mcp.json` writer has a real server path to reference. Plan A must have landed (plugin scaffold exists).

Task 1 scaffolds. Task 2 builds test fixtures. Tasks 3–5 implement `resolve-al-tools.ps1` with TDD across the five resolution steps. Task 6 implements `download-al-vsix.ps1` (integration-tested against the real marketplace endpoint). Task 7 implements `write-mcp-config.ps1` with TDD for merge-vs-create. Task 8 implements `ensure-pwsh7.ps1`. Task 9 writes `SKILL.md` and updates the slash command. Task 10 is an end-to-end smoke test on a fresh temp folder with a fake `app.json`.

---

### Task 1: Scaffold skill directory

**Files:**
- Create: `skills/bc-bootstrap/SKILL.md` (empty, filled in Task 9)
- Create: `skills/bc-bootstrap/scripts/resolve-al-tools.ps1` (empty)
- Create: `skills/bc-bootstrap/scripts/download-al-vsix.ps1` (empty)
- Create: `skills/bc-bootstrap/scripts/write-mcp-config.ps1` (empty)
- Create: `skills/bc-bootstrap/scripts/ensure-pwsh7.ps1` (empty)

- [ ] **Step 1: Create directories and stub files**

Run:
```
pwsh -NoProfile -Command @'
$dirs = @('skills/bc-bootstrap/scripts', 'tests/bc-bootstrap/fixtures')
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
$files = @(
  'skills/bc-bootstrap/SKILL.md',
  'skills/bc-bootstrap/scripts/resolve-al-tools.ps1',
  'skills/bc-bootstrap/scripts/download-al-vsix.ps1',
  'skills/bc-bootstrap/scripts/write-mcp-config.ps1',
  'skills/bc-bootstrap/scripts/ensure-pwsh7.ps1'
)
$files | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType File -Path $_ | Out-Null } }
'@
```

- [ ] **Step 2: Commit**

```bash
git add skills/bc-bootstrap tests/bc-bootstrap
git commit -m "feat(bc-bootstrap): scaffold skill directory"
```

---

### Task 2: Create fake VS Code extension fixture

**Files:**
- Create: `tests/bc-bootstrap/fixtures/fake-vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32/altool.exe`
- Create: `tests/bc-bootstrap/fixtures/fake-vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32/alc.exe`
- Create: `tests/bc-bootstrap/fixtures/fake-vscode/extensions/ms-dynamics-smb.al-16.9.999999/bin/win32/altool.exe` — older version to test "pick latest" logic
- Create: `tests/bc-bootstrap/fixtures/fake-vscode/extensions/ms-dynamics-smb.al-16.9.999999/bin/win32/alc.exe`

- [ ] **Step 1: Generate fixture files**

Run:
```
pwsh -NoProfile -Command @'
$base = 'tests/bc-bootstrap/fixtures/fake-vscode/extensions'
$versions = @('ms-dynamics-smb.al-17.0.2273547', 'ms-dynamics-smb.al-16.9.999999')
foreach ($v in $versions) {
  $dir = "$base/$v/bin/win32"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  'fake binary' | Set-Content -Path "$dir/altool.exe"
  'fake binary' | Set-Content -Path "$dir/alc.exe"
}
Write-Host "Fixtures created"
'@
```

- [ ] **Step 2: Commit**

```bash
git add tests/bc-bootstrap/fixtures
git commit -m "test(bc-bootstrap): add fake VS Code extension fixtures"
```

---

### Task 3: `resolve-al-tools.ps1` — env var path (step 1)

**Files:**
- Create: `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1`
- Modify: `skills/bc-bootstrap/scripts/resolve-al-tools.ps1`

- [ ] **Step 1: Write failing test for env var resolution**

Write `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-bootstrap/scripts/resolve-al-tools.ps1"
    $script:fixturesDir = "$PSScriptRoot/fixtures"
}

function Invoke-Resolver {
    param(
        [string] $EnvToolsPath,
        [string] $VSCodeExtensionsRoot,
        [string] $PluginCacheRoot,
        [string] $BcContainerHelperRoot,
        [switch] $AllowDownload
    )
    $cmd = @(
        'pwsh', '-NoProfile', '-File', $script:scriptPath,
        '-EnvToolsPath', "`"$EnvToolsPath`"",
        '-VSCodeExtensionsRoot', "`"$VSCodeExtensionsRoot`"",
        '-PluginCacheRoot', "`"$PluginCacheRoot`"",
        '-BcContainerHelperRoot', "`"$BcContainerHelperRoot`""
    )
    if ($AllowDownload) { $cmd += '-AllowDownload' }
    $raw = & $cmd[0] $cmd[1..($cmd.Length-1)]
    if ($LASTEXITCODE -ne 0) {
        throw "Resolver failed with exit $LASTEXITCODE`: $raw"
    }
    return ($raw -join "`n") | ConvertFrom-Json
}

Describe 'resolve-al-tools.ps1' {
    Context 'Step 1: environment variable' {
        It 'returns env var path when set and valid' {
            $fake = "$fixturesDir/fake-vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32"
            $result = Invoke-Resolver -EnvToolsPath $fake -VSCodeExtensionsRoot '' -PluginCacheRoot '' -BcContainerHelperRoot ''
            $result.status | Should -Be 'ok'
            $result.source | Should -Be 'env'
            $result.toolsPath | Should -Be (Resolve-Path $fake).Path
        }

        It 'skips env var when the path does not exist' {
            $result = Invoke-Resolver -EnvToolsPath 'C:/nonexistent/path' -VSCodeExtensionsRoot '' -PluginCacheRoot '' -BcContainerHelperRoot ''
            $result.source | Should -Not -Be 'env'
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Resolve-AlTools.Tests.ps1 -Output Detailed"`
Expected: tests fail because `resolve-al-tools.ps1` is empty and returns nothing.

- [ ] **Step 3: Implement step 1 of the resolver (env var only)**

Write `skills/bc-bootstrap/scripts/resolve-al-tools.ps1` with this exact content:

```powershell
#requires -Version 5.1
<#
resolve-al-tools.ps1 — Resolve the AL toolchain (altool.exe, alc.exe, almcp) across
five fallback sources. Writes a JSON object to stdout:

  { "status": "ok"|"not-found"|"error",
    "source": "env"|"vscode"|"pluginCache"|"bcContainerHelper"|"marketplace",
    "toolsPath": "<absolute path to bin/win32 folder>",
    "message": "<human-readable summary>" }
#>
[CmdletBinding()]
param(
    [string] $EnvToolsPath            = $env:BC_AGENT_AL_TOOLS_PATH,
    [string] $VSCodeExtensionsRoot    = (Join-Path $env:USERPROFILE '.vscode\extensions'),
    [string] $PluginCacheRoot         = (Join-Path $env:LOCALAPPDATA 'bc-agent-plugin\al-tools'),
    [string] $BcContainerHelperRoot   = 'C:\ProgramData\BcContainerHelper\Extensions\bc-gt',
    [switch] $AllowDownload
)

$ErrorActionPreference = 'Stop'

function Write-ResolverResult {
    param([string]$Status, [string]$Source, [string]$ToolsPath, [string]$Message)
    $obj = [pscustomobject]@{
        status    = $Status
        source    = $Source
        toolsPath = $ToolsPath
        message   = $Message
    }
    $obj | ConvertTo-Json -Compress
}

function Test-ToolchainPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path $Path)) { return $false }
    $altool = Join-Path $Path 'altool.exe'
    $alc    = Join-Path $Path 'alc.exe'
    return (Test-Path $altool) -and (Test-Path $alc)
}

# Step 1: env var
if ($EnvToolsPath -and (Test-ToolchainPath $EnvToolsPath)) {
    $abs = (Resolve-Path $EnvToolsPath).Path
    Write-ResolverResult -Status 'ok' -Source 'env' -ToolsPath $abs -Message "Resolved from BC_AGENT_AL_TOOLS_PATH"
    exit 0
}

# Placeholder for later steps — filled in Tasks 4 and 5.
Write-ResolverResult -Status 'not-found' -Source '' -ToolsPath '' -Message "Not yet implemented"
exit 1
```

- [ ] **Step 4: Run tests to verify step-1 tests pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Resolve-AlTools.Tests.ps1 -Output Detailed"`
Expected: 2 tests pass (env var found, env var missing falls through).

- [ ] **Step 5: Commit**

```bash
git add skills/bc-bootstrap/scripts/resolve-al-tools.ps1 tests/bc-bootstrap/Resolve-AlTools.Tests.ps1
git commit -m "feat(bc-bootstrap): resolver step 1 (env var)"
```

---

### Task 4: `resolve-al-tools.ps1` — VS Code extension resolution (step 2)

**Files:**
- Modify: `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1`
- Modify: `skills/bc-bootstrap/scripts/resolve-al-tools.ps1`

- [ ] **Step 1: Add failing tests for VS Code extension picking**

Append to `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1`:

```powershell
Describe 'resolve-al-tools.ps1 step 2' {
    It 'picks the latest version from VS Code extensions' {
        $fake = "$fixturesDir/fake-vscode/extensions"
        $result = Invoke-Resolver -EnvToolsPath '' -VSCodeExtensionsRoot $fake -PluginCacheRoot '' -BcContainerHelperRoot ''
        $result.status | Should -Be 'ok'
        $result.source | Should -Be 'vscode'
        $result.toolsPath | Should -Match 'ms-dynamics-smb.al-17\.0\.2273547'
    }

    It 'returns not-found when extensions root has no AL extension' {
        $empty = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP 'bc-bootstrap-empty') -ErrorAction SilentlyContinue
        $result = Invoke-Resolver -EnvToolsPath '' -VSCodeExtensionsRoot $empty.FullName -PluginCacheRoot '' -BcContainerHelperRoot ''
        $result.source | Should -Not -Be 'vscode'
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Resolve-AlTools.Tests.ps1 -Output Detailed"`
Expected: 2 new tests fail.

- [ ] **Step 3: Implement step 2**

In `skills/bc-bootstrap/scripts/resolve-al-tools.ps1`, replace the "Placeholder for later steps" block with:

```powershell
# Step 2: VS Code extensions (pick latest by version folder name)
if ($VSCodeExtensionsRoot -and (Test-Path $VSCodeExtensionsRoot)) {
    $candidates = Get-ChildItem -Path $VSCodeExtensionsRoot -Directory -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue
    if ($candidates) {
        $sorted = $candidates | Sort-Object -Property @{
            Expression = {
                $verText = ($_.Name -replace '^ms-dynamics-smb\.al-', '')
                try { [version]$verText } catch { [version]'0.0.0.0' }
            }
            Descending = $true
        }
        foreach ($c in $sorted) {
            $p = Join-Path $c.FullName 'bin\win32'
            if (Test-ToolchainPath $p) {
                Write-ResolverResult -Status 'ok' -Source 'vscode' -ToolsPath (Resolve-Path $p).Path -Message "Resolved from VS Code extension $($c.Name)"
                exit 0
            }
        }
    }
}

# Placeholder for steps 3-5 — filled in Task 5
Write-ResolverResult -Status 'not-found' -Source '' -ToolsPath '' -Message "Not yet implemented"
exit 1
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Resolve-AlTools.Tests.ps1 -Output Detailed"`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-bootstrap/scripts/resolve-al-tools.ps1 tests/bc-bootstrap/Resolve-AlTools.Tests.ps1
git commit -m "feat(bc-bootstrap): resolver step 2 (VS Code extensions)"
```

---

### Task 5: `resolve-al-tools.ps1` — plugin cache and bc-gt steps (steps 3 & 4)

**Files:**
- Modify: `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1`
- Modify: `skills/bc-bootstrap/scripts/resolve-al-tools.ps1`

- [ ] **Step 1: Add failing tests for steps 3 and 4**

Append to `tests/bc-bootstrap/Resolve-AlTools.Tests.ps1`:

```powershell
Describe 'resolve-al-tools.ps1 steps 3 and 4' {
    It 'finds tools in the plugin cache when no env var and no VS Code' {
        $cache = Join-Path $env:TEMP 'bc-bootstrap-plugincache'
        $toolsDir = Join-Path $cache 'bin\win32'
        New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
        'fake' | Set-Content -Path (Join-Path $toolsDir 'altool.exe')
        'fake' | Set-Content -Path (Join-Path $toolsDir 'alc.exe')

        try {
            $result = Invoke-Resolver -EnvToolsPath '' -VSCodeExtensionsRoot '' -PluginCacheRoot $cache -BcContainerHelperRoot ''
            $result.status | Should -Be 'ok'
            $result.source | Should -Be 'pluginCache'
        } finally {
            Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns not-found when no source has tools and AllowDownload not set' {
        $result = Invoke-Resolver -EnvToolsPath '' -VSCodeExtensionsRoot '' -PluginCacheRoot 'C:/nope' -BcContainerHelperRoot 'C:/nope'
        $result.status | Should -Be 'not-found'
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Resolve-AlTools.Tests.ps1 -Output Detailed"`
Expected: 2 new tests fail.

- [ ] **Step 3: Implement steps 3 and 4**

In `skills/bc-bootstrap/scripts/resolve-al-tools.ps1`, replace the "Placeholder for steps 3-5" block with:

```powershell
# Step 3: plugin's own cache
if ($PluginCacheRoot) {
    $p = Join-Path $PluginCacheRoot 'bin\win32'
    if (Test-ToolchainPath $p) {
        Write-ResolverResult -Status 'ok' -Source 'pluginCache' -ToolsPath (Resolve-Path $p).Path -Message "Resolved from plugin cache"
        exit 0
    }
}

# Step 4: BcContainerHelper bc-gt vsix extraction
if ($BcContainerHelperRoot -and (Test-Path $BcContainerHelperRoot)) {
    $vsix = Join-Path $BcContainerHelperRoot 'ALLanguage.vsix'
    if (Test-Path $vsix) {
        # Extract to plugin cache and re-check
        $extractTo = $PluginCacheRoot
        New-Item -ItemType Directory -Force -Path $extractTo | Out-Null
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($vsix, $extractTo)
        } catch {
            # ExtractToDirectory throws if target not empty — try entry-by-entry
            $zip = [IO.Compression.ZipFile]::OpenRead($vsix)
            try {
                foreach ($e in $zip.Entries) {
                    if ($e.FullName -like 'extension/*') {
                        $rel = $e.FullName.Substring('extension/'.Length)
                        if (-not $rel) { continue }
                        $dst = Join-Path $extractTo $rel
                        $dstDir = Split-Path $dst -Parent
                        if ($dstDir -and -not (Test-Path $dstDir)) {
                            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
                        }
                        if (-not $e.FullName.EndsWith('/')) {
                            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $true)
                        }
                    }
                }
            } finally { $zip.Dispose() }
        }
        $p = Join-Path $extractTo 'bin\win32'
        if (Test-ToolchainPath $p) {
            Write-ResolverResult -Status 'ok' -Source 'bcContainerHelper' -ToolsPath (Resolve-Path $p).Path -Message "Extracted from BcContainerHelper vsix"
            exit 0
        }
    }
}

# Step 5: marketplace download (only if explicitly allowed — actual download is a separate script)
if ($AllowDownload) {
    Write-ResolverResult -Status 'needs-download' -Source 'marketplace' -ToolsPath '' -Message "Need to run download-al-vsix.ps1"
    exit 2
}

Write-ResolverResult -Status 'not-found' -Source '' -ToolsPath '' -Message "AL toolchain not found in any source. Set BC_AGENT_AL_TOOLS_PATH, install VS Code AL extension, or run with -AllowDownload to pull from marketplace."
exit 1
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Resolve-AlTools.Tests.ps1 -Output Detailed"`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-bootstrap/scripts/resolve-al-tools.ps1 tests/bc-bootstrap/Resolve-AlTools.Tests.ps1
git commit -m "feat(bc-bootstrap): resolver steps 3-4 (plugin cache, bc-gt vsix)"
```

---

### Task 6: `download-al-vsix.ps1` — marketplace download

**Files:**
- Modify: `skills/bc-bootstrap/scripts/download-al-vsix.ps1`

**Note.** This is not unit-tested — it hits the real Visual Studio Marketplace. Smoke-tested in Task 10.

- [ ] **Step 1: Implement the download script**

Write `skills/bc-bootstrap/scripts/download-al-vsix.ps1` with this exact content:

```powershell
#requires -Version 5.1
<#
download-al-vsix.ps1 — Download the latest Microsoft AL Language extension vsix from the
Visual Studio Marketplace and extract it into the plugin's AL toolchain cache.

Outputs a JSON object:
  { "status": "ok"|"error", "toolsPath": "...", "message": "..." }
#>
[CmdletBinding()]
param(
    [string] $PluginCacheRoot = (Join-Path $env:LOCALAPPDATA 'bc-agent-plugin\al-tools'),
    [string] $MarketplaceUrl  = 'https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-dynamics-smb/vsextensions/al/latest/vspackage'
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param([string]$Status, [string]$ToolsPath, [string]$Message)
    [pscustomobject]@{ status=$Status; toolsPath=$ToolsPath; message=$Message } | ConvertTo-Json -Compress
}

try {
    New-Item -ItemType Directory -Force -Path $PluginCacheRoot | Out-Null
    $tempVsix = Join-Path $env:TEMP "al-$([Guid]::NewGuid().ToString('N')).vsix"

    [Console]::Error.WriteLine("Downloading AL vsix from marketplace...")
    # Marketplace returns a gzipped vsix; Invoke-WebRequest handles decompression automatically.
    Invoke-WebRequest -Uri $MarketplaceUrl -OutFile $tempVsix -UseBasicParsing -Headers @{ 'User-Agent' = 'bc-agent-plugin/0.1' }

    if (-not (Test-Path $tempVsix) -or (Get-Item $tempVsix).Length -lt 1MB) {
        Write-Result -Status 'error' -ToolsPath '' -Message "Downloaded file is missing or suspiciously small"
        exit 1
    }

    [Console]::Error.WriteLine("Extracting vsix to $PluginCacheRoot...")
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($tempVsix)
    try {
        foreach ($e in $zip.Entries) {
            if ($e.FullName -like 'extension/*') {
                $rel = $e.FullName.Substring('extension/'.Length)
                if (-not $rel) { continue }
                $dst = Join-Path $PluginCacheRoot $rel
                $dstDir = Split-Path $dst -Parent
                if ($dstDir -and -not (Test-Path $dstDir)) {
                    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
                }
                if (-not $e.FullName.EndsWith('/')) {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $true)
                }
            }
        }
    } finally {
        $zip.Dispose()
    }

    Remove-Item $tempVsix -Force -ErrorAction SilentlyContinue

    $toolsPath = Join-Path $PluginCacheRoot 'bin\win32'
    if ((Test-Path (Join-Path $toolsPath 'altool.exe')) -and (Test-Path (Join-Path $toolsPath 'alc.exe'))) {
        Write-Result -Status 'ok' -ToolsPath (Resolve-Path $toolsPath).Path -Message "Downloaded and extracted"
        exit 0
    } else {
        Write-Result -Status 'error' -ToolsPath '' -Message "Extraction finished but altool.exe/alc.exe not found at $toolsPath"
        exit 1
    }
} catch {
    Write-Result -Status 'error' -ToolsPath '' -Message "Download failed: $($_.Exception.Message)"
    exit 1
}
```

- [ ] **Step 2: Commit**

```bash
git add skills/bc-bootstrap/scripts/download-al-vsix.ps1
git commit -m "feat(bc-bootstrap): add marketplace vsix downloader"
```

---

### Task 7: `write-mcp-config.ps1` — write or merge `.mcp.json`

**Files:**
- Create: `tests/bc-bootstrap/Write-McpConfig.Tests.ps1`
- Modify: `skills/bc-bootstrap/scripts/write-mcp-config.ps1`

- [ ] **Step 1: Write failing Pester tests**

Write `tests/bc-bootstrap/Write-McpConfig.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-bootstrap/scripts/write-mcp-config.ps1"
}

function Invoke-Writer {
    param([string]$ProjectRoot, [string]$AlToolsPath, [string]$PluginRoot)
    & pwsh -NoProfile -File $script:scriptPath -ProjectRoot $ProjectRoot -AlToolsPath $AlToolsPath -PluginRoot $PluginRoot
}

Describe 'write-mcp-config.ps1' {
    BeforeEach {
        $script:tmp = Join-Path $env:TEMP "mcpcfg-$([Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    }
    AfterEach {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates .mcp.json with almcp and bc-symbols entries when none exists' {
        Invoke-Writer -ProjectRoot $tmp -AlToolsPath 'C:/fake/altool/path' -PluginRoot 'C:/fake/plugin'
        $path = Join-Path $tmp '.mcp.json'
        Test-Path $path | Should -BeTrue
        $cfg = Get-Content $path -Raw | ConvertFrom-Json
        $cfg.mcpServers.almcp | Should -Not -BeNullOrEmpty
        $cfg.mcpServers.'bc-symbols' | Should -Not -BeNullOrEmpty
        $cfg.mcpServers.almcp.command | Should -Match 'altool'
        $cfg.mcpServers.'bc-symbols'.command | Should -Be 'pwsh'
    }

    It 'merges into an existing .mcp.json without clobbering other entries' {
        $existing = @{
            mcpServers = @{
                'some-other-server' = @{ command = 'node'; args = @('existing.js') }
            }
        }
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $tmp '.mcp.json') -Encoding UTF8

        Invoke-Writer -ProjectRoot $tmp -AlToolsPath 'C:/fake/altool/path' -PluginRoot 'C:/fake/plugin'

        $cfg = Get-Content (Join-Path $tmp '.mcp.json') -Raw | ConvertFrom-Json
        $cfg.mcpServers.'some-other-server' | Should -Not -BeNullOrEmpty
        $cfg.mcpServers.almcp | Should -Not -BeNullOrEmpty
        $cfg.mcpServers.'bc-symbols' | Should -Not -BeNullOrEmpty
    }

    It 'writes bc-troubleshoot template to .bc-agent/mcp-troubleshoot.template.json' {
        Invoke-Writer -ProjectRoot $tmp -AlToolsPath 'C:/fake/altool/path' -PluginRoot 'C:/fake/plugin'
        $tmpl = Join-Path $tmp '.bc-agent/mcp-troubleshoot.template.json'
        Test-Path $tmpl | Should -BeTrue
        $content = Get-Content $tmpl -Raw | ConvertFrom-Json
        $content.'bc-troubleshoot' | Should -Not -BeNullOrEmpty
        $content.'bc-troubleshoot'.type | Should -Be 'http'
    }

    It 'does not clobber an existing CLAUDE.md without confirmation flag' {
        'existing content' | Set-Content -Path (Join-Path $tmp 'CLAUDE.md') -Encoding UTF8
        Invoke-Writer -ProjectRoot $tmp -AlToolsPath 'C:/fake/altool/path' -PluginRoot 'C:/fake/plugin'
        (Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw).Trim() | Should -Be 'existing content'
    }

    It 'creates CLAUDE.md when none exists' {
        Invoke-Writer -ProjectRoot $tmp -AlToolsPath 'C:/fake/altool/path' -PluginRoot 'C:/fake/plugin'
        Test-Path (Join-Path $tmp 'CLAUDE.md') | Should -BeTrue
        (Get-Content (Join-Path $tmp 'CLAUDE.md') -Raw) | Should -Match 'bc-developer'
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Write-McpConfig.Tests.ps1 -Output Detailed"`
Expected: 5 tests fail because the script is empty.

- [ ] **Step 3: Implement `write-mcp-config.ps1`**

Write `skills/bc-bootstrap/scripts/write-mcp-config.ps1` with this exact content:

```powershell
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

$altoolExe = Join-Path $AlToolsPath 'altool.exe'
$bcSymbolsScript = Join-Path $PluginRoot 'skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1'
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

# Build the bc-symbols entry — use ${workspaceFolder} so Claude Code substitutes at runtime
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
```

- [ ] **Step 4: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap/Write-McpConfig.Tests.ps1 -Output Detailed"`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-bootstrap/scripts/write-mcp-config.ps1 tests/bc-bootstrap/Write-McpConfig.Tests.ps1
git commit -m "feat(bc-bootstrap): implement .mcp.json writer"
```

---

### Task 8: `ensure-pwsh7.ps1` — detect PowerShell 7

**Files:**
- Modify: `skills/bc-bootstrap/scripts/ensure-pwsh7.ps1`

- [ ] **Step 1: Implement the script**

Write `skills/bc-bootstrap/scripts/ensure-pwsh7.ps1` with this exact content:

```powershell
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
```

- [ ] **Step 2: Smoke test**

Run: `pwsh -NoProfile -File skills/bc-bootstrap/scripts/ensure-pwsh7.ps1`
Expected: JSON with `status: "ok"`, exit 0 (we're running in pwsh 7).

- [ ] **Step 3: Commit**

```bash
git add skills/bc-bootstrap/scripts/ensure-pwsh7.ps1
git commit -m "feat(bc-bootstrap): add pwsh 7 detector"
```

---

### Task 9: Write `SKILL.md` and update `commands/bc-setup.md`

**Files:**
- Modify: `skills/bc-bootstrap/SKILL.md`
- Modify: `commands/bc-setup.md`

- [ ] **Step 1: Write the skill manifest**

Write `skills/bc-bootstrap/SKILL.md` with this exact content:

````markdown
---
name: bc-bootstrap
description: Initializes a Business Central project for Claude Code. Resolves the AL toolchain, offers to install BcContainerHelper, writes .mcp.json with almcp and bc-symbols MCP server entries, and creates CLAUDE.md. Run once per project before using the bc-developer subagent.
---

# bc-bootstrap

First-run setup for a Business Central AL project. Idempotent: running it twice is a no-op if everything is already in place.

## When to use

- The user opens a folder with `app.json` but no `.mcp.json` entry for `almcp`.
- The user says "set up Claude for this BC project" or similar.
- Another BC skill fails with "AL toolchain not found".

## Steps

Run these steps in order, using the `Bash` tool to invoke the PowerShell scripts.

### 1. Verify `app.json` exists

If there is no `app.json` at the project root, stop and tell the user: "Run this from a Business Central project root (the folder containing `app.json`)."

### 2. Check that PowerShell 7 is installed

Run:

```bash
pwsh -NoProfile -File .claude/plugins/bc-agent-plugin/skills/bc-bootstrap/scripts/ensure-pwsh7.ps1
```

If the result is `status: "missing"` or `"outdated"`, ask the user whether to install PowerShell 7 via winget: `winget install --id Microsoft.PowerShell --source winget`. Do not run the install without confirmation.

### 3. Resolve the AL toolchain

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/plugins/bc-agent-plugin/skills/bc-bootstrap/scripts/resolve-al-tools.ps1
```

Parse the JSON output.

- `status: "ok"` → note the `toolsPath` and proceed to step 5.
- `status: "not-found"` → proceed to step 4 (download from marketplace).

### 4. Download the AL vsix (fallback)

Ask the user: "The AL toolchain was not found on this machine. Download the AL Language extension from the Visual Studio Marketplace into the plugin's cache? This is a one-time download of ~100 MB." Only proceed on confirmation.

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/plugins/bc-agent-plugin/skills/bc-bootstrap/scripts/download-al-vsix.ps1
```

If the result is `status: "error"`, surface the message to the user and stop.

### 5. Offer to install BcContainerHelper if missing

Run:

```bash
powershell -NoProfile -Command "if (Get-Module -ListAvailable BcContainerHelper) { 'installed' } else { 'missing' }"
```

If the output is `missing`, tell the user: "BcContainerHelper is required for container mode (debug/test workflows). It is not needed for compile-only work. Install now? (`Install-Module BcContainerHelper -Scope CurrentUser -Force`)" Only install on confirmation. Do not fail bootstrap if the user declines — container mode will fail later if attempted.

### 6. Write `.mcp.json` and `CLAUDE.md`

Run:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/plugins/bc-agent-plugin/skills/bc-bootstrap/scripts/write-mcp-config.ps1 -ProjectRoot "<abs-project-root>" -AlToolsPath "<from-step-3-or-4>" -PluginRoot "<plugin-install-root>"
```

### 7. Summarize

Report to the user:

- Where the AL toolchain lives
- Which MCP servers were registered
- Whether `CLAUDE.md` was created or left untouched
- The suggested next step: "Use `/bc <task>` to delegate BC work to the bc-developer subagent."

## Failure modes

- Missing `app.json` → "Run this from a BC project root (folder containing `app.json`)."
- AL toolchain unreachable and network download declined → "AL toolchain not found. Set `$env:BC_AGENT_AL_TOOLS_PATH`, install the VS Code AL extension, or re-run with network access."
- Existing `CLAUDE.md` → never overwritten; a note is printed instead.
````

- [ ] **Step 2: Replace `commands/bc-setup.md`**

Write `commands/bc-setup.md` with this exact content:

```markdown
---
description: Initialize a Business Central project for Claude Code — runs the bc-bootstrap skill.
---

Use the `bc-bootstrap` skill to initialize the current Business Central project for Claude Code.

The skill will: verify `app.json`, resolve the AL toolchain (from VS Code, BcContainerHelper, plugin cache, or by downloading the vsix from the Visual Studio Marketplace), offer to install BcContainerHelper, and write `.mcp.json` with `almcp` and `bc-symbols` MCP server entries plus a `CLAUDE.md`.

After it finishes, use `/bc <task>` to delegate BC work to the `bc-developer` subagent.
```

- [ ] **Step 3: Commit**

```bash
git add skills/bc-bootstrap/SKILL.md commands/bc-setup.md
git commit -m "docs(bc-bootstrap): add SKILL.md and wire /bc-setup"
```

---

### Task 10: End-to-end smoke test on a temp project

**Files:** none (read-only verification)

- [ ] **Step 1: Create a fake BC project**

Run:
```
pwsh -NoProfile -Command @'
$tmp = Join-Path $env:TEMP "bc-bootstrap-smoke-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
@{
    id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    name = "Smoke Test"
    publisher = "Fixture"
    version = "1.0.0.0"
    platform = "28.0.0.0"
    application = "28.0.0.0"
    idRanges = @(@{ from = 50100; to = 50149 })
    dependencies = @()
} | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $tmp 'app.json') -Encoding UTF8
Write-Host $tmp
'@
```

Note the path printed; use it below as `$project`.

- [ ] **Step 2: Resolve the toolchain**

Run:
```
powershell -NoProfile -ExecutionPolicy Bypass -File skills/bc-bootstrap/scripts/resolve-al-tools.ps1
```

Expected: JSON with `status: "ok"` and a real `toolsPath` (likely from VS Code extension since the plan assumes the developer has it installed). If `status: "not-found"`, the developer running this plan needs the AL extension installed first.

- [ ] **Step 3: Write the MCP config**

Run (substitute the real values from steps 1 and 2):
```
powershell -NoProfile -ExecutionPolicy Bypass -File skills/bc-bootstrap/scripts/write-mcp-config.ps1 -ProjectRoot "<project-path-from-step-1>" -AlToolsPath "<toolsPath-from-step-2>" -PluginRoot (Get-Location).Path
```

Expected: JSON `status: "ok"`.

- [ ] **Step 4: Verify outputs**

Run:
```
pwsh -NoProfile -Command "Get-Content '<project-path>/.mcp.json' -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 10"
```

Expected: output contains `mcpServers.almcp` with `command` ending in `altool.exe` and `mcpServers.bc-symbols` with `command: pwsh`.

Run:
```
pwsh -NoProfile -Command "Test-Path '<project-path>/.bc-agent/mcp-troubleshoot.template.json'"
```

Expected: `True`.

Run:
```
pwsh -NoProfile -Command "Test-Path '<project-path>/CLAUDE.md'"
```

Expected: `True`.

- [ ] **Step 5: Clean up**

Run:
```
pwsh -NoProfile -Command "Remove-Item '<project-path>' -Recurse -Force"
```

- [ ] **Step 6: Run full test suite to verify no regressions**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-bootstrap -Output Detailed"`
Expected: all tests pass (Resolve-AlTools: 6, Write-McpConfig: 5 = 11 total).

- [ ] **Step 7: No commit needed** (verification only)
