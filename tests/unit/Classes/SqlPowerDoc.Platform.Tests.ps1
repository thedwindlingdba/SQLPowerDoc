#Requires -Version 7.4
<#
    Work item: A7 - platform abstraction (plan section 4, A7; code in section 3.2).

    Gate (plan section 4, A7): "on Linux, each Windows-gated seam throws
    SqlPowerDocPlatformException naming the capability and the current platform; TestTcpPort and
    ResolveDnsName return real results against localhost; SqlPowerDocFakePlatform returns canned
    CIM data and records calls in order."

    The whole class exists because of one measured fact (validated_runtime_findings.md #1): the
    CimCmdlets module is not shipped on Linux, so Get-CimInstance does not resolve and Pester
    cannot mock it - `Mock Get-CimInstance` fails with "Could not find Command". The only seam
    that works is an injectable object, which is what these tests pin down.

    Everything that touches a class runs inside InModuleScope: Import-Module does not export
    class or enum types to the caller's scope, only `using module` does, so a type lookup from
    the test's own scope returns $null however correct the module is.
#>

BeforeDiscovery {
    $script:OnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)

    # Plan section 3.2: the first group is Windows-only and gated, the second is genuinely
    # cross-platform and runs for real on Linux.
    $script:WindowsOnlyCapabilities = @(
        'CimQuery'
        'RemoteRegistry'
        'LocalSecurityPolicy'
        'SqlServiceEnumeration'
        'WindowsAuthentication'
        'ExcelAutoSize'
    )
    $script:CrossPlatformCapabilities = @('TcpProbe', 'DnsResolution')
}

BeforeAll {
    $script:BuiltManifest = Join-Path $PSScriptRoot '..' '..' '..' 'output' 'SqlPowerDoc' '3.0.0' 'SqlPowerDoc.psd1'
    Import-Module -Name PSFramework -ErrorAction SilentlyContinue
    Import-Module -Name $script:BuiltManifest -Force -ErrorAction Stop

    $script:OnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
}

Describe 'SqlPowerDocPlatform construction' -Tag 'Unit' {

    It 'derives from SqlPowerDocBase so the seam logs and reads configuration like every other class' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocPlatform' -as [type]
            $type | Should -Not -BeNullOrEmpty -Because 'plan section 2.3 lists Classes/11-SqlPowerDocPlatform.ps1'
            $type.BaseType.Name | Should -Be 'SqlPowerDocBase'
        }
    }

    It 'detects the host operating system at construction time' {
        $expected = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Windows)

        $platform = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty
            [SqlPowerDocPlatform]::new()
        }

        $platform.IsWindowsHost | Should -Be $expected
        $platform.PlatformName | Should -Be $(if ($expected) { 'Windows' } else { 'Unix' })
    }

    It 'accepts a PSCmdlet so platform log lines are attributed to the calling wrapper' {
        Mock -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -MockWith { }

        InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            # The Log call has to happen while the wrapper is still on the stack: a PSCmdlet
            # outlives its invocation but its MyInvocation.MyCommand does not, and SqlPowerDocBase
            # falls back to the class name once it is gone.
            function Invoke-A7ConstructionProbe {
                [CmdletBinding()]
                param()

                $instance = [SqlPowerDocPlatform]::new($PSCmdlet)
                $instance.Log('Verbose', 'probing capabilities')
                $instance
            }

            $platform = Invoke-A7ConstructionProbe
            $platform | Should -Not -BeNullOrEmpty
            $platform.IsWindowsHost | Should -BeOfType [bool]
        }

        Should -Invoke -CommandName Write-PSFMessage -ModuleName SqlPowerDoc -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters.ContainsKey('PSCmdlet') -and
            $PesterBoundParameters.FunctionName -eq 'Invoke-A7ConstructionProbe'
        }
    }
}

Describe 'SqlPowerDocPlatform.Supports' -Tag 'Unit' {

    It 'answers every value of SqlPowerDocCapability' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $platform = [SqlPowerDocPlatform]::new()

            foreach ($capability in [enum]::GetValues([SqlPowerDocCapability])) {
                $platform.Supports($capability) | Should -BeOfType [bool] -Because "$capability must have a ruling"
            }
        }
    }

    It 'gates <_> on a Windows control host' -ForEach $script:WindowsOnlyCapabilities {
        $answer = InModuleScope SqlPowerDoc -Parameters @{ CapabilityName = $_ } {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $platform = [SqlPowerDocPlatform]::new()
            [PSCustomObject]@{
                Supported = $platform.Supports([SqlPowerDocCapability] $CapabilityName)
                OnWindows = $platform.IsWindowsHost
            }
        }

        $answer.Supported | Should -Be $answer.OnWindows
    }

    It 'runs <_> everywhere, because it is System.Net and not Windows' -ForEach $script:CrossPlatformCapabilities {
        InModuleScope SqlPowerDoc -Parameters @{ CapabilityName = $_ } {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocPlatform]::new().Supports([SqlPowerDocCapability] $CapabilityName) | Should -BeTrue
        }
    }
}

Describe 'SqlPowerDocPlatform.AssertSupported' -Tag 'Unit' {

    It 'returns without complaint for a capability the host has' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            { [SqlPowerDocPlatform]::new().AssertSupported([SqlPowerDocCapability]::TcpProbe) } |
                Should -Not -Throw
        }
    }

    It 'throws SqlPowerDocPlatformException naming the capability and the platform' -Skip:$script:OnWindows {
        $exception = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            try {
                [SqlPowerDocPlatform]::new().AssertSupported([SqlPowerDocCapability]::CimQuery)
                $null
            }
            catch {
                $_.Exception
            }
        }

        $exception | Should -Not -BeNullOrEmpty
        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
        $exception.Message | Should -Match 'CimQuery'
        $exception.Message | Should -Match 'Unix'

        # Target carries the platform name so a wrapper can set -Target without parsing the
        # message (plan section 3.1).
        $exception.Target | Should -Be 'Unix'
    }
}

Describe 'SqlPowerDocPlatform Windows-only seams on a non-Windows host' -Tag 'Unit' -Skip:$script:OnWindows {

    # Each of these asserts the gate fires BEFORE the underlying command is reached. If it did
    # not, the failure would be a CommandNotFoundException from a cmdlet that does not exist on
    # this host - which is exactly the diagnostic the platform class was built to replace.

    It 'refuses GetCimInstance rather than reaching a Get-CimInstance that does not exist here' {
        $exception = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            # Proves the premise: there is no command to fall through to, and none to mock.
            Get-Command -Name 'Get-CimInstance' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty

            try { [SqlPowerDocPlatform]::new().GetCimInstance(@{ ClassName = 'Win32_OperatingSystem' }); $null }
            catch { $_.Exception }
        }

        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
        $exception.Message | Should -Match 'CimQuery'
    }

    It 'refuses NewCimSession' {
        $exception = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            try { [SqlPowerDocPlatform]::new().NewCimSession('SPDHOST01', $null); $null }
            catch { $_.Exception }
        }

        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
        $exception.Message | Should -Match 'CimQuery'
    }

    It 'refuses GetRegistryValue' {
        $exception = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            try {
                [SqlPowerDocPlatform]::new().GetRegistryValue(
                    'SPDHOST01', 'LocalMachine', 'SOFTWARE\Microsoft\Microsoft SQL Server', 'InstalledInstances')
                $null
            }
            catch { $_.Exception }
        }

        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
        $exception.Message | Should -Match 'RemoteRegistry'
    }

    It 'refuses InvokeProcess' {
        $exception = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            try { [SqlPowerDocPlatform]::new().InvokeProcess('secedit.exe', @('/export'), 30); $null }
            catch { $_.Exception }
        }

        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
        $exception.Message | Should -Match 'LocalSecurityPolicy'
    }
}

Describe 'SqlPowerDocPlatform.TestTcpPort' -Tag 'Unit' {

    BeforeAll {
        # A real listener on an ephemeral loopback port. System.Net.Sockets is cross-platform,
        # so this seam is tested for real on Linux rather than faked (plan section 5.3).
        $script:Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $script:Listener.Start()
        $script:OpenPort = $script:Listener.LocalEndpoint.Port

        $closed = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $closed.Start()
        $script:ClosedPort = $closed.LocalEndpoint.Port
        $closed.Stop()
    }

    AfterAll {
        if ($script:Listener) { $script:Listener.Stop() }
    }

    It 'returns true for a port that is actually listening' {
        InModuleScope SqlPowerDoc -Parameters @{ Port = $script:OpenPort } {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocPlatform]::new().TestTcpPort('127.0.0.1', $Port, 2000) | Should -BeTrue
        }
    }

    It 'returns false, and does not throw, for a port nothing is listening on' {
        InModuleScope SqlPowerDoc -Parameters @{ Port = $script:ClosedPort } {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocPlatform]::new().TestTcpPort('127.0.0.1', $Port, 2000) | Should -BeFalse
        }
    }

    It 'returns false when the host name itself does not resolve' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocPlatform]::new().TestTcpPort('spd-no-such-host.invalid', 1433, 2000) | Should -BeFalse
        }
    }
}

Describe 'SqlPowerDocPlatform.ResolveDnsName' -Tag 'Unit' {

    It 'resolves localhost to a loopback address' {
        $addresses = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocPlatform]::new().ResolveDnsName('localhost')
        }

        $addresses | Should -Not -BeNullOrEmpty
        @($addresses | Where-Object { [System.Net.IPAddress]::IsLoopback($_) }) | Should -Not -BeNullOrEmpty
    }

    It 'returns an empty set instead of throwing when a name does not resolve' {
        $addresses = InModuleScope SqlPowerDoc {
            ('SqlPowerDocPlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocPlatform]::new().ResolveDnsName('spd-no-such-host.invalid')
        }

        @($addresses) | Should -HaveCount 0
    }
}

Describe 'SqlPowerDocFakePlatform' -Tag 'Unit' {

    It 'is a real subclass of SqlPowerDocPlatform, which is why it ships inside the module' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocFakePlatform' -as [type]
            $type | Should -Not -BeNullOrEmpty -Because 'plan section 3.2: a class declared in a .Tests.ps1 file is in a different parse scope and cannot inherit from a module-internal class'
            $type.BaseType.Name | Should -Be 'SqlPowerDocPlatform'
        }
    }

    It 'reports every capability supported so collector logic runs on Linux' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $fake = [SqlPowerDocFakePlatform]::new()

            foreach ($capability in [enum]::GetValues([SqlPowerDocCapability])) {
                $fake.Supports($capability) | Should -BeTrue -Because "$capability must be reachable under the fake"
            }
        }
    }

    It 'can be told to report nothing, so the unsupported-host path is testable too' {
        $exception = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $fake = [SqlPowerDocFakePlatform]::new()
            $fake.ForceWindows = $false

            $fake.Supports([SqlPowerDocCapability]::CimQuery) | Should -BeFalse

            try { $fake.GetCimInstance(@{ ClassName = 'Win32_Bios' }); $null }
            catch { $_.Exception }
        }

        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
    }

    It 'returns canned CIM data keyed on the class name' {
        $result = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $fake = [SqlPowerDocFakePlatform]::new()
            $fake.Responses['Win32_OperatingSystem'] = [PSCustomObject]@{
                Caption = 'Microsoft Windows Server 2019 Standard'
                Version = '10.0.17763'
            }

            $fake.GetCimInstance(@{ ClassName = 'Win32_OperatingSystem'; ComputerName = 'SPDHOST01' })
        }

        @($result) | Should -HaveCount 1
        $result[0].Caption | Should -Be 'Microsoft Windows Server 2019 Standard'
    }

    It 'prefers a ComputerName-scoped response over the bare class name' {
        $result = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $fake = [SqlPowerDocFakePlatform]::new()
            $fake.Responses['Win32_ComputerSystem'] = [PSCustomObject]@{ Name = 'DEFAULT' }
            $fake.Responses['Win32_ComputerSystem@SPDHOST02'] = [PSCustomObject]@{ Name = 'SPDHOST02' }

            $fake.GetCimInstance(@{ ClassName = 'Win32_ComputerSystem'; ComputerName = 'SPDHOST02' })
        }

        $result[0].Name | Should -Be 'SPDHOST02'
    }

    It 'returns an empty set for a class nothing was staged for' {
        $result = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocFakePlatform]::new().GetCimInstance(@{ ClassName = 'Win32_UnStaged' })
        }

        @($result) | Should -HaveCount 0
    }

    It 'records every call, in order, with the query the collector actually asked for' {
        $calls = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $fake = [SqlPowerDocFakePlatform]::new()
            $null = $fake.GetCimInstance(@{
                    ClassName    = 'Win32_Bios'
                    ComputerName = 'SPDHOST01'
                    Property     = @('SerialNumber', 'SMBIOSBIOSVersion')
                })
            $null = $fake.GetCimInstance(@{ ClassName = 'Win32_ComputerSystem'; ComputerName = 'SPDHOST01' })

            $fake.Calls
        }

        # Asserting the REQUEST is what catches a collector that quietly starts pulling whole
        # instances instead of an explicit -Property list (plan section 5.5).
        @($calls) | Should -HaveCount 2
        $calls[0].ClassName | Should -Be 'Win32_Bios'
        $calls[0].ComputerName | Should -Be 'SPDHOST01'
        $calls[0].Property | Should -Contain 'SerialNumber'
        $calls[1].ClassName | Should -Be 'Win32_ComputerSystem'
    }

    It 'serves an associator chain step by step from the response queue' {
        $result = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            # GetDisk is a dependent chain, not four independent lookups: each hop's filter is
            # built from the previous result, so a dictionary keyed only on class name cannot
            # stage it (plan section 5.5).
            $fake = [SqlPowerDocFakePlatform]::new()
            $fake.EnqueueResponse('Win32_DiskPartition', @([PSCustomObject]@{ DeviceID = 'Disk #0, Partition #0' }))
            $fake.EnqueueResponse('Win32_DiskPartition', @([PSCustomObject]@{ DeviceID = 'Disk #1, Partition #0' }))
            $fake.Responses['Win32_DiskPartition'] = [PSCustomObject]@{ DeviceID = 'fallback' }

            @(
                $fake.GetCimInstance(@{ Query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='\\.\PHYSICALDRIVE0'} WHERE ResultClass = Win32_DiskPartition" })
                $fake.GetCimInstance(@{ Query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='\\.\PHYSICALDRIVE1'} WHERE ResultClass = Win32_DiskPartition" })
                $fake.GetCimInstance(@{ Query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='\\.\PHYSICALDRIVE2'} WHERE ResultClass = Win32_DiskPartition" })
            )
        }

        $result[0].DeviceID | Should -Be 'Disk #0, Partition #0'
        $result[1].DeviceID | Should -Be 'Disk #1, Partition #0'

        # Drained queue falls back to the single-shot Responses table.
        $result[2].DeviceID | Should -Be 'fallback'
    }

    It 'returns staged registry values and records the lookup' {
        $probe = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $fake = [SqlPowerDocFakePlatform]::new()
            $fake.Registry['LocalMachine\SOFTWARE\Microsoft\Microsoft SQL Server\InstalledInstances'] = @('MSSQLSERVER')

            [PSCustomObject]@{
                Value = $fake.GetRegistryValue(
                    'SPDHOST01', 'LocalMachine', 'SOFTWARE\Microsoft\Microsoft SQL Server', 'InstalledInstances')
                Calls = $fake.Calls
            }
        }

        $probe.Value | Should -Be @('MSSQLSERVER')
        @($probe.Calls) | Should -HaveCount 1
        $probe.Calls[0].ComputerName | Should -Be 'SPDHOST01'
        $probe.Calls[0].Registry | Should -Be 'LocalMachine\SOFTWARE\Microsoft\Microsoft SQL Server\InstalledInstances'
    }

    It 'answers TestTcpPort from the staged port table instead of opening a socket' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $fake = [SqlPowerDocFakePlatform]::new()
            $fake.OpenPorts['SPDHOST01:1433'] = $true

            $fake.TestTcpPort('SPDHOST01', 1433, 1000) | Should -BeTrue
            $fake.TestTcpPort('SPDHOST01', 1434, 1000) | Should -BeFalse
        }
    }

    It 'hands back a canned CIM session rather than calling New-CimSession' {
        $session = InModuleScope SqlPowerDoc {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocFakePlatform]::new().NewCimSession('SPDHOST01', $null)
        }

        $session | Should -Not -BeNullOrEmpty
        $session.ComputerName | Should -Be 'SPDHOST01'
    }
}

Describe 'SqlPowerDocPlatform.InvokeProcess' -Tag 'Unit' {

    BeforeAll {
        # The gate on InvokeProcess is LocalSecurityPolicy (secedit.exe / gpresult.exe), so the
        # implementation itself is unreachable on Linux through the real class. Lifting the gate
        # with the fake runs the real System.Diagnostics.Process code path here - the same code
        # that shells out on Windows.
        $script:EchoPath = if ($script:OnWindows) { "$env:SystemRoot\System32\cmd.exe" } else { '/bin/sh' }
        $script:EchoArguments = if ($script:OnWindows) { @('/c', 'echo first& echo second') } else { @('-c', 'echo first; echo second') }
    }

    It 'returns the child process stdout, one element per line' {
        $lines = InModuleScope SqlPowerDoc -Parameters @{ Path = $script:EchoPath; Arguments = $script:EchoArguments } {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocFakePlatform]::new().InvokeProcess($Path, $Arguments, 30)
        }

        @($lines) | Should -HaveCount 2
        $lines[0].Trim() | Should -Be 'first'
        $lines[1].Trim() | Should -Be 'second'
    }

    It 'throws SqlPowerDocPlatformException carrying stderr when the child fails' {
        $exception = InModuleScope SqlPowerDoc -Parameters @{ Path = $script:EchoPath; OnWindows = $script:OnWindows } {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $arguments = if ($OnWindows) { @('/c', 'echo broken 1>&2& exit 3') } else { @('-c', 'echo broken 1>&2; exit 3') }

            try { [SqlPowerDocFakePlatform]::new().InvokeProcess($Path, $arguments, 30); $null }
            catch { $_.Exception }
        }

        $exception | Should -Not -BeNullOrEmpty
        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
        $exception.Message | Should -Match '3'
        $exception.Message | Should -Match 'broken'
    }

    It 'kills the child and throws rather than hanging when it outlives the timeout' {
        $exception = InModuleScope SqlPowerDoc -Parameters @{ Path = $script:EchoPath; OnWindows = $script:OnWindows } {
            ('SqlPowerDocFakePlatform' -as [type]) | Should -Not -BeNullOrEmpty

            $arguments = if ($OnWindows) { @('/c', 'ping -n 30 127.0.0.1 > nul') } else { @('-c', 'sleep 30') }

            try { [SqlPowerDocFakePlatform]::new().InvokeProcess($Path, $arguments, 1); $null }
            catch { $_.Exception }
        }

        $exception | Should -Not -BeNullOrEmpty
        $exception.GetType().Name | Should -Be 'SqlPowerDocPlatformException'
        $exception.Message | Should -Match 'did not exit'
    }
}
