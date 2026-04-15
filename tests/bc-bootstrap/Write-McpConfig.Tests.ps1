#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-bootstrap/scripts/write-mcp-config.ps1"

    function Invoke-Writer {
        param([string]$ProjectRoot, [string]$AlToolsPath, [string]$PluginRoot)
        & pwsh -NoProfile -File $script:scriptPath -ProjectRoot $ProjectRoot -AlToolsPath $AlToolsPath -PluginRoot $PluginRoot
    }
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
