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

        # Inner .app location varies across BC versions:
        #   v28 plan docs: publishedartifacts/<guid>_<ver>_<maj>_<build>.app
        #   v27 real-world: <guid>_<ver>_<maj>_<build>.app at zip root (no publishedartifacts/ prefix)
        # Also minimal-r2r.app test fixture uses publishedartifacts/ path.
        # Match any .app entry, prefer the largest (the real inner app, not a Merkle tracker).
        $innerEntry = $zip.Entries |
            Where-Object { $_.FullName.ToLowerInvariant().EndsWith('.app') } |
            Sort-Object -Property Length -Descending |
            Select-Object -First 1
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
