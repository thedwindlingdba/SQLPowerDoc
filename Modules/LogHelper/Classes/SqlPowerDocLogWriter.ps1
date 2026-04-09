using namespace System
using namespace System.Globalization
using namespace System.IO
using namespace System.Security.Cryptography
using namespace System.Text
using namespace System.Threading

class SqlPowerDocLogWriter : IDisposable {
    [string] $LogPath
    [string] $Source
    hidden [Mutex] $FileMutex
    hidden [bool] $DirectoryReady = $false
    hidden [bool] $Disposed = $false
    hidden static [UTF8Encoding] $Utf8NoBom = [UTF8Encoding]::new($false)

    SqlPowerDocLogWriter([string] $logPath, [string] $source) {
        if ([string]::IsNullOrWhiteSpace($logPath)) {
            throw [ArgumentException]::new('LogPath must be non-empty.')
        }

        $this.LogPath = [Path]::GetFullPath($logPath)
        $this.Source = if ([string]::IsNullOrWhiteSpace($source)) { 'SqlPowerDoc' } else { $source.Trim() }
        $this.EnsureLogDirectory()
        $this.FileMutex = [Mutex]::new($false, $this.GetMutexName($this.LogPath))
    }

    hidden [string] GetMutexName([string] $path) {
        $normalizedPath = $path.Trim().ToLowerInvariant()
        $bytes = [Encoding]::UTF8.GetBytes($normalizedPath)
        $sha = [SHA256]::Create()
        $hash = $null
        try {
            $hash = $sha.ComputeHash($bytes)
        }
        finally {
            $sha.Dispose()
        }

        $hex = [BitConverter]::ToString($hash).Replace('-', '')
        return "Local\SqlPowerDocLogWriter_$hex"
    }

    hidden [void] EnsureLogDirectory() {
        if ($this.DirectoryReady) {
            return
        }

        $dir = [Path]::GetDirectoryName($this.LogPath)
        if (-not [string]::IsNullOrEmpty($dir) -and -not [Directory]::Exists($dir)) {
            [void][Directory]::CreateDirectory($dir)
        }
        $this.DirectoryReady = $true
    }

    hidden [void] ThrowIfDisposed() {
        if ($this.Disposed) {
            throw [ObjectDisposedException]::new('SqlPowerDocLogWriter')
        }
    }

    hidden [string] NormalizeMessage([string] $message) {
        if ($null -eq $message) {
            return ''
        }

        $oneLine = $message -replace '[\r\n]+', ' '
        return $oneLine.TrimEnd()
    }

    hidden [string] EscapeJsonString([string] $value) {
        if ($null -eq $value) {
            return ''
        }

        $sb = [StringBuilder]::new()
        for ($i = 0; $i -lt $value.Length; $i++) {
            $ch = $value[$i]
            $code = [int][char]$ch
            switch ($code) {
                34 { [void]$sb.Append('\"') }
                92 { [void]$sb.Append('\\') }
                8 { [void]$sb.Append('\b') }
                9 { [void]$sb.Append('\t') }
                10 { [void]$sb.Append('\n') }
                12 { [void]$sb.Append('\f') }
                13 { [void]$sb.Append('\r') }
                default {
                    if ($code -lt 32) {
                        [void]$sb.Append('\u')
                        [void]$sb.Append($code.ToString('x4', [CultureInfo]::InvariantCulture))
                    }
                    else {
                        [void]$sb.Append($ch)
                    }
                }
            }
        }

        return $sb.ToString()
    }

    hidden [string] BuildJson([string] $severity, [string] $logLevel, [string] $message) {
        $ts = [DateTime]::UtcNow.ToString('o', [CultureInfo]::InvariantCulture)
        $escapedSource = $this.EscapeJsonString($this.Source)
        $escapedMessage = $this.EscapeJsonString($this.NormalizeMessage($message))
        $threadId = [Environment]::CurrentManagedThreadId

        return ('{{"DateTime":"{0}","Severity":"{1}","LogLevel":"{2}","Source":"{3}","ThreadId":{4},"Message":"{5}","Data":null}}' -f $ts, $severity, $logLevel, $escapedSource, $threadId, $escapedMessage)
    }

    hidden [void] AppendFileUtf8NoBom([string] $jsonLine) {
        $this.ThrowIfDisposed()
        $this.EnsureLogDirectory()

        $mutex = $this.FileMutex
        if ($null -eq $mutex) {
            throw [ObjectDisposedException]::new('SqlPowerDocLogWriter')
        }

        [void]$mutex.WaitOne()
        try {
            $bytes = [SqlPowerDocLogWriter]::Utf8NoBom.GetBytes($jsonLine + [Environment]::NewLine)
            $stream = [FileStream]::new($this.LogPath, [FileMode]::Append, [FileAccess]::Write, [FileShare]::ReadWrite)
            try {
                $stream.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $stream.Dispose()
            }
        }
        finally {
            $mutex.ReleaseMutex()
        }
    }

    hidden [void] Emit([string] $severity, [string] $logLevel, [string] $message) {
        $this.ThrowIfDisposed()
        $jsonLine = $this.BuildJson($severity, $logLevel, $message)
        $this.AppendFileUtf8NoBom($jsonLine)

        switch ($severity) {
            'Warning' {
                Microsoft.PowerShell.Utility\Write-Warning -Message $jsonLine
            }
            'Error' {
                Microsoft.PowerShell.Utility\Write-Error -Message $jsonLine -ErrorAction Continue
            }
            default {
                if ($logLevel -eq 'Debug') {
                    Microsoft.PowerShell.Utility\Write-Verbose -Message $jsonLine
                }
                else {
                    Microsoft.PowerShell.Utility\Write-Information -MessageData $jsonLine -InformationAction Continue
                }
            }
        }
    }

    [void] Flush() {
        $this.ThrowIfDisposed()
        $mutex = $this.FileMutex
        if ($null -eq $mutex) {
            throw [ObjectDisposedException]::new('SqlPowerDocLogWriter')
        }

        [void]$mutex.WaitOne()
        try {
            # No-op barrier: waiting on the mutex ensures prior append critical sections completed.
        }
        finally {
            $mutex.ReleaseMutex()
        }
    }

    [void] Stop() {
        if ($this.Disposed) {
            return
        }

        $mutex = $this.FileMutex
        if ($null -eq $mutex) {
            $this.Disposed = $true
            return
        }

        [void]$mutex.WaitOne()
        try {
            $this.Disposed = $true
        }
        finally {
            $mutex.ReleaseMutex()
        }

        $mutex.Dispose()
        $this.FileMutex = $null
    }

    [void] Dispose() {
        $this.Stop()
    }

    [void] Info([string] $message) {
        $this.Emit('Normal', 'Info', $message)
    }

    [void] Warn([string] $message) {
        $this.Emit('Warning', 'Info', $message)
    }

    [void] Error([string] $message) {
        $this.Emit('Error', 'Info', $message)
    }

    [void] Debug([string] $message) {
        $this.Emit('Normal', 'Debug', $message)
    }
}
