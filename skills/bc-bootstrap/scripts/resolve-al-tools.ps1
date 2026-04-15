#requires -Version 5.1
<#
resolve-al-tools.ps1 — Resolve the AL toolchain (altool.exe, alc.exe, almcp) across
five fallback sources. Writes a JSON object to stdout:

  { "status": "ok"|"not-found"|"needs-download"|"error",
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
    [pscustomobject]@{
        status    = $Status
        source    = $Source
        toolsPath = $ToolsPath
        message   = $Message
    } | ConvertTo-Json -Compress
}

function Test-ToolchainPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path $Path)) { return $false }
    return (Test-Path (Join-Path $Path 'altool.exe')) -and (Test-Path (Join-Path $Path 'alc.exe'))
}

# Step 1: env var
if ($EnvToolsPath -and (Test-ToolchainPath $EnvToolsPath)) {
    $abs = (Resolve-Path $EnvToolsPath).Path
    Write-ResolverResult -Status 'ok' -Source 'env' -ToolsPath $abs -Message "Resolved from BC_AGENT_AL_TOOLS_PATH"
    exit 0
}

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
        $extractTo = $PluginCacheRoot
        New-Item -ItemType Directory -Force -Path $extractTo | Out-Null
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
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
        } catch {
            Write-Warning "bc-gt vsix extraction failed: $($_.Exception.Message)"
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

Write-ResolverResult -Status 'not-found' -Source '' -ToolsPath '' -Message "AL toolchain not found in any source. Set BC_AGENT_AL_TOOLS_PATH, install VS Code AL extension, or re-run with -AllowDownload to pull from marketplace."
exit 1
