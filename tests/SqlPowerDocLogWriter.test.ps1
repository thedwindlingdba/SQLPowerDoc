BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'Modules\LogHelper\LogHelper.psd1') -Force
    $script:LogLinePattern = '^(?<ts>\d{4}-\d{2}-\d{2}T[\d:\.]+Z) (?<sev>INFO|WARN|ERROR|DEBUG) \[(?<src>[^\]]+)\] (?<msg>.*)$'
}

AfterAll {
    Remove-Module -Name LogHelper -Force -ErrorAction SilentlyContinue
}

Describe 'SqlPowerDocLogWriter' {
    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('structured-{0}.log' -f [guid]::NewGuid().ToString('n'))
    }

    It 'writes INFO line with canonical format to file' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'UnitTest'
        $w.Info('hello')
        $script:LogPath | Should -Exist
        $line = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n")
        $line | Should -Match $script:LogLinePattern
        $m = [regex]::Match($line, $script:LogLinePattern)
        $m.Groups['sev'].Value | Should -Be 'INFO'
        $m.Groups['src'].Value | Should -Be 'UnitTest'
        $m.Groups['msg'].Value | Should -Be 'hello'
    }

    It 'writes WARN and ERROR tokens for respective levels' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'T'
        $w.Warn('w1')
        $w.Error('e1')
        $lines = Get-Content -LiteralPath $script:LogPath
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match ' WARN \[T\] w1'
        $lines[1] | Should -Match ' ERROR \[T\] e1'
    }

    It 'writes DEBUG token to file (host mirror uses Write-Verbose)' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'Dbg'
        $w.Debug('trace')
        $line = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n")
        $line | Should -Match ' DEBUG \[Dbg\] trace'
    }
}
