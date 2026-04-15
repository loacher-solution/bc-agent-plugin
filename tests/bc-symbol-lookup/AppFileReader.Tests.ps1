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
