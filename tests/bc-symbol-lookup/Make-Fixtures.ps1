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
