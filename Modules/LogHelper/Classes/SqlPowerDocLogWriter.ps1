using namespace System
using namespace System.IO
using namespace System.Text
using namespace System.Threading

class SqlPowerDocLogWriter {
    [string] $LogPath
    [string] $Source
    hidden [object] $SyncRoot = [object]::new()

    SqlPowerDocLogWriter([string] $logPath, [string] $source) {
        if ([string]::IsNullOrWhiteSpace($logPath)) {
            throw [ArgumentException]::new('LogPath must be non-empty.')
        }
        $this.LogPath = $logPath
        $this.Source = if ([string]::IsNullOrWhiteSpace($source)) { 'SqlPowerDoc' } else { $source.Trim() }
    }

    hidden [void] EnsureLogDirectory() {
        $dir = [Path]::GetDirectoryName($this.LogPath)
        if (-not [string]::IsNullOrEmpty($dir) -and -not [Directory]::Exists($dir)) {
            [void][Directory]::CreateDirectory($dir)
        }
    }

    hidden [string] NormalizeMessage([string] $message) {
        if ($null -eq $message) { return '' }
        $oneLine = $message -replace '[\r\n]+', ' '
        return $oneLine.TrimEnd()
    }

    hidden [string] BuildLine([string] $severity, [string] $message) {
        $ts = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        $msg = $this.NormalizeMessage($message)
        return ('{0} {1} [{2}] {3}' -f $ts, $severity, $this.Source, $msg)
    }

    hidden [void] AppendFileUtf8NoBom([string] $line) {
        $this.EnsureLogDirectory()
        $enc = [UTF8Encoding]::new($false)
        $bytes = $enc.GetBytes($line + [Environment]::NewLine)
        [Monitor]::Enter($this.SyncRoot)
        try {
            $fs = [FileStream]::new($this.LogPath, [FileMode]::Append, [FileAccess]::Write, [FileShare]::Read)
            try {
                $fs.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $fs.Dispose()
            }
        }
        finally {
            [Monitor]::Exit($this.SyncRoot)
        }
    }

    hidden [void] Emit([string] $severity, [string] $message) {
        $line = $this.BuildLine($severity, $message)
        $this.AppendFileUtf8NoBom($line)
        switch ($severity) {
            'INFO' { Microsoft.PowerShell.Utility\Write-Information -MessageData $line -InformationAction Continue }
            'WARN' { Microsoft.PowerShell.Utility\Write-Warning -Message $line }
            'ERROR' { Microsoft.PowerShell.Utility\Write-Error -Message $line -ErrorAction Continue }
            'DEBUG' { Microsoft.PowerShell.Utility\Write-Verbose -Message $line }
        }
    }

    [void] Info([string] $message) { $this.Emit('INFO', $message) }
    [void] Warn([string] $message) { $this.Emit('WARN', $message) }
    [void] Error([string] $message) { $this.Emit('ERROR', $message) }
    [void] Debug([string] $message) { $this.Emit('DEBUG', $message) }
}
