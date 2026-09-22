#
# Tier 1x: the operating-system seam (plan sections 2.3 and 3.2).
#
# This class exists because of one measured fact: the CimCmdlets module is not shipped on Linux,
# so Get-CimInstance does not resolve and `Mock Get-CimInstance` fails with "Could not find
# Command". There is no way to unit-test a CIM collector on Linux by mocking the cmdlet. The only
# seam that works is an injectable object, so every OS-dependent call in the module goes through a
# method here and SqlPowerDocFakePlatform (Classes/12-) overrides it in tests.
#
# Six seams in two groups. GetCimInstance, NewCimSession, GetRegistryValue, and InvokeProcess are
# Windows-only and gated; TestTcpPort and ResolveDnsName are System.Net and run for real
# everywhere, so discovery's subnet sweep is genuinely testable on the Linux dev host.
#

class SqlPowerDocPlatform : SqlPowerDocBase {
    [bool] $IsWindowsHost
    [string] $PlatformName

    SqlPowerDocPlatform() : base() {
        $this.DetectPlatform()
    }

    SqlPowerDocPlatform([System.Management.Automation.PSCmdlet] $Cmdlet) : base($Cmdlet) {
        $this.DetectPlatform()
    }

    # RuntimeInformation, not $IsWindows: the automatic variable is a host convenience that a test
    # or a dot-sourced profile can shadow, and this ruling gates every collector in the module.
    hidden [void] DetectPlatform() {
        $this.IsWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Windows)
        $this.PlatformName = $(if ($this.IsWindowsHost) { 'Windows' } else { 'Unix' })
    }

    [bool] Supports([SqlPowerDocCapability] $Capability) {
        switch ($Capability) {
            ([SqlPowerDocCapability]::CimQuery) { return $this.IsWindowsHost }
            ([SqlPowerDocCapability]::RemoteRegistry) { return $this.IsWindowsHost }
            ([SqlPowerDocCapability]::LocalSecurityPolicy) { return $this.IsWindowsHost }
            ([SqlPowerDocCapability]::SqlServiceEnumeration) { return $this.IsWindowsHost }
            ([SqlPowerDocCapability]::WindowsAuthentication) { return $this.IsWindowsHost }

            # System.Drawing.Common is Windows-only on modern .NET, so ImportExcel's -AutoSize
            # fails on Linux even with libgdiplus installed. Nothing in the module branches on
            # this - column widths are always explicit - it is reported, not acted on.
            ([SqlPowerDocCapability]::ExcelAutoSize) { return $this.IsWindowsHost }

            ([SqlPowerDocCapability]::TcpProbe) { return $true }
            ([SqlPowerDocCapability]::DnsResolution) { return $true }
        }

        return $false
    }

    [void] AssertSupported([SqlPowerDocCapability] $Capability) {
        if (-not $this.Supports($Capability)) {
            throw [SqlPowerDocPlatformException]::new(
                "Capability '$Capability' requires a Windows control host (current platform: $($this.PlatformName)).",
                $this.PlatformName)
        }
    }

    # --- Windows-only seams -------------------------------------------------

    # Every CIM read in the module goes through here. The gate runs first so a Linux host reports
    # the missing capability by name instead of a CommandNotFoundException raised somewhere deep
    # inside a collector.
    [object[]] GetCimInstance([hashtable] $Query) {
        $this.AssertSupported([SqlPowerDocCapability]::CimQuery)
        return @(Get-CimInstance @Query -ErrorAction Stop)
    }

    [object] NewCimSession([string] $ComputerName, [pscredential] $Credential) {
        $this.AssertSupported([SqlPowerDocCapability]::CimQuery)

        $parameters = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
        if ($null -ne $Credential) { $parameters['Credential'] = $Credential }

        return (New-CimSession @parameters)
    }

    [object] GetRegistryValue([string] $ComputerName, [string] $Hive, [string] $Key, [string] $Name) {
        $this.AssertSupported([SqlPowerDocCapability]::RemoteRegistry)

        $base = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($Hive, $ComputerName)
        try {
            $subKey = $base.OpenSubKey($Key)
            if ($null -eq $subKey) { return $null }

            try { return $subKey.GetValue($Name) }
            finally { $subKey.Dispose() }
        }
        finally { $base.Dispose() }
    }

    # secedit.exe and gpresult.exe, for the local security policy collector. Nothing else in the
    # module may start a process: a meta-test greps the built module for Start-Process outside
    # this file.
    [string[]] InvokeProcess([string] $FilePath, [string[]] $Arguments, [int] $TimeoutSeconds) {
        $this.AssertSupported([SqlPowerDocCapability]::LocalSecurityPolicy)

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $FilePath
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo

        try {
            if (-not $process.Start()) {
                throw [SqlPowerDocPlatformException]::new("Failed to start '$FilePath'.", $this.PlatformName)
            }

            # Both pipes are drained before waiting. A child that fills the stderr buffer blocks
            # forever if only stdout is read, and gpresult is verbose enough to do it.
            $standardOutput = $process.StandardOutput.ReadToEndAsync()
            $standardError = $process.StandardError.ReadToEndAsync()

            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $process.Kill($true)
                throw [SqlPowerDocPlatformException]::new(
                    "'$FilePath' did not exit within $TimeoutSeconds second(s) and was terminated.",
                    $this.PlatformName)
            }

            # The timed overload returns as soon as the process ends; the parameterless one also
            # waits for the redirected streams to flush, so the task results below are complete.
            $process.WaitForExit()

            if ($process.ExitCode -ne 0) {
                throw [SqlPowerDocPlatformException]::new(
                    ("'{0}' exited with code {1}: {2}" -f $FilePath, $process.ExitCode, $standardError.Result.Trim()),
                    $this.PlatformName)
            }

            $text = $standardOutput.Result
            if ([string]::IsNullOrEmpty($text)) { return @() }

            return @($text.TrimEnd("`r", "`n") -split '\r?\n')
        }
        finally { $process.Dispose() }
    }

    # --- Cross-platform seams (real implementations, exercised on Linux) ----

    [bool] TestTcpPort([string] $ComputerName, [int] $Port, [int] $TimeoutMilliseconds) {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $task = $client.ConnectAsync($ComputerName, $Port)
            return ($task.Wait($TimeoutMilliseconds) -and $client.Connected)
        }
        catch { return $false }
        finally { $client.Dispose() }
    }

    # A name that does not resolve is a normal result of a subnet sweep, not an error, so this
    # returns an empty set rather than throwing.
    [System.Net.IPAddress[]] ResolveDnsName([string] $Name) {
        try { return [System.Net.Dns]::GetHostAddresses($Name) }
        catch { return @() }
    }
}
