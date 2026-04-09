BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $manifest = Join-Path $script:RepoRoot 'Modules\LogHelper\LogHelper.psd1'
    Import-Module -Name $manifest -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name LogHelper -Force -ErrorAction SilentlyContinue
}

Describe 'LogHelper' {
    It 'imports via manifest path' {
        Get-Module -Name LogHelper | Should -Not -BeNullOrEmpty
    }
}

Describe 'Write-Log' {
    BeforeEach {
        $script:LogPath = Join-Path $TestDrive 'pester.log'
        Set-LogFile -Path $script:LogPath
        Set-LoggingPreference -Preference standard
    }

    It 'writes information-level text to the log file' {
        $msg = 'SQLPowerDoc Pester smoke'
        Write-Log -Message $msg -MessageLevel information
        $script:LogPath | Should -Exist
        (Get-Content -LiteralPath $script:LogPath -Raw) | Should -Match $msg
    }
}
