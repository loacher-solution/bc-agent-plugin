#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-bootstrap/scripts/resolve-al-tools.ps1"
    $script:fixturesDir = "$PSScriptRoot/fixtures"

    function Invoke-Resolver {
        param(
            [string] $EnvToolsPath = '',
            [string] $VSCodeExtensionsRoot = '',
            [string] $PluginCacheRoot = '',
            [string] $BcContainerHelperRoot = '',
            [switch] $AllowDownload
        )
        $params = @(
            '-NoProfile', '-File', $script:scriptPath,
            '-EnvToolsPath', $EnvToolsPath,
            '-VSCodeExtensionsRoot', $VSCodeExtensionsRoot,
            '-PluginCacheRoot', $PluginCacheRoot,
            '-BcContainerHelperRoot', $BcContainerHelperRoot
        )
        if ($AllowDownload) { $params += '-AllowDownload' }
        $raw = & pwsh @params
        return ($raw -join "`n") | ConvertFrom-Json
    }
}

Describe 'resolve-al-tools.ps1 step 1 — env var' {
    It 'returns env var path when set and valid' {
        $fake = "$fixturesDir/fake-vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/win32"
        $result = Invoke-Resolver -EnvToolsPath $fake
        $result.status | Should -Be 'ok'
        $result.source | Should -Be 'env'
        $result.toolsPath | Should -Be (Resolve-Path $fake).Path
    }

    It 'skips env var when the path does not exist' {
        $result = Invoke-Resolver -EnvToolsPath 'C:/nonexistent/path' -VSCodeExtensionsRoot 'C:/nope'
        $result.source | Should -Not -Be 'env'
    }
}

Describe 'resolve-al-tools.ps1 step 2 — VS Code extensions' {
    It 'picks the latest version from VS Code extensions' {
        $fake = "$fixturesDir/fake-vscode/extensions"
        $result = Invoke-Resolver -VSCodeExtensionsRoot $fake
        $result.status | Should -Be 'ok'
        $result.source | Should -Be 'vscode'
        $result.toolsPath | Should -Match 'ms-dynamics-smb.al-17\.0\.2273547'
    }

    It 'skips VS Code step when extensions root has no AL extension' {
        $empty = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP "resolve-empty-$([Guid]::NewGuid().ToString('N'))")
        try {
            $result = Invoke-Resolver -VSCodeExtensionsRoot $empty.FullName
            $result.source | Should -Not -Be 'vscode'
        } finally {
            Remove-Item $empty.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'resolve-al-tools.ps1 step 3 — plugin cache' {
    It 'finds tools in the plugin cache when no env var and no VS Code' {
        $cache = Join-Path $env:TEMP "bc-bootstrap-plugincache-$([Guid]::NewGuid().ToString('N'))"
        $toolsDir = Join-Path $cache 'bin/win32'
        New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
        'fake' | Set-Content -Path (Join-Path $toolsDir 'altool.exe')
        'fake' | Set-Content -Path (Join-Path $toolsDir 'alc.exe')

        try {
            $result = Invoke-Resolver -PluginCacheRoot $cache
            $result.status | Should -Be 'ok'
            $result.source | Should -Be 'pluginCache'
        } finally {
            Remove-Item $cache -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns not-found when no source has tools and AllowDownload not set' {
        $result = Invoke-Resolver -PluginCacheRoot 'C:/nope' -BcContainerHelperRoot 'C:/nope'
        $result.status | Should -Be 'not-found'
    }
}
