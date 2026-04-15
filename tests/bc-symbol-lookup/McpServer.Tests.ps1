#requires -Version 7.0
#requires -Module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:fixturesDir = "$PSScriptRoot/fixtures"
    $script:serverPath  = "$PSScriptRoot/../../skills/bc-symbol-lookup/server/bc-symbol-mcp.ps1"

    function Invoke-McpRequest {
        param(
            [string] $ServerPath,
            [string] $PackageCachePath,
            [object[]] $Requests
        )
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'pwsh'
        $psi.Arguments = "-NoProfile -File `"$ServerPath`" -PackageCachePath `"$PackageCachePath`""
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)

        # Drain stdout/stderr asynchronously to avoid deadlock when buffers fill
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        foreach ($req in $Requests) {
            $line = $req | ConvertTo-Json -Depth 20 -Compress
            $proc.StandardInput.WriteLine($line)
        }
        $proc.StandardInput.Close()

        $proc.WaitForExit(10000) | Out-Null
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        return [pscustomobject]@{
            Stdout = $stdout
            Stderr = $stderr
            ExitCode = $proc.ExitCode
        }
    }
}

Describe 'MCP server stdio protocol' {
    It 'responds to tools/list with six tools' {
        $req = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list'; params = @{} }
        $out = Invoke-McpRequest -ServerPath $serverPath -PackageCachePath $fixturesDir -Requests @($req)
        $out.Stdout | Should -Not -BeNullOrEmpty
        $jsonLine = ($out.Stdout.Trim() -split "`n") | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1
        $resp = $jsonLine | ConvertFrom-Json
        $resp.id | Should -Be 1
        $resp.result.tools.Count | Should -Be 6
        $names = $resp.result.tools | ForEach-Object { $_.name }
        $names | Should -Contain 'bc_find_object'
        $names | Should -Contain 'bc_get_fields'
        $names | Should -Contain 'bc_get_procedures'
        $names | Should -Contain 'bc_get_object_source'
        $names | Should -Contain 'bc_search'
        $names | Should -Contain 'bc_list_apps'
    }

    It 'responds to a tools/call for bc_list_apps' {
        $req = @{
            jsonrpc = '2.0'; id = 2; method = 'tools/call';
            params  = @{ name = 'bc_list_apps'; arguments = @{} }
        }
        $out = Invoke-McpRequest -ServerPath $serverPath -PackageCachePath $fixturesDir -Requests @($req)
        $jsonLine = ($out.Stdout.Trim() -split "`n") | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1
        $resp = $jsonLine | ConvertFrom-Json
        $resp.id | Should -Be 2
        $resp.result | Should -Not -BeNullOrEmpty
    }

    It 'responds to tools/call for bc_find_object' {
        $req = @{
            jsonrpc = '2.0'; id = 3; method = 'tools/call';
            params  = @{ name = 'bc_find_object'; arguments = @{ name = 'Fixture Table' } }
        }
        $out = Invoke-McpRequest -ServerPath $serverPath -PackageCachePath $fixturesDir -Requests @($req)
        $jsonLine = ($out.Stdout.Trim() -split "`n") | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1
        $resp = $jsonLine | ConvertFrom-Json
        $resp.id | Should -Be 3
    }
}
