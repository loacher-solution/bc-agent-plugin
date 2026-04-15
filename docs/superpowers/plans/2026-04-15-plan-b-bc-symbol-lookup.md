# Plan B — `bc-symbol-lookup` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local stdio MCP server in PowerShell that parses Business Central `.app` files offline and exposes six tools (`bc_find_object`, `bc_get_fields`, `bc_get_procedures`, `bc_get_object_source`, `bc_search`, `bc_list_apps`) so Claude can answer object/field/procedure queries without hallucinating, without a running BC server, and without access to Microsoft private repositories.

**Architecture:** Pure read-only PowerShell. An `.app` file is a zip with a 40-byte header; v28 apps are "Ready2Run" wrappers — the outer zip contains `readytorunappmanifest.json` plus an inner `.app` that is itself a 40-byte-prefixed zip. Inside the innermost zip lives `SymbolReference.json`, a JSON file with a recursive `Namespaces` tree whose leaves hold arrays of `Tables`, `Pages`, `Codeunits`, etc. The server walks this tree on startup, builds an in-memory flat index, and serves stdio MCP JSON-RPC requests. File-system watching re-indexes on `.alpackages/` changes.

**Tech Stack:** PowerShell 7 (`pwsh.exe`), .NET `System.IO.Compression.ZipFile` (built into pwsh), Pester 5 for tests. No external packages.

---

## File Structure

**Create (skill):**
- `skills/bc-symbol-lookup/SKILL.md` — thin skill manifest with frontmatter
- `skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1` — stdio MCP server entry point (argument parsing, stdio loop, dispatch to tool handlers)
- `skills/bc-symbol-lookup/server/lib/AppFileReader.ps1` — strip 40-byte header, unzip, detect and unwrap Ready2Run, extract `SymbolReference.json` and optional `src/` files
- `skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1` — walk `Namespaces` tree, build flat index, answer lookup queries
- `skills/bc-symbol-lookup/server/lib/Tools.ps1` — one handler function per MCP tool, returns structured result objects
- `skills/bc-symbol-lookup/server/lib/McpServer.ps1` — JSON-RPC stdio loop, request/response framing, error mapping

**Create (tests):**
- `tests/bc-symbol-lookup/fixtures/README.md` — describes how fixtures were captured
- `tests/bc-symbol-lookup/fixtures/minimal-flat.app` — hand-crafted tiny `.app` with one Table, one Page, one Codeunit (not Ready2Run)
- `tests/bc-symbol-lookup/fixtures/minimal-r2r.app` — same content but wrapped in Ready2Run outer layer
- `tests/bc-symbol-lookup/fixtures/corrupt.app` — truncated file for negative testing
- `tests/bc-symbol-lookup/Make-Fixtures.ps1` — script that generates the three fixtures above from in-script JSON (makes the tests hermetic)
- `tests/bc-symbol-lookup/AppFileReader.Tests.ps1` — Pester tests for header strip, Ready2Run detection, zip extraction
- `tests/bc-symbol-lookup/SymbolIndex.Tests.ps1` — Pester tests for namespace walk, flat-index queries
- `tests/bc-symbol-lookup/Tools.Tests.ps1` — Pester tests for each tool handler against the minimal fixtures
- `tests/bc-symbol-lookup/McpServer.Tests.ps1` — subprocess spawn test: send JSON-RPC `tools/list` and `tools/call` to the real server, assert responses

**Modify:** None.

---

## Dependencies and ordering

Tasks 1–3 build infrastructure (header strip, test fixtures, zip extraction). Tasks 4–6 build the index. Tasks 7–12 build the six tool handlers, one per tool, each with its own test. Task 13 wires up the MCP server loop. Task 14 end-to-end subprocess test. Task 15 skill manifest. Task 16 verification and smoke test against a real `.app` file from `bcartifacts.cache`.

---

### Task 1: Scaffold skill directory and empty files

**Files:**
- Create: `skills/bc-symbol-lookup/SKILL.md` (placeholder, filled in Task 15)
- Create: `skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1` (placeholder, filled in Task 13)
- Create: `skills/bc-symbol-lookup/server/lib/AppFileReader.ps1` (empty)
- Create: `skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1` (empty)
- Create: `skills/bc-symbol-lookup/server/lib/Tools.ps1` (empty)
- Create: `skills/bc-symbol-lookup/server/lib/McpServer.ps1` (empty)
- Create: `tests/bc-symbol-lookup/fixtures/README.md`

- [ ] **Step 1: Create directory tree and stub files**

Run (PowerShell):

```powershell
$dirs = @(
  'skills/bc-symbol-lookup/server/lib',
  'tests/bc-symbol-lookup/fixtures'
)
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

$files = @(
  'skills/bc-symbol-lookup/SKILL.md',
  'skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1',
  'skills/bc-symbol-lookup/server/lib/AppFileReader.ps1',
  'skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1',
  'skills/bc-symbol-lookup/server/lib/Tools.ps1',
  'skills/bc-symbol-lookup/server/lib/McpServer.ps1'
)
$files | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType File -Path $_ | Out-Null } }

Set-Content -Path 'tests/bc-symbol-lookup/fixtures/README.md' -Value "# Fixtures`r`n`r`nGenerated by ``Make-Fixtures.ps1``. Do not edit by hand."
```

- [ ] **Step 2: Commit**

```bash
git add skills/bc-symbol-lookup tests/bc-symbol-lookup
git commit -m "feat(bc-symbol-lookup): scaffold skill directory"
```

---

### Task 2: Build `Make-Fixtures.ps1` — generate minimal flat `.app`

**Files:**
- Create: `tests/bc-symbol-lookup/Make-Fixtures.ps1`
- Create: `tests/bc-symbol-lookup/fixtures/minimal-flat.app` (output of the script)

**Background.** A real BC `.app` file is: 40-byte header (zeros are fine for tests) + standard zip bytes. The inner zip must contain `NavxManifest.xml` and `SymbolReference.json` at minimum. We skip `NavxManifest.xml` contents (we don't parse it) but include a byte of it so the zip isn't empty.

- [ ] **Step 1: Write the fixture generator script**

Write `tests/bc-symbol-lookup/Make-Fixtures.ps1` with this exact content:

```powershell
#requires -Version 7.0
<#
Generates hermetic .app fixture files for bc-symbol-lookup tests.
A .app file is a 40-byte header followed by standard zip bytes.
v28 Ready2Run wraps another .app inside an outer zip containing
readytorunappmanifest.json.
#>
[CmdletBinding()]
param(
    [string] $OutputDir = (Join-Path $PSScriptRoot 'fixtures')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-HeaderedZip {
    param(
        [hashtable] $Entries,       # filename -> string content
        [string]    $OutputPath
    )
    $tempZip = [IO.Path]::GetTempFileName() + '.zip'
    try {
        $zip = [IO.Compression.ZipFile]::Open($tempZip, 'Create')
        try {
            foreach ($name in $Entries.Keys) {
                $entry = $zip.CreateEntry($name)
                $stream = $entry.Open()
                try {
                    $writer = [IO.StreamWriter]::new($stream, [Text.Encoding]::UTF8)
                    $writer.Write([string]$Entries[$name])
                    $writer.Flush()
                } finally {
                    $stream.Dispose()
                }
            }
        } finally {
            $zip.Dispose()
        }
        $zipBytes = [IO.File]::ReadAllBytes($tempZip)
        $header = New-Object byte[] 40
        $final = New-Object byte[] ($header.Length + $zipBytes.Length)
        [Array]::Copy($header, 0, $final, 0, 40)
        [Array]::Copy($zipBytes, 0, $final, 40, $zipBytes.Length)
        [IO.File]::WriteAllBytes($OutputPath, $final)
    } finally {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    }
}

# Minimal SymbolReference.json with one Table, one Page, one Codeunit.
# Namespace nesting intentional to match v28 tree shape.
$symbolJson = @'
{
  "RuntimeVersion": "16.0",
  "AppId": "11111111-1111-1111-1111-111111111111",
  "Name": "Fixture Minimal App",
  "Publisher": "Fixture Publisher",
  "Version": "1.0.0.0",
  "Namespaces": [
    {
      "Name": "Fixture",
      "Namespaces": [],
      "Tables": [
        {
          "Id": 50100,
          "Name": "Fixture Table",
          "Fields": [
            { "Id": 1, "Name": "No.", "TypeDefinition": { "Name": "Code", "Length": 20 } },
            { "Id": 2, "Name": "Description", "TypeDefinition": { "Name": "Text", "Length": 100 } }
          ]
        }
      ],
      "Pages": [
        {
          "Id": 50100,
          "Name": "Fixture Card",
          "SourceTable": "Fixture Table"
        }
      ],
      "Codeunits": [
        {
          "Id": 50100,
          "Name": "Fixture Helper",
          "Methods": [
            {
              "Name": "DoStuff",
              "IsLocal": false,
              "IsInternal": false,
              "Parameters": [
                { "Name": "Input", "IsVar": false, "TypeDefinition": { "Name": "Integer" } }
              ],
              "ReturnTypeDefinition": { "Name": "Boolean" }
            }
          ]
        }
      ]
    }
  ],
  "Tables": [],
  "Pages": [],
  "Codeunits": [],
  "Enums": [],
  "Interfaces": []
}
'@

$navxManifest = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/navx/2015/manifest">
  <App Id="11111111-1111-1111-1111-111111111111" Name="Fixture Minimal App" Publisher="Fixture Publisher" Version="1.0.0.0" />
</Package>
'@

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Flat fixture (no Ready2Run wrapping)
$flatPath = Join-Path $OutputDir 'minimal-flat.app'
New-HeaderedZip -OutputPath $flatPath -Entries @{
    'SymbolReference.json' = $symbolJson
    'NavxManifest.xml'     = $navxManifest
}
Write-Host "Wrote $flatPath"

# Ready2Run fixture — outer zip with an inner minimal-flat.app
$innerBytes = [IO.File]::ReadAllBytes($flatPath)
$innerBase64 = [Convert]::ToBase64String($innerBytes)
$r2rManifest = @'
{
  "Name": "Fixture Minimal App",
  "Publisher": "Fixture Publisher",
  "Version": "1.0.0.0",
  "TargetVersions": ["28.0"]
}
'@
# Outer zip needs to contain the inner .app as binary, so we write it out then embed.
$innerTempName = 'publishedartifacts/11111111-1111-1111-1111-111111111111_1.0.0.0_1_0.app'
$r2rPath = Join-Path $OutputDir 'minimal-r2r.app'

# For binary embedding we need a custom writer path — open the outer zip and copy the raw bytes.
$tempZip = [IO.Path]::GetTempFileName() + '.zip'
try {
    $zip = [IO.Compression.ZipFile]::Open($tempZip, 'Create')
    try {
        # readytorunappmanifest.json
        $manifestEntry = $zip.CreateEntry('readytorunappmanifest.json')
        $ms = $manifestEntry.Open()
        $bytes = [Text.Encoding]::UTF8.GetBytes($r2rManifest)
        $ms.Write($bytes, 0, $bytes.Length)
        $ms.Dispose()

        # inner .app (binary)
        $innerEntry = $zip.CreateEntry($innerTempName)
        $is = $innerEntry.Open()
        $is.Write($innerBytes, 0, $innerBytes.Length)
        $is.Dispose()
    } finally {
        $zip.Dispose()
    }
    $outerBytes = [IO.File]::ReadAllBytes($tempZip)
    $header = New-Object byte[] 40
    $final = New-Object byte[] ($header.Length + $outerBytes.Length)
    [Array]::Copy($header, 0, $final, 0, 40)
    [Array]::Copy($outerBytes, 0, $final, 40, $outerBytes.Length)
    [IO.File]::WriteAllBytes($r2rPath, $final)
} finally {
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
}
Write-Host "Wrote $r2rPath"

# Corrupt fixture — first 20 bytes of a real .app then truncated
$corruptPath = Join-Path $OutputDir 'corrupt.app'
$corruptBytes = [IO.File]::ReadAllBytes($flatPath)[0..19]
[IO.File]::WriteAllBytes($corruptPath, $corruptBytes)
Write-Host "Wrote $corruptPath"
```

- [ ] **Step 2: Run the fixture generator**

Run: `pwsh -NoProfile -File tests/bc-symbol-lookup/Make-Fixtures.ps1`

Expected output:

```
Wrote ...\tests\bc-symbol-lookup\fixtures\minimal-flat.app
Wrote ...\tests\bc-symbol-lookup\fixtures\minimal-r2r.app
Wrote ...\tests\bc-symbol-lookup\fixtures\corrupt.app
```

- [ ] **Step 3: Verify fixture files exist and have expected shape**

Run:
```
pwsh -NoProfile -Command "Get-ChildItem tests/bc-symbol-lookup/fixtures/*.app | Select-Object Name, Length"
```

Expected: three rows — `minimal-flat.app` (a few hundred bytes), `minimal-r2r.app` (a few hundred bytes, larger than flat), `corrupt.app` (20 bytes).

- [ ] **Step 4: Commit**

```bash
git add tests/bc-symbol-lookup/Make-Fixtures.ps1 tests/bc-symbol-lookup/fixtures
git commit -m "test(bc-symbol-lookup): generate .app fixtures"
```

---

### Task 3: `AppFileReader.ps1` — strip header, extract inner JSON

**Files:**
- Create: `tests/bc-symbol-lookup/AppFileReader.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/AppFileReader.ps1`

- [ ] **Step 1: Write failing Pester tests for `Read-AppSymbols`**

Write `tests/bc-symbol-lookup/AppFileReader.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot/../../skills/bc-symbol-lookup/server/lib/AppFileReader.ps1"
    $script:fixturesDir = "$PSScriptRoot/fixtures"
}

Describe 'Read-AppSymbols' {
    It 'extracts SymbolReference.json from a flat .app file' {
        $result = Read-AppSymbols -Path "$fixturesDir/minimal-flat.app"
        $result | Should -Not -BeNullOrEmpty
        $result.SymbolJson | Should -Not -BeNullOrEmpty
        $parsed = $result.SymbolJson | ConvertFrom-Json
        $parsed.Name | Should -Be 'Fixture Minimal App'
        $parsed.AppId | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'extracts SymbolReference.json from a Ready2Run-wrapped .app file' {
        $result = Read-AppSymbols -Path "$fixturesDir/minimal-r2r.app"
        $result | Should -Not -BeNullOrEmpty
        $parsed = $result.SymbolJson | ConvertFrom-Json
        $parsed.Name | Should -Be 'Fixture Minimal App'
    }

    It 'throws a clear error on a corrupt .app file' {
        { Read-AppSymbols -Path "$fixturesDir/corrupt.app" } |
            Should -Throw -ExpectedMessage '*corrupt*'
    }

    It 'returns null (not throw) when SymbolReference.json is missing' {
        $emptyZip = [IO.Path]::GetTempFileName() + '.app'
        try {
            $header = New-Object byte[] 40
            $tempZip = [IO.Path]::GetTempFileName() + '.zip'
            $z = [IO.Compression.ZipFile]::Open($tempZip, 'Create')
            $z.CreateEntry('NavxManifest.xml') | Out-Null
            $z.Dispose()
            $zb = [IO.File]::ReadAllBytes($tempZip)
            $final = New-Object byte[] ($header.Length + $zb.Length)
            [Array]::Copy($header, 0, $final, 0, 40)
            [Array]::Copy($zb, 0, $final, 40, $zb.Length)
            [IO.File]::WriteAllBytes($emptyZip, $final)
            Remove-Item $tempZip -Force

            $result = Read-AppSymbols -Path $emptyZip
            $result | Should -BeNullOrEmpty
        } finally {
            Remove-Item $emptyZip -Force -ErrorAction SilentlyContinue
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/AppFileReader.Tests.ps1 -Output Detailed"`
Expected: all four tests fail with "Read-AppSymbols is not recognized" or similar.

- [ ] **Step 3: Implement `Read-AppSymbols`**

Write `skills/bc-symbol-lookup/server/lib/AppFileReader.ps1` with this exact content:

```powershell
#requires -Version 7.0
<#
AppFileReader.ps1 — Read SymbolReference.json from a Business Central .app file.

A .app file is:
  - 40-byte header (we skip)
  - followed by a standard zip

v28 "Ready2Run" wrapping: the outer zip contains:
  - readytorunappmanifest.json
  - publishedartifacts/<guid>_<ver>_<maj>_<build>.app   (inner, also header-prefixed)

We handle both shapes transparently: strip outer header, try to read SymbolReference.json
from the outer zip; if not present, detect Ready2Run by presence of readytorunappmanifest.json,
find the inner .app entry, strip its 40-byte header, read SymbolReference.json from it.
#>

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-AppSymbols {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 44) {
        throw "File is corrupt (too small to contain 40-byte header + zip): $Path"
    }

    $zipBytes = New-Object byte[] ($bytes.Length - 40)
    [Array]::Copy($bytes, 40, $zipBytes, 0, $zipBytes.Length)

    try {
        $ms = [IO.MemoryStream]::new($zipBytes)
        $zip = [IO.Compression.ZipArchive]::new($ms, [IO.Compression.ZipArchiveMode]::Read)
    } catch {
        throw "File is corrupt (not a valid zip after header strip): $Path — $($_.Exception.Message)"
    }

    try {
        $symbolEntry = $zip.Entries | Where-Object { $_.FullName -ieq 'SymbolReference.json' } | Select-Object -First 1

        if ($symbolEntry) {
            $symbolJson = _ReadEntryText $symbolEntry
            return [pscustomobject]@{
                SymbolJson = $symbolJson
                IsReadyToRun = $false
                SourcePath = $Path
            }
        }

        # Not in outer — check for Ready2Run wrapping
        $r2rManifest = $zip.Entries | Where-Object { $_.FullName -ieq 'readytorunappmanifest.json' } | Select-Object -First 1
        if (-not $r2rManifest) {
            return $null
        }

        $innerEntry = $zip.Entries | Where-Object { $_.FullName -like 'publishedartifacts/*.app' } | Select-Object -First 1
        if (-not $innerEntry) {
            return $null
        }

        $innerBytes = _ReadEntryBytes $innerEntry
        if ($innerBytes.Length -lt 44) {
            throw "Ready2Run inner .app is corrupt: $Path"
        }
        $innerZipBytes = New-Object byte[] ($innerBytes.Length - 40)
        [Array]::Copy($innerBytes, 40, $innerZipBytes, 0, $innerZipBytes.Length)

        $innerMs = [IO.MemoryStream]::new($innerZipBytes)
        $innerZip = [IO.Compression.ZipArchive]::new($innerMs, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $innerSym = $innerZip.Entries | Where-Object { $_.FullName -ieq 'SymbolReference.json' } | Select-Object -First 1
            if (-not $innerSym) { return $null }
            $symbolJson = _ReadEntryText $innerSym
            return [pscustomobject]@{
                SymbolJson = $symbolJson
                IsReadyToRun = $true
                SourcePath = $Path
            }
        } finally {
            $innerZip.Dispose()
            $innerMs.Dispose()
        }
    } finally {
        $zip.Dispose()
        $ms.Dispose()
    }
}

function _ReadEntryText {
    param([IO.Compression.ZipArchiveEntry] $Entry)
    $s = $Entry.Open()
    try {
        $reader = [IO.StreamReader]::new($s, [Text.Encoding]::UTF8)
        return $reader.ReadToEnd()
    } finally {
        $s.Dispose()
    }
}

function _ReadEntryBytes {
    param([IO.Compression.ZipArchiveEntry] $Entry)
    $s = $Entry.Open()
    try {
        $memory = [IO.MemoryStream]::new()
        $s.CopyTo($memory)
        return $memory.ToArray()
    } finally {
        $s.Dispose()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/AppFileReader.Tests.ps1 -Output Detailed"`
Expected: all four tests pass, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/AppFileReader.ps1 tests/bc-symbol-lookup/AppFileReader.Tests.ps1
git commit -m "feat(bc-symbol-lookup): implement AppFileReader with header strip and Ready2Run support"
```

---

### Task 4: `SymbolIndex.ps1` — walk Namespaces and build flat index

**Files:**
- Create: `tests/bc-symbol-lookup/SymbolIndex.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1`

- [ ] **Step 1: Write failing Pester tests for `New-SymbolIndex` and `Find-IndexedObject`**

Write `tests/bc-symbol-lookup/SymbolIndex.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot/../../skills/bc-symbol-lookup/server/lib/AppFileReader.ps1"
    . "$PSScriptRoot/../../skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1"
    $script:fixturesDir = "$PSScriptRoot/fixtures"
}

Describe 'New-SymbolIndex' {
    It 'indexes the flat fixture and finds the Fixture Table' {
        $index = New-SymbolIndex -PackageCachePath $fixturesDir
        $index | Should -Not -BeNullOrEmpty
        $index.Objects.Count | Should -BeGreaterOrEqual 3
    }

    It 'finds an object by name (case-insensitive)' {
        $index = New-SymbolIndex -PackageCachePath $fixturesDir
        $matches = Find-IndexedObject -Index $index -Name 'fixture table'
        # Two fixtures (flat + r2r) contain the same logical object,
        # so we expect two index entries for this name.
        $matches.Count | Should -BeGreaterOrEqual 1
    }

    It 'filters by type' {
        $index = New-SymbolIndex -PackageCachePath $fixturesDir
        $codeunits = Find-IndexedObject -Index $index -Name 'Fixture Helper' -Type 'Codeunit'
        $codeunits.Count | Should -BeGreaterOrEqual 1
        $codeunits[0].Type | Should -Be 'Codeunit'
    }

    It 'walks nested Namespaces tree' {
        $index = New-SymbolIndex -PackageCachePath $fixturesDir
        $obj = Find-IndexedObject -Index $index -Name 'Fixture Table' | Select-Object -First 1
        $obj.Namespace | Should -Be 'Fixture'
    }

    It 'lists indexed apps' {
        $index = New-SymbolIndex -PackageCachePath $fixturesDir
        $index.Apps.Count | Should -BeGreaterOrEqual 2  # flat + r2r
        $index.Apps[0].Name | Should -Be 'Fixture Minimal App'
    }

    It 'survives a corrupt .app in the folder' {
        { New-SymbolIndex -PackageCachePath $fixturesDir } | Should -Not -Throw
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/SymbolIndex.Tests.ps1 -Output Detailed"`
Expected: all tests fail with "New-SymbolIndex is not recognized".

- [ ] **Step 3: Implement `SymbolIndex.ps1`**

Write `skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1` with this exact content:

```powershell
#requires -Version 7.0
<#
SymbolIndex.ps1 — Build an in-memory flat index over SymbolReference.json trees from
every .app file in a package cache folder.

Index shape:
  [pscustomobject]@{
    Apps    = @([{ Id, Name, Publisher, Version, Path }])
    Objects = @([{ Id, Type, Name, Namespace, FullyQualifiedName, SourceApp, AppVersion,
                    Fields, Procedures, Node }])
  }

`Node` holds the raw JSON PSCustomObject for the object so tool handlers can pull
fields/procedures on demand without re-walking the tree.
#>

function New-SymbolIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageCachePath
    )

    $apps    = New-Object System.Collections.Generic.List[object]
    $objects = New-Object System.Collections.Generic.List[object]

    if (-not (Test-Path $PackageCachePath)) {
        return [pscustomobject]@{ Apps = @(); Objects = @() }
    }

    $appFiles = Get-ChildItem -Path $PackageCachePath -Filter '*.app' -File -ErrorAction SilentlyContinue
    foreach ($file in $appFiles) {
        try {
            $read = Read-AppSymbols -Path $file.FullName
        } catch {
            Write-Warning "Skipping $($file.Name): $($_.Exception.Message)"
            continue
        }
        if (-not $read) { continue }

        try {
            $parsed = $read.SymbolJson | ConvertFrom-Json -Depth 100
        } catch {
            Write-Warning "Skipping $($file.Name): SymbolReference.json parse failed — $($_.Exception.Message)"
            continue
        }

        $apps.Add([pscustomobject]@{
            Id        = $parsed.AppId
            Name      = $parsed.Name
            Publisher = $parsed.Publisher
            Version   = $parsed.Version
            Path      = $file.FullName
        })

        _WalkNamespaces -Node $parsed -NamespacePath '' -SourceAppName $parsed.Name -SourceAppVersion $parsed.Version -Sink $objects
    }

    return [pscustomobject]@{
        Apps    = $apps.ToArray()
        Objects = $objects.ToArray()
    }
}

function _WalkNamespaces {
    param(
        [Parameter(Mandatory)] $Node,
        [string] $NamespacePath,
        [string] $SourceAppName,
        [string] $SourceAppVersion,
        [Parameter(Mandatory)] $Sink
    )

    $objectKinds = @(
        @{ Property = 'Tables';          Type = 'Table' },
        @{ Property = 'TableExtensions'; Type = 'TableExtension' },
        @{ Property = 'Pages';           Type = 'Page' },
        @{ Property = 'PageExtensions';  Type = 'PageExtension' },
        @{ Property = 'Codeunits';       Type = 'Codeunit' },
        @{ Property = 'Reports';         Type = 'Report' },
        @{ Property = 'Queries';         Type = 'Query' },
        @{ Property = 'XmlPorts';        Type = 'XmlPort' },
        @{ Property = 'Enums';           Type = 'Enum' },
        @{ Property = 'EnumExtensions';  Type = 'EnumExtension' },
        @{ Property = 'Interfaces';      Type = 'Interface' },
        @{ Property = 'ControlAddIns';   Type = 'ControlAddIn' },
        @{ Property = 'PermissionSets';  Type = 'PermissionSet' },
        @{ Property = 'ReportExtensions'; Type = 'ReportExtension' }
    )

    foreach ($kind in $objectKinds) {
        $arr = $Node.PSObject.Properties[$kind.Property]
        if ($arr -and $arr.Value) {
            foreach ($obj in $arr.Value) {
                $name = if ($obj.Name) { $obj.Name } else { "<unnamed>" }
                $id   = if ($obj.PSObject.Properties['Id']) { $obj.Id } else { $null }
                $fqn  = if ($NamespacePath) { "$NamespacePath.$name" } else { $name }
                $Sink.Add([pscustomobject]@{
                    Id                 = $id
                    Type               = $kind.Type
                    Name               = $name
                    Namespace          = $NamespacePath
                    FullyQualifiedName = $fqn
                    SourceApp          = $SourceAppName
                    AppVersion         = $SourceAppVersion
                    Node               = $obj
                })
            }
        }
    }

    # Recurse into nested namespaces
    $nsProp = $Node.PSObject.Properties['Namespaces']
    if ($nsProp -and $nsProp.Value) {
        foreach ($ns in $nsProp.Value) {
            $childPath = if ($ns.Name) {
                if ($NamespacePath) { "$NamespacePath.$($ns.Name)" } else { $ns.Name }
            } else {
                $NamespacePath
            }
            _WalkNamespaces -Node $ns -NamespacePath $childPath -SourceAppName $SourceAppName -SourceAppVersion $SourceAppVersion -Sink $Sink
        }
    }
}

function Find-IndexedObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [Parameter(Mandatory)] [string] $Name,
        [string] $Type
    )
    $results = $Index.Objects | Where-Object { $_.Name -ieq $Name -or $_.Name -ilike $Name }
    if ($Type) {
        $results = $results | Where-Object { $_.Type -ieq $Type }
    }
    return @($results)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/SymbolIndex.Tests.ps1 -Output Detailed"`
Expected: all six tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1 tests/bc-symbol-lookup/SymbolIndex.Tests.ps1
git commit -m "feat(bc-symbol-lookup): implement SymbolIndex with namespace walker"
```

---

### Task 5: `Tools.ps1` — `bc_list_apps` handler

**Files:**
- Create: `tests/bc-symbol-lookup/Tools.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/Tools.ps1`

- [ ] **Step 1: Write failing Pester test for `Invoke-BcListAppsTool`**

Write `tests/bc-symbol-lookup/Tools.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . "$PSScriptRoot/../../skills/bc-symbol-lookup/server/lib/AppFileReader.ps1"
    . "$PSScriptRoot/../../skills/bc-symbol-lookup/server/lib/SymbolIndex.ps1"
    . "$PSScriptRoot/../../skills/bc-symbol-lookup/server/lib/Tools.ps1"
    $script:fixturesDir = "$PSScriptRoot/fixtures"
    $script:index = New-SymbolIndex -PackageCachePath $fixturesDir
}

Describe 'Invoke-BcListAppsTool' {
    It 'returns the apps list with expected fields' {
        $result = Invoke-BcListAppsTool -Index $index -Args @{}
        $result.apps | Should -Not -BeNullOrEmpty
        $result.apps[0].name | Should -Be 'Fixture Minimal App'
        $result.apps[0].publisher | Should -Be 'Fixture Publisher'
        $result.apps[0].version | Should -Be '1.0.0.0'
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: fail with "Invoke-BcListAppsTool is not recognized".

- [ ] **Step 3: Implement `Invoke-BcListAppsTool`**

Write `skills/bc-symbol-lookup/server/lib/Tools.ps1` with this exact content:

```powershell
#requires -Version 7.0
<#
Tools.ps1 — MCP tool handlers for bc-symbol-lookup.

Each handler takes `-Index` (a SymbolIndex) and `-Args` (a hashtable from the MCP
tool call) and returns a PSCustomObject that gets JSON-serialized as the tool result.

Never throw — wrap errors in { error = ... } return values so the agent gets structured
feedback instead of a protocol-level crash.
#>

function Invoke-BcListAppsTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )
    return [pscustomobject]@{
        apps = @($Index.Apps | ForEach-Object {
            [pscustomobject]@{
                id        = $_.Id
                name      = $_.Name
                publisher = $_.Publisher
                version   = $_.Version
                path      = $_.Path
            }
        })
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/Tools.ps1 tests/bc-symbol-lookup/Tools.Tests.ps1
git commit -m "feat(bc-symbol-lookup): implement bc_list_apps tool"
```

---

### Task 6: `bc_find_object` handler

**Files:**
- Modify: `tests/bc-symbol-lookup/Tools.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/Tools.ps1`

- [ ] **Step 1: Add failing test for `Invoke-BcFindObjectTool`**

Append to `tests/bc-symbol-lookup/Tools.Tests.ps1` (before the closing of the file — just add a new `Describe` block after the existing one):

```powershell
Describe 'Invoke-BcFindObjectTool' {
    It 'finds Fixture Table by exact name' {
        $result = Invoke-BcFindObjectTool -Index $index -Args @{ name = 'Fixture Table' }
        $result.objects.Count | Should -BeGreaterOrEqual 1
        $result.objects[0].type | Should -Be 'Table'
        $result.objects[0].id | Should -Be 50100
    }

    It 'filters by type' {
        $result = Invoke-BcFindObjectTool -Index $index -Args @{ name = 'Fixture'; type = 'Codeunit' }
        $result.objects | ForEach-Object { $_.type | Should -Be 'Codeunit' }
    }

    It 'supports wildcard matching' {
        $result = Invoke-BcFindObjectTool -Index $index -Args @{ name = 'Fix*' }
        $result.objects.Count | Should -BeGreaterOrEqual 3  # Table, Page, Codeunit (at least)
    }

    It 'returns empty array on no match' {
        $result = Invoke-BcFindObjectTool -Index $index -Args @{ name = 'NoSuchObject' }
        $result.objects.Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 4 new tests fail with "Invoke-BcFindObjectTool is not recognized".

- [ ] **Step 3: Implement `Invoke-BcFindObjectTool`**

Append to `skills/bc-symbol-lookup/server/lib/Tools.ps1`:

```powershell
function Invoke-BcFindObjectTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $name = [string]$Args['name']
    if (-not $name) {
        return [pscustomobject]@{ error = "Parameter 'name' is required" }
    }
    $type = [string]$Args['type']

    $results = $Index.Objects | Where-Object {
        $_.Name -ilike $name
    }
    if ($type) {
        $results = $results | Where-Object { $_.Type -ieq $type }
    }

    return [pscustomobject]@{
        objects = @($results | ForEach-Object {
            [pscustomobject]@{
                id                 = $_.Id
                type               = $_.Type
                name               = $_.Name
                namespace          = $_.Namespace
                fullyQualifiedName = $_.FullyQualifiedName
                sourceApp          = $_.SourceApp
                appVersion         = $_.AppVersion
            }
        })
    }
}
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 5 tests pass (1 from Task 5 + 4 new).

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/Tools.ps1 tests/bc-symbol-lookup/Tools.Tests.ps1
git commit -m "feat(bc-symbol-lookup): implement bc_find_object tool"
```

---

### Task 7: `bc_get_fields` handler

**Files:**
- Modify: `tests/bc-symbol-lookup/Tools.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/Tools.ps1`

- [ ] **Step 1: Add failing test for `Invoke-BcGetFieldsTool`**

Append to `tests/bc-symbol-lookup/Tools.Tests.ps1`:

```powershell
Describe 'Invoke-BcGetFieldsTool' {
    It 'returns fields of Fixture Table' {
        $result = Invoke-BcGetFieldsTool -Index $index -Args @{ objectName = 'Fixture Table'; type = 'Table' }
        $result.fields.Count | Should -Be 2
        $result.fields[0].id | Should -Be 1
        $result.fields[0].name | Should -Be 'No.'
        $result.fields[0].typeName | Should -Be 'Code'
        $result.fields[0].typeLength | Should -Be 20
    }

    It 'filters fields by substring' {
        $result = Invoke-BcGetFieldsTool -Index $index -Args @{ objectName = 'Fixture Table'; type = 'Table'; filter = 'Desc' }
        $result.fields.Count | Should -Be 1
        $result.fields[0].name | Should -Be 'Description'
    }

    It 'returns error when object not found' {
        $result = Invoke-BcGetFieldsTool -Index $index -Args @{ objectName = 'Nope'; type = 'Table' }
        $result.error | Should -Not -BeNullOrEmpty
    }

    It 'returns error when object has no fields (wrong type)' {
        $result = Invoke-BcGetFieldsTool -Index $index -Args @{ objectName = 'Fixture Helper'; type = 'Codeunit' }
        $result.error | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 4 new tests fail.

- [ ] **Step 3: Implement `Invoke-BcGetFieldsTool`**

Append to `skills/bc-symbol-lookup/server/lib/Tools.ps1`:

```powershell
function Invoke-BcGetFieldsTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $objectName = [string]$Args['objectName']
    $objectId   = $Args['objectId']
    $type       = [string]$Args['type']
    $filter     = [string]$Args['filter']

    if (-not $type) {
        return [pscustomobject]@{ error = "Parameter 'type' is required (e.g., 'Table' or 'TableExtension')" }
    }
    if ($type -ne 'Table' -and $type -ne 'TableExtension') {
        return [pscustomobject]@{ error = "bc_get_fields only supports type Table or TableExtension (got: $type)" }
    }

    $match = $Index.Objects | Where-Object {
        $_.Type -ieq $type -and (
            ($objectName -and $_.Name -ieq $objectName) -or
            ($objectId -and $_.Id -eq $objectId)
        )
    } | Select-Object -First 1

    if (-not $match) {
        return [pscustomobject]@{ error = "Object not found: $type '$objectName' (id=$objectId)" }
    }

    $fieldsProp = $match.Node.PSObject.Properties['Fields']
    if (-not $fieldsProp -or -not $fieldsProp.Value) {
        return [pscustomobject]@{ error = "Object has no fields: $type '$objectName'" }
    }

    $fields = $fieldsProp.Value | ForEach-Object {
        $td = $_.TypeDefinition
        [pscustomobject]@{
            id         = $_.Id
            name       = $_.Name
            typeName   = if ($td) { $td.Name } else { $null }
            typeLength = if ($td -and $td.PSObject.Properties['Length']) { $td.Length } else { $null }
            enabled    = if ($_.PSObject.Properties['Enabled']) { $_.Enabled } else { $true }
        }
    }

    if ($filter) {
        $fields = $fields | Where-Object { $_.name -ilike "*$filter*" }
    }

    return [pscustomobject]@{ fields = @($fields) }
}
```

- [ ] **Step 4: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/Tools.ps1 tests/bc-symbol-lookup/Tools.Tests.ps1
git commit -m "feat(bc-symbol-lookup): implement bc_get_fields tool"
```

---

### Task 8: `bc_get_procedures` handler

**Files:**
- Modify: `tests/bc-symbol-lookup/Tools.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/Tools.ps1`

- [ ] **Step 1: Add failing test**

Append to `tests/bc-symbol-lookup/Tools.Tests.ps1`:

```powershell
Describe 'Invoke-BcGetProceduresTool' {
    It 'returns procedures of Fixture Helper codeunit' {
        $result = Invoke-BcGetProceduresTool -Index $index -Args @{ objectName = 'Fixture Helper'; type = 'Codeunit' }
        $result.procedures.Count | Should -Be 1
        $result.procedures[0].name | Should -Be 'DoStuff'
        $result.procedures[0].scope | Should -Be 'Public'
        $result.procedures[0].parameters.Count | Should -Be 1
        $result.procedures[0].parameters[0].name | Should -Be 'Input'
        $result.procedures[0].parameters[0].typeName | Should -Be 'Integer'
        $result.procedures[0].returnType | Should -Be 'Boolean'
    }

    It 'returns error when codeunit not found' {
        $result = Invoke-BcGetProceduresTool -Index $index -Args @{ objectName = 'NoSuch'; type = 'Codeunit' }
        $result.error | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 2 new tests fail.

- [ ] **Step 3: Implement `Invoke-BcGetProceduresTool`**

Append to `skills/bc-symbol-lookup/server/lib/Tools.ps1`:

```powershell
function Invoke-BcGetProceduresTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $objectName = [string]$Args['objectName']
    $objectId   = $Args['objectId']
    $type       = [string]$Args['type']
    $filter     = [string]$Args['filter']

    if (-not $type) {
        return [pscustomobject]@{ error = "Parameter 'type' is required (e.g., 'Codeunit' or 'Page')" }
    }

    $match = $Index.Objects | Where-Object {
        $_.Type -ieq $type -and (
            ($objectName -and $_.Name -ieq $objectName) -or
            ($objectId -and $_.Id -eq $objectId)
        )
    } | Select-Object -First 1

    if (-not $match) {
        return [pscustomobject]@{ error = "Object not found: $type '$objectName' (id=$objectId)" }
    }

    $methodsProp = $match.Node.PSObject.Properties['Methods']
    if (-not $methodsProp -or -not $methodsProp.Value) {
        return [pscustomobject]@{ procedures = @() }
    }

    $procs = $methodsProp.Value | ForEach-Object {
        $m = $_
        $scope =
            if ($m.PSObject.Properties['IsLocal'] -and $m.IsLocal) { 'Local' }
            elseif ($m.PSObject.Properties['IsInternal'] -and $m.IsInternal) { 'Internal' }
            else { 'Public' }

        $params = @()
        if ($m.PSObject.Properties['Parameters'] -and $m.Parameters) {
            $params = $m.Parameters | ForEach-Object {
                [pscustomobject]@{
                    name     = $_.Name
                    typeName = if ($_.TypeDefinition) { $_.TypeDefinition.Name } else { $null }
                    isVar    = if ($_.PSObject.Properties['IsVar']) { [bool]$_.IsVar } else { $false }
                }
            }
        }

        $returnType = $null
        if ($m.PSObject.Properties['ReturnTypeDefinition'] -and $m.ReturnTypeDefinition) {
            $returnType = $m.ReturnTypeDefinition.Name
        }

        [pscustomobject]@{
            name       = $m.Name
            scope      = $scope
            parameters = @($params)
            returnType = $returnType
        }
    }

    if ($filter) {
        $procs = $procs | Where-Object { $_.name -ilike "*$filter*" }
    }

    return [pscustomobject]@{ procedures = @($procs) }
}
```

- [ ] **Step 4: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/Tools.ps1 tests/bc-symbol-lookup/Tools.Tests.ps1
git commit -m "feat(bc-symbol-lookup): implement bc_get_procedures tool"
```

---

### Task 9: `bc_search` handler

**Files:**
- Modify: `tests/bc-symbol-lookup/Tools.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/Tools.ps1`

- [ ] **Step 1: Add failing test**

Append to `tests/bc-symbol-lookup/Tools.Tests.ps1`:

```powershell
Describe 'Invoke-BcSearchTool' {
    It 'finds objects by free-text query' {
        $result = Invoke-BcSearchTool -Index $index -Args @{ query = 'fixture' }
        $result.results.Count | Should -BeGreaterOrEqual 3
    }

    It 'respects the limit parameter' {
        $result = Invoke-BcSearchTool -Index $index -Args @{ query = 'fixture'; limit = 1 }
        $result.results.Count | Should -Be 1
    }

    It 'returns empty results with no match' {
        $result = Invoke-BcSearchTool -Index $index -Args @{ query = 'zzzzzzz' }
        $result.results.Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 3 new tests fail.

- [ ] **Step 3: Implement `Invoke-BcSearchTool`**

Append to `skills/bc-symbol-lookup/server/lib/Tools.ps1`:

```powershell
function Invoke-BcSearchTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $query = [string]$Args['query']
    if (-not $query) {
        return [pscustomobject]@{ error = "Parameter 'query' is required" }
    }
    $limit = if ($Args['limit']) { [int]$Args['limit'] } else { 25 }

    $ql = $query.ToLowerInvariant()
    $hits = $Index.Objects | ForEach-Object {
        $nameLower = $_.Name.ToLowerInvariant()
        $score =
            if ($nameLower -eq $ql) { 100 }
            elseif ($nameLower.StartsWith($ql)) { 75 }
            elseif ($nameLower.Contains($ql)) { 50 }
            else { 0 }
        if ($score -gt 0) {
            [pscustomobject]@{
                score      = $score
                id         = $_.Id
                type       = $_.Type
                name       = $_.Name
                namespace  = $_.Namespace
                sourceApp  = $_.SourceApp
                appVersion = $_.AppVersion
            }
        }
    } | Sort-Object -Property score -Descending | Select-Object -First $limit

    return [pscustomobject]@{ results = @($hits) }
}
```

- [ ] **Step 4: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/Tools.ps1 tests/bc-symbol-lookup/Tools.Tests.ps1
git commit -m "feat(bc-symbol-lookup): implement bc_search tool"
```

---

### Task 10: `bc_get_object_source` handler (stub that returns null for v1)

**Files:**
- Modify: `tests/bc-symbol-lookup/Tools.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/Tools.ps1`

**Note.** v1 ships this tool as a declared-but-null endpoint. The fixtures don't include `src/*.al` files, and full source retrieval from real `.app` files is a v2 feature. The tool must exist so the MCP schema is stable; it returns `{ source: null, reason: "source retrieval not implemented in v1" }`.

- [ ] **Step 1: Add failing test**

Append to `tests/bc-symbol-lookup/Tools.Tests.ps1`:

```powershell
Describe 'Invoke-BcGetObjectSourceTool' {
    It 'returns null source with a reason in v1' {
        $result = Invoke-BcGetObjectSourceTool -Index $index -Args @{ objectName = 'Fixture Table'; type = 'Table' }
        $result.source | Should -BeNullOrEmpty
        $result.reason | Should -Match 'not implemented'
    }

    It 'returns error when object not found' {
        $result = Invoke-BcGetObjectSourceTool -Index $index -Args @{ objectName = 'NoSuch'; type = 'Table' }
        $result.error | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 2 new tests fail.

- [ ] **Step 3: Implement `Invoke-BcGetObjectSourceTool`**

Append to `skills/bc-symbol-lookup/server/lib/Tools.ps1`:

```powershell
function Invoke-BcGetObjectSourceTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Index,
        [hashtable] $Args = @{}
    )

    $objectName = [string]$Args['objectName']
    $type       = [string]$Args['type']

    $match = $Index.Objects | Where-Object {
        $_.Type -ieq $type -and $_.Name -ieq $objectName
    } | Select-Object -First 1

    if (-not $match) {
        return [pscustomobject]@{ error = "Object not found: $type '$objectName'" }
    }

    return [pscustomobject]@{
        source = $null
        reason = 'Source retrieval not implemented in v1 — see roadmap'
    }
}
```

- [ ] **Step 4: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/Tools.Tests.ps1 -Output Detailed"`
Expected: 16 tests pass.

- [ ] **Step 5: Commit**

```bash
git add skills/bc-symbol-lookup/server/lib/Tools.ps1 tests/bc-symbol-lookup/Tools.Tests.ps1
git commit -m "feat(bc-symbol-lookup): stub bc_get_object_source for v1"
```

---

### Task 11: `McpServer.ps1` — JSON-RPC stdio loop

**Files:**
- Create: `tests/bc-symbol-lookup/McpServer.Tests.ps1`
- Modify: `skills/bc-symbol-lookup/server/lib/McpServer.ps1`

- [ ] **Step 1: Write failing test that spawns a subprocess and sends `tools/list`**

Write `tests/bc-symbol-lookup/McpServer.Tests.ps1` with this exact content:

```powershell
#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:fixturesDir = "$PSScriptRoot/fixtures"
    $script:serverPath  = "$PSScriptRoot/../../skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1"
}

function Invoke-McpRequest {
    param(
        [string] $ServerPath,
        [string] $PackageCachePath,
        [object[]] $Requests
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'pwsh'
    $psi.Arguments = "-NoProfile -File `"$ServerPath`" -PackageCachePath `"$PackageCachePath`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)

    foreach ($req in $Requests) {
        $line = $req | ConvertTo-Json -Depth 20 -Compress
        $proc.StandardInput.WriteLine($line)
    }
    $proc.StandardInput.Close()

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit(10000) | Out-Null
    return [pscustomobject]@{
        Stdout = $stdout
        Stderr = $stderr
        ExitCode = $proc.ExitCode
    }
}

Describe 'MCP server stdio protocol' {
    It 'responds to tools/list with six tools' {
        $req = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list'; params = @{} }
        $out = Invoke-McpRequest -ServerPath $serverPath -PackageCachePath $fixturesDir -Requests @($req)
        $out.Stdout | Should -Not -BeNullOrEmpty
        $lines = $out.Stdout -split "`r?`n" | Where-Object { $_ }
        $resp = $lines[0] | ConvertFrom-Json
        $resp.id | Should -Be 1
        $resp.result.tools.Count | Should -Be 6
        $names = $resp.result.tools | ForEach-Object { $_.name }
        $names | Should -Contain 'bc_find_object'
        $names | Should -Contain 'bc_get_fields'
        $names | Should -Contain 'bc_get_procedures'
        $names | Should -Contain 'bc_get_object_source'
        $names | Should -Contain 'bc_search'
        $names | Should -Contain 'bc_list_apps'
    }

    It 'responds to a tools/call for bc_list_apps' {
        $req = @{
            jsonrpc = '2.0'; id = 2; method = 'tools/call';
            params  = @{ name = 'bc_list_apps'; arguments = @{} }
        }
        $out = Invoke-McpRequest -ServerPath $serverPath -PackageCachePath $fixturesDir -Requests @($req)
        $lines = $out.Stdout -split "`r?`n" | Where-Object { $_ }
        $resp = $lines[0] | ConvertFrom-Json
        $resp.id | Should -Be 2
        $resp.result | Should -Not -BeNullOrEmpty
    }

    It 'responds to tools/call for bc_find_object' {
        $req = @{
            jsonrpc = '2.0'; id = 3; method = 'tools/call';
            params  = @{ name = 'bc_find_object'; arguments = @{ name = 'Fixture Table' } }
        }
        $out = Invoke-McpRequest -ServerPath $serverPath -PackageCachePath $fixturesDir -Requests @($req)
        $lines = $out.Stdout -split "`r?`n" | Where-Object { $_ }
        $resp = $lines[0] | ConvertFrom-Json
        $resp.id | Should -Be 3
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/McpServer.Tests.ps1 -Output Detailed"`
Expected: all tests fail because `bc-symbol-mcp.ps1` is empty.

- [ ] **Step 3: Implement `McpServer.ps1`**

Write `skills/bc-symbol-lookup/server/lib/McpServer.ps1` with this exact content:

```powershell
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
                    # Convert PSCustomObject args to hashtable for handlers
                    $argsHash = @{}
                    if ($argsObj) {
                        $argsObj.PSObject.Properties | ForEach-Object { $argsHash[$_.Name] = $_.Value }
                    }
                    $handler = $ToolDispatch[$toolName]
                    $result = & $handler -Index $Index -Args $argsHash
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
```

- [ ] **Step 4: Test will still fail — still need the entry-point script. Move to Task 12.**

- [ ] **Step 5: Interim commit**

```bash
git add skills/bc-symbol-lookup/server/lib/McpServer.ps1 tests/bc-symbol-lookup/McpServer.Tests.ps1
git commit -m "feat(bc-symbol-lookup): add MCP server JSON-RPC loop"
```

---

### Task 12: `bc-symbol-mcp.ps1` — entry point that wires everything together

**Files:**
- Modify: `skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1`

- [ ] **Step 1: Write the entry point**

Write `skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1` with this exact content:

```powershell
#requires -Version 7.0
<#
bc-symbol-mcp.ps1 — Entry point for the bc-symbols stdio MCP server.

Invoked by Claude Code via .mcp.json:
  "bc-symbols": {
    "command": "pwsh",
    "args": ["-NoProfile", "-File", "<plugin>/skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1",
             "-PackageCachePath", "${workspaceFolder}/.alpackages"]
  }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $PackageCachePath
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/lib/AppFileReader.ps1"
. "$PSScriptRoot/lib/SymbolIndex.ps1"
. "$PSScriptRoot/lib/Tools.ps1"
. "$PSScriptRoot/lib/McpServer.ps1"

[Console]::Error.WriteLine("bc-symbols: indexing $PackageCachePath ...")
$index = New-SymbolIndex -PackageCachePath $PackageCachePath
[Console]::Error.WriteLine("bc-symbols: indexed $($index.Apps.Count) apps, $($index.Objects.Count) objects")

$dispatch = @{
    'bc_find_object'        = { param($Index, $Args) Invoke-BcFindObjectTool        -Index $Index -Args $Args }
    'bc_get_fields'         = { param($Index, $Args) Invoke-BcGetFieldsTool         -Index $Index -Args $Args }
    'bc_get_procedures'     = { param($Index, $Args) Invoke-BcGetProceduresTool     -Index $Index -Args $Args }
    'bc_get_object_source'  = { param($Index, $Args) Invoke-BcGetObjectSourceTool   -Index $Index -Args $Args }
    'bc_search'             = { param($Index, $Args) Invoke-BcSearchTool            -Index $Index -Args $Args }
    'bc_list_apps'          = { param($Index, $Args) Invoke-BcListAppsTool          -Index $Index -Args $Args }
}

$schemas = @(
    @{
        name        = 'bc_find_object'
        description = 'Find a Business Central object (Table, Page, Codeunit, etc.) by name. Supports wildcards.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                name = @{ type = 'string'; description = "Object name (exact or wildcard like 'Sales*')" }
                type = @{ type = 'string'; description = "Optional: Table, Page, Codeunit, Enum, Interface, Report, Query, XmlPort, TableExtension, PageExtension" }
            }
            required   = @('name')
        }
    },
    @{
        name        = 'bc_get_fields'
        description = 'Get the fields of a Table or TableExtension, with optional substring filter.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                objectName = @{ type = 'string' }
                objectId   = @{ type = 'integer' }
                type       = @{ type = 'string'; enum = @('Table', 'TableExtension') }
                filter     = @{ type = 'string'; description = 'Optional substring filter on field name' }
            }
            required   = @('type')
        }
    },
    @{
        name        = 'bc_get_procedures'
        description = 'Get the procedures of a Codeunit, Page, or other procedure-bearing object.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                objectName = @{ type = 'string' }
                objectId   = @{ type = 'integer' }
                type       = @{ type = 'string' }
                filter     = @{ type = 'string'; description = 'Optional substring filter on procedure name' }
            }
            required   = @('type')
        }
    },
    @{
        name        = 'bc_get_object_source'
        description = 'Get the AL source of an object, if present in the .app package. v1: returns null with a reason.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                objectName = @{ type = 'string' }
                objectId   = @{ type = 'integer' }
                type       = @{ type = 'string' }
            }
            required   = @('type')
        }
    },
    @{
        name        = 'bc_search'
        description = 'Free-text search across object names, ranked by match quality.'
        inputSchema = @{
            type       = 'object'
            properties = @{
                query = @{ type = 'string' }
                limit = @{ type = 'integer'; description = 'Max results, default 25' }
            }
            required   = @('query')
        }
    },
    @{
        name        = 'bc_list_apps'
        description = 'List all indexed .app files in the current package cache.'
        inputSchema = @{
            type       = 'object'
            properties = @{}
        }
    }
)

Start-McpServer -Index $index -ToolDispatch $dispatch -ToolSchemas $schemas
```

- [ ] **Step 2: Run the McpServer tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup/McpServer.Tests.ps1 -Output Detailed"`
Expected: 3 tests pass (tools/list returns 6 tools, bc_list_apps returns a result, bc_find_object returns a result).

- [ ] **Step 3: Run all tests to verify full regression green**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup -Output Detailed"`
Expected: all tests pass (AppFileReader: 4, SymbolIndex: 6, Tools: 16, McpServer: 3 = 29 total).

- [ ] **Step 4: Commit**

```bash
git add skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1
git commit -m "feat(bc-symbol-lookup): wire up MCP server entry point"
```

---

### Task 13: Smoke test against a real BC `.app` file

**Files:**
- None (read-only smoke test)

**Purpose.** Verify the parser works against a real v28 Ready2Run-wrapped `.app` from the local `bcartifacts.cache`, not just our hand-crafted fixtures. This is the moment we find out whether the SymbolReference.json walk handles real-world shape edge cases.

- [ ] **Step 1: Pick a real `.app` file**

Run:
```
pwsh -NoProfile -Command "Get-ChildItem 'C:\bcartifacts.cache\sandbox\27.4.45366.47091\w1\Extensions\*.app' -File | Sort-Object Length | Select-Object -First 1 FullName, Length"
```
Expected: a single file path, e.g. `Microsoft_System Application_*.app`.

- [ ] **Step 2: Create a temporary package cache folder with that one file**

Run:
```
pwsh -NoProfile -Command @'
$src = Get-ChildItem 'C:\bcartifacts.cache\sandbox\27.4.45366.47091\w1\Extensions\*.app' -File | Sort-Object Length | Select-Object -First 1
$dst = Join-Path $env:TEMP 'bc-symbol-smoke'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item $src.FullName $dst
Write-Host "Copied $($src.Name) to $dst"
'@
```

- [ ] **Step 3: Start the MCP server and send `bc_list_apps`**

Run:
```
pwsh -NoProfile -Command @'
$req = @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = 'bc_list_apps'; arguments = @{} } } | ConvertTo-Json -Compress
$out = $req | pwsh -NoProfile -File skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1 -PackageCachePath (Join-Path $env:TEMP 'bc-symbol-smoke')
Write-Host $out
'@
```

Expected: a JSON-RPC response containing `result.content[0].text` whose parsed value has at least one app with `name` equal to the real app's display name (e.g., "System Application").

- [ ] **Step 4: Send `bc_find_object` for a known BC standard object**

Run:
```
pwsh -NoProfile -Command @'
$req = @{ jsonrpc = '2.0'; id = 1; method = 'tools/call'; params = @{ name = 'bc_find_object'; arguments = @{ name = 'Customer' } } } | ConvertTo-Json -Compress
$out = $req | pwsh -NoProfile -File skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1 -PackageCachePath (Join-Path $env:TEMP 'bc-symbol-smoke')
Write-Host $out
'@
```

Expected: a response. System Application may or may not contain a Customer object — if the smoke test uses a different `.app` that does contain Customer (e.g., Base Application), this should return results. If System Application, the response may be empty `objects: []`, which is also a valid pass — it just confirms the server runs without crashing.

- [ ] **Step 5: If any unexpected error, diagnose and patch**

If Step 3 or 4 throws, the real-world SymbolReference.json has a shape we didn't account for. Add a new test case to `SymbolIndex.Tests.ps1` using the problem object's JSON shape as a fixture, fix `_WalkNamespaces`, and repeat.

- [ ] **Step 6: Clean up temp folder**

Run:
```
pwsh -NoProfile -Command "Remove-Item (Join-Path $env:TEMP 'bc-symbol-smoke') -Recurse -Force"
```

- [ ] **Step 7: No commit needed** (read-only)

---

### Task 14: Write `SKILL.md`

**Files:**
- Modify: `skills/bc-symbol-lookup/SKILL.md`

- [ ] **Step 1: Write the skill manifest**

Write `skills/bc-symbol-lookup/SKILL.md` with this exact content:

```markdown
---
name: bc-symbol-lookup
description: Offline Business Central symbol lookup via a local MCP server. Provides bc_find_object, bc_get_fields, bc_get_procedures, bc_search, and bc_list_apps tools that parse .app files in the project's .alpackages/ folder. Use this instead of guessing object IDs, field names, or procedure signatures.
---

# bc-symbol-lookup

This skill is a **local stdio MCP server** that parses Business Central `.app` files offline and answers object/field/procedure queries. Register it in your project's `.mcp.json` — `bc-bootstrap` does this automatically.

## When to use

Whenever you need to know something about a BC object — your own, a BC standard object, or a third-party extension — before referencing it in AL code. Examples:

- "What fields does the Customer table have?" → `bc_get_fields`
- "What's the signature of `Sales-Post.Run`?" → `bc_get_procedures`
- "Is there an object called Vendor Card?" → `bc_find_object`
- "Find everything with 'Item' in the name" → `bc_search`
- "Which apps are currently indexed?" → `bc_list_apps`

## Hard rule

**Never guess an object ID, field name, or procedure signature. Look it up first.**

If a field, procedure, or object you need isn't in the index, the project's `.alpackages/` is missing that app's symbols. Call `al_downloadsymbols` via the `almcp` MCP server with `globalSourcesOnly=true` to pull them, then re-run your lookup.

## How it works

The server strips the 40-byte header from each `.app` file, detects v28 Ready2Run wrappers and strips the inner header as well, extracts `SymbolReference.json`, and walks the recursive `Namespaces` tree to build a flat in-memory index. Re-indexing runs on demand when `.alpackages/` changes.

The server is pure read-only — it never touches the network, never calls a BC server, never runs the AL compiler.

## Registered via

```json
"bc-symbols": {
  "command": "pwsh",
  "args": ["-NoProfile", "-File", "<plugin>/skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1",
           "-PackageCachePath", "${workspaceFolder}/.alpackages"]
}
```
```

- [ ] **Step 2: Commit**

```bash
git add skills/bc-symbol-lookup/SKILL.md
git commit -m "docs(bc-symbol-lookup): add SKILL.md"
```

---

### Task 15: Full-suite verification

- [ ] **Step 1: Run all Pester tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/bc-symbol-lookup -Output Detailed"`
Expected: 29 tests pass, 0 fail.

- [ ] **Step 2: Verify skill layout on disk**

Run: `pwsh -NoProfile -Command "Get-ChildItem -Recurse -File skills/bc-symbol-lookup | ForEach-Object { $_.FullName.Replace((Get-Location).Path + '\', '') }"`

Expected (order may vary):
```
skills\bc-symbol-lookup\SKILL.md
skills\bc-symbol-lookup\server\bc-symbol-mcp.ps1
skills\bc-symbol-lookup\server\lib\AppFileReader.ps1
skills\bc-symbol-lookup\server\lib\McpServer.ps1
skills\bc-symbol-lookup\server\lib\SymbolIndex.ps1
skills\bc-symbol-lookup\server\lib\Tools.ps1
```

- [ ] **Step 3: No commit needed** (verification only)
