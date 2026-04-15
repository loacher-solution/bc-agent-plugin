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
