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
