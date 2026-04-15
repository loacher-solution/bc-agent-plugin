#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-container/scripts/read-bc-version.ps1"
    $script:fixtures = "$PSScriptRoot/fixtures"

    function Invoke-Reader {
        param([string]$AppJsonPath)
        $raw = & pwsh -NoProfile -File $script:scriptPath -AppJsonPath $AppJsonPath
        return ($raw -join "`n") | ConvertFrom-Json
    }
}

Describe 'read-bc-version.ps1' {
    It 'extracts platform and application from a valid app.json' {
        $r = Invoke-Reader -AppJsonPath "$fixtures/app-with-versions.json"
        $r.status | Should -Be 'ok'
        $r.platform | Should -Be '28.0.0.0'
        $r.application | Should -Be '28.0.0.0'
    }

    It 'returns missing-versions status when fields are absent' {
        $r = Invoke-Reader -AppJsonPath "$fixtures/app-missing-versions.json"
        $r.status | Should -Be 'missing-versions'
    }

    It 'returns not-found when app.json does not exist' {
        $r = Invoke-Reader -AppJsonPath "$fixtures/nope.json"
        $r.status | Should -Be 'not-found'
    }
}
