BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:RepoRoot 'Modules\LogHelper\LogHelper.psd1') -Force
    $script:ExpectedKeys = @('DateTime', 'Severity', 'LogLevel', 'Source', 'ThreadId', 'Message', 'Data')
}

AfterAll {
    Remove-Module -Name LogHelper -Force -ErrorAction SilentlyContinue
}

Describe 'SqlPowerDocLogWriter' {
    BeforeEach {
        $script:LogPath = Join-Path $TestDrive ('structured-{0}.log' -f [guid]::NewGuid().ToString('n'))
    }

    It 'throws when log path is empty' {
        { New-SqlPowerDocLogWriter -LogPath '' } | Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
    }

    It 'throws when log path is whitespace' {
        { New-SqlPowerDocLogWriter -LogPath '   ' } | Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'writes PoshBot-style JSON line for Info' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'UnitTest'
        try {
            $infoStream = & { $w.Info('hello') } 6>&1
            $w.Flush()
            $infoStream | Should -Not -BeNullOrEmpty
            "$infoStream" | Should -Match '"Severity":"Normal"'
            "$infoStream" | Should -Match '"LogLevel":"Info"'
            $script:LogPath | Should -Exist
            $line = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n")
            $line | Should -Match '"DateTime":"[^"]*Z"'
            $json = $line | ConvertFrom-Json
            foreach ($k in $script:ExpectedKeys) { $json.PSObject.Properties.Name | Should -Contain $k }
            $json.Severity | Should -Be 'Normal'
            $json.LogLevel | Should -Be 'Info'
            $json.Source | Should -Be 'UnitTest'
            $json.Message | Should -Be 'hello'
        }
        finally {
            $w.Stop()
        }
    }

    It 'defaults source and normalizes multiline messages' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source '  '
        try {
            $w.Info("line1`r`nline2")
            $w.Flush()
            $json = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n") | ConvertFrom-Json
            $json.Source | Should -Be 'SqlPowerDoc'
            $json.Message | Should -Be 'line1 line2'
        }
        finally {
            $w.Stop()
        }
    }

    It 'escapes JSON special characters and preserves message payload' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'Esc'
        try {
            $msg = ('quote " and slash \ and tab {0}end' -f "`t")
            $w.Info($msg)
            $w.Flush()
            $line = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n")
            { $line | ConvertFrom-Json } | Should -Not -Throw
            $json = $line | ConvertFrom-Json
            $json.Message | Should -Be $msg
        }
        finally {
            $w.Stop()
        }
    }

    It 'encodes non-tab control characters as escaped unicode in JSON' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'Ctrl'
        try {
            $msg = "pre$([char]1)mid$([char]2)post"
            $w.Info($msg)
            $w.Flush()
            $line = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n")
            $line | Should -Match '\\u0001'
            $line | Should -Match '\\u0002'
            $json = $line | ConvertFrom-Json
            $json.Message | Should -Be $msg
        }
        finally {
            $w.Stop()
        }
    }

    It 'escapes special characters in Source field' {
        $source = 'src "quoted" \ slash'
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source $source
        try {
            $w.Info('source-check')
            $w.Flush()
            $line = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n")
            { $line | ConvertFrom-Json } | Should -Not -Throw
            $json = $line | ConvertFrom-Json
            $json.Source | Should -Be $source
        }
        finally {
            $w.Stop()
        }
    }

    It 'writes empty string when message is null' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'Null'
        try {
            $w.Info($null)
            $w.Flush()
            $json = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n") | ConvertFrom-Json
            $json.Message | Should -Be ''
        }
        finally {
            $w.Stop()
        }
    }

    It 'writes Warning and Error severities for Warn/Error methods' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'T'
        try {
            $warnStream = & { $w.Warn('w1') } 3>&1
            $errorStream = & { $w.Error('e1') } 2>&1
            $w.Flush()
            $warnStream | Should -Not -BeNullOrEmpty
            $errorStream | Should -Not -BeNullOrEmpty
            "$warnStream" | Should -Match '"Severity":"Warning"'
            "$errorStream" | Should -Match '"Severity":"Error"'
            $lines = Get-Content -LiteralPath $script:LogPath
            $lines.Count | Should -Be 2
            $first = $lines[0] | ConvertFrom-Json
            $second = $lines[1] | ConvertFrom-Json
            $first.Severity | Should -Be 'Warning'
            $first.LogLevel | Should -Be 'Info'
            $first.Message | Should -Be 'w1'
            $second.Severity | Should -Be 'Error'
            $second.LogLevel | Should -Be 'Info'
            $second.Message | Should -Be 'e1'
        }
        finally {
            $w.Stop()
        }
    }

    It 'writes Debug log level for Debug method' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'Dbg'
        $priorVerbose = $Global:VerbosePreference
        $Global:VerbosePreference = 'Continue'
        try {
            $verboseStream = & { $w.Debug('trace') } 4>&1
            $w.Flush()
            $verboseStream | Should -Not -BeNullOrEmpty
            "$verboseStream" | Should -Match '"LogLevel":"Debug"'
            $json = (Get-Content -LiteralPath $script:LogPath -Raw).TrimEnd("`r", "`n") | ConvertFrom-Json
            $json.Severity | Should -Be 'Normal'
            $json.LogLevel | Should -Be 'Debug'
            $json.Message | Should -Be 'trace'
        }
        finally {
            $w.Stop()
            $Global:VerbosePreference = $priorVerbose
        }
    }

    It 'throws after Stop is called' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'UnitTest'
        $w.Stop()
        { $w.Info('after-stop') } | Should -Throw -ExceptionType ([System.ObjectDisposedException])
        { $w.Flush() } | Should -Throw -ExceptionType ([System.ObjectDisposedException])
    }

    It 'allows Stop to be called repeatedly without failure' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'UnitTest'
        $w.Stop()
        { $w.Stop() } | Should -Not -Throw
    }

    It 'treats Dispose as Stop and blocks subsequent writes' {
        $w = New-SqlPowerDocLogWriter -LogPath $script:LogPath -Source 'UnitTest'
        $w.Dispose()
        { $w.Info('after-dispose') } | Should -Throw -ExceptionType ([System.ObjectDisposedException])
    }

    It 'supports concurrent writes without line loss' {
        if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Start-ThreadJob is required for multithreaded write test.'
            return
        }

        $manifest = Join-Path $script:RepoRoot 'Modules\LogHelper\LogHelper.psd1'
        $jobs = @()
        try {
            for ($i = 1; $i -le 40; $i++) {
                $jobs += Start-ThreadJob -ArgumentList $manifest, $script:LogPath, $i -ScriptBlock {
                    param($mPath, $logPath, $num)
                    Import-Module $mPath -Force
                    $writer = New-SqlPowerDocLogWriter -LogPath $logPath -Source 'MT'
                    try {
                        $writer.Info("msg-$num")
                        $writer.Flush()
                    }
                    finally {
                        $writer.Stop()
                    }
                }
            }
            Wait-Job -Job $jobs | Out-Null
            $null = Receive-Job -Job $jobs -ErrorAction Stop
        }
        finally {
            if ($jobs.Count -gt 0) {
                Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
            }
        }

        $lines = Get-Content -LiteralPath $script:LogPath
        $lines.Count | Should -Be 40

        $parsed = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $lines) {
            $parsed.Add(($line | ConvertFrom-Json))
        }
        $parsed.Count | Should -Be 40

        foreach ($item in $parsed) {
            foreach ($k in $script:ExpectedKeys) {
                $item.PSObject.Properties.Name | Should -Contain $k
            }
            $item.Source | Should -Be 'MT'
            $item.Severity | Should -Be 'Normal'
            $item.LogLevel | Should -Be 'Info'
        }

        $messages = @($parsed | ForEach-Object { $_.Message })
        ($messages | Sort-Object -Unique).Count | Should -Be 40
        for ($i = 1; $i -le 40; $i++) {
            $messages | Should -Contain "msg-$i"
        }
    }
}
