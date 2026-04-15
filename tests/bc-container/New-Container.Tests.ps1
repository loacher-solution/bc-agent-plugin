#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = "$PSScriptRoot/../../skills/bc-container/scripts/new-container.ps1"
}

Describe 'new-container.ps1 (DryRun)' {
    BeforeEach {
        $script:tmpProject = Join-Path $env:TEMP "bc-container-test-$([Guid]::NewGuid().ToString('N'))"
        $script:tmpCredStore = Join-Path $env:TEMP "bc-container-creds-$([Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Force -Path $script:tmpProject | Out-Null
        New-Item -ItemType Directory -Force -Path $script:tmpCredStore | Out-Null
    }
    AfterEach {
        Remove-Item $script:tmpProject -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $script:tmpCredStore -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes .bc-agent/container.json metadata in dry run' {
        & pwsh -NoProfile -File $script:scriptPath `
            -ProjectRoot $script:tmpProject `
            -ContainerName 'testcontainer' `
            -Platform '28.0.0.0' `
            -Application '28.0.0.0' `
            -Country 'w1' `
            -CredentialStoreRoot $script:tmpCredStore `
            -DryRun

        $metaPath = Join-Path $script:tmpProject '.bc-agent/container.json'
        Test-Path $metaPath | Should -BeTrue
        $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
        $meta.name | Should -Be 'testcontainer'
        $meta.platform | Should -Be '28.0.0.0'
        $meta.application | Should -Be '28.0.0.0'
        $meta.credentialsFile | Should -Match 'testcontainer\.json$'
        $meta.dryRun | Should -Be $true
    }

    It 'writes a credential file into the credential store in dry run' {
        & pwsh -NoProfile -File $script:scriptPath `
            -ProjectRoot $script:tmpProject `
            -ContainerName 'testcontainer' `
            -Platform '28.0.0.0' `
            -Application '28.0.0.0' `
            -Country 'w1' `
            -CredentialStoreRoot $script:tmpCredStore `
            -DryRun

        $credPath = Join-Path $script:tmpCredStore 'testcontainer.json'
        Test-Path $credPath | Should -BeTrue
        $cred = Get-Content $credPath -Raw | ConvertFrom-Json
        $cred.username | Should -Not -BeNullOrEmpty
        $cred.password | Should -Not -BeNullOrEmpty
    }
}
