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
        $result = Invoke-BcListAppsTool -Index $index -ToolArgs @{}
        $result.apps | Should -Not -BeNullOrEmpty
        $result.apps[0].name | Should -Be 'Fixture Minimal App'
        $result.apps[0].publisher | Should -Be 'Fixture Publisher'
        $result.apps[0].version | Should -Be '1.0.0.0'
    }
}

Describe 'Invoke-BcFindObjectTool' {
    It 'finds Fixture Table by exact name' {
        $result = Invoke-BcFindObjectTool -Index $index -ToolArgs @{ name = 'Fixture Table' }
        $result.objects.Count | Should -BeGreaterOrEqual 1
        $result.objects[0].type | Should -Be 'Table'
        $result.objects[0].id | Should -Be 50100
    }

    It 'filters by type' {
        $result = Invoke-BcFindObjectTool -Index $index -ToolArgs @{ name = 'Fixture*'; type = 'Codeunit' }
        $result.objects | ForEach-Object { $_.type | Should -Be 'Codeunit' }
    }

    It 'supports wildcard matching' {
        $result = Invoke-BcFindObjectTool -Index $index -ToolArgs @{ name = 'Fix*' }
        $result.objects.Count | Should -BeGreaterOrEqual 3
    }

    It 'returns empty array on no match' {
        $result = Invoke-BcFindObjectTool -Index $index -ToolArgs @{ name = 'NoSuchObject' }
        $result.objects.Count | Should -Be 0
    }
}

Describe 'Invoke-BcGetFieldsTool' {
    It 'returns fields of Fixture Table' {
        $result = Invoke-BcGetFieldsTool -Index $index -ToolArgs @{ objectName = 'Fixture Table'; type = 'Table' }
        $result.fields.Count | Should -Be 2
        $result.fields[0].id | Should -Be 1
        $result.fields[0].name | Should -Be 'No.'
        $result.fields[0].typeName | Should -Be 'Code'
        $result.fields[0].typeLength | Should -Be 20
    }

    It 'filters fields by substring' {
        $result = Invoke-BcGetFieldsTool -Index $index -ToolArgs @{ objectName = 'Fixture Table'; type = 'Table'; filter = 'Desc' }
        $result.fields.Count | Should -Be 1
        $result.fields[0].name | Should -Be 'Description'
    }

    It 'returns error when object not found' {
        $result = Invoke-BcGetFieldsTool -Index $index -ToolArgs @{ objectName = 'Nope'; type = 'Table' }
        $result.error | Should -Not -BeNullOrEmpty
    }

    It 'returns error when object has no fields (wrong type)' {
        $result = Invoke-BcGetFieldsTool -Index $index -ToolArgs @{ objectName = 'Fixture Helper'; type = 'Codeunit' }
        $result.error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-BcGetProceduresTool' {
    It 'returns procedures of Fixture Helper codeunit' {
        $result = Invoke-BcGetProceduresTool -Index $index -ToolArgs @{ objectName = 'Fixture Helper'; type = 'Codeunit' }
        $result.procedures.Count | Should -Be 1
        $result.procedures[0].name | Should -Be 'DoStuff'
        $result.procedures[0].scope | Should -Be 'Public'
        $result.procedures[0].parameters.Count | Should -Be 1
        $result.procedures[0].parameters[0].name | Should -Be 'Input'
        $result.procedures[0].parameters[0].typeName | Should -Be 'Integer'
        $result.procedures[0].returnType | Should -Be 'Boolean'
    }

    It 'returns error when codeunit not found' {
        $result = Invoke-BcGetProceduresTool -Index $index -ToolArgs @{ objectName = 'NoSuch'; type = 'Codeunit' }
        $result.error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-BcSearchTool' {
    It 'finds objects by free-text query' {
        $result = Invoke-BcSearchTool -Index $index -ToolArgs @{ query = 'fixture' }
        $result.results.Count | Should -BeGreaterOrEqual 3
    }

    It 'respects the limit parameter' {
        $result = Invoke-BcSearchTool -Index $index -ToolArgs @{ query = 'fixture'; limit = 1 }
        $result.results.Count | Should -Be 1
    }

    It 'returns empty results with no match' {
        $result = Invoke-BcSearchTool -Index $index -ToolArgs @{ query = 'zzzzzzz' }
        $result.results.Count | Should -Be 0
    }
}

Describe 'Invoke-BcGetObjectSourceTool' {
    It 'returns null source with a reason in v1' {
        $result = Invoke-BcGetObjectSourceTool -Index $index -ToolArgs @{ objectName = 'Fixture Table'; type = 'Table' }
        $result.source | Should -BeNullOrEmpty
        $result.reason | Should -Match 'not implemented'
    }

    It 'returns error when object not found' {
        $result = Invoke-BcGetObjectSourceTool -Index $index -ToolArgs @{ objectName = 'NoSuch'; type = 'Table' }
        $result.error | Should -Not -BeNullOrEmpty
    }
}
