#Requires -Version 7.4
<#
    Work item: A8 - first vertical slice, Get-SqlPowerDocCapability (plan section 4, A8).

    Gate (plan section 4, A8): "one row per SqlPowerDocCapability value; CimQuery.Supported is
    $false on Linux and the capability appears in the built manifest's FunctionsToExport."

    The point of this slice is not the function - it is the chain it proves: enum -> base ->
    platform -> private singleton -> public wrapper -> ModuleBuilder export list, all the way
    through the built module, before anyone writes a collector.
#>

BeforeDiscovery {
    $script:OnWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)
}

BeforeAll {
    $script:BuiltRoot = Join-Path $PSScriptRoot '..' '..' 'output' 'SqlPowerDoc' '3.0.0'
    $script:BuiltManifest = Join-Path $script:BuiltRoot 'SqlPowerDoc.psd1'

    Import-Module -Name PSFramework -ErrorAction SilentlyContinue
    Import-Module -Name $script:BuiltManifest -Force -ErrorAction Stop
}

Describe 'Get-SqlPowerDocCapability surface' -Tag 'Unit' {

    It 'is exported from the built module' {
        Get-Command -Name 'Get-SqlPowerDocCapability' -Module 'SqlPowerDoc' -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'appears in the built manifest FunctionsToExport, not behind a wildcard' {
        $manifest = Import-PowerShellDataFile -Path $script:BuiltManifest

        $manifest.FunctionsToExport | Should -Contain 'Get-SqlPowerDocCapability'
        $manifest.FunctionsToExport | Should -Not -Contain '*'
    }

    It 'exports no private helper: the singleton stays inside the module' {
        Get-Command -Name 'Get-SqlPowerDocPlatform' -Module 'SqlPowerDoc' -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty
    }

    It 'takes -EnableException like every other exported function (plan section 2.4)' {
        (Get-Command -Name 'Get-SqlPowerDocCapability').Parameters.Keys | Should -Contain 'EnableException'
    }

    It 'takes the hidden -Platform override the test suite injects through' {
        $parameter = (Get-Command -Name 'Get-SqlPowerDocCapability').Parameters['Platform']

        $parameter | Should -Not -BeNullOrEmpty
        $parameter.ParameterType.Name | Should -Be 'SqlPowerDocPlatform'
    }
}

Describe 'Get-SqlPowerDocCapability output' -Tag 'Unit' {

    BeforeAll {
        $script:Rows = @(Get-SqlPowerDocCapability)
        $script:CapabilityNames = InModuleScope SqlPowerDoc { [enum]::GetNames([SqlPowerDocCapability]) }
    }

    It 'returns exactly one row per SqlPowerDocCapability value' {
        $script:Rows | Should -HaveCount $script:CapabilityNames.Count
        @($script:Rows.Capability | ForEach-Object { "$_" } | Sort-Object) |
            Should -Be @($script:CapabilityNames | Sort-Object)
    }

    It 'reports Supported as a boolean and names the host platform on every row' {
        foreach ($row in $script:Rows) {
            $row.Supported | Should -BeOfType [bool]
            $row.PlatformName | Should -Not -BeNullOrEmpty
        }
    }

    It 'reports CimQuery as unsupported on a non-Windows control host' -Skip:$script:OnWindows {
        $row = $script:Rows | Where-Object { "$($_.Capability)" -eq 'CimQuery' }

        $row.Supported | Should -BeFalse
        $row.PlatformName | Should -Be 'Unix'
    }

    It 'reports TcpProbe as supported, because it is System.Net and runs anywhere' {
        ($script:Rows | Where-Object { "$($_.Capability)" -eq 'TcpProbe' }).Supported | Should -BeTrue
    }
}

Describe 'Get-SqlPowerDocCapability platform injection' -Tag 'Unit' {

    It 'reports what the injected platform says, not what the host says' {
        $fake = InModuleScope SqlPowerDoc { [SqlPowerDocFakePlatform]::new() }

        $rows = @(Get-SqlPowerDocCapability -Platform $fake)

        $rows | Should -Not -BeNullOrEmpty
        @($rows | Where-Object { -not $_.Supported }) | Should -HaveCount 0
    }

    It 'reports nothing supported when the injected platform gates everything off' {
        $fake = InModuleScope SqlPowerDoc {
            $instance = [SqlPowerDocFakePlatform]::new()
            $instance.ForceWindows = $false
            $instance
        }

        @(Get-SqlPowerDocCapability -Platform $fake | Where-Object { $_.Supported }) | Should -HaveCount 0
    }
}

Describe 'Get-SqlPowerDocPlatform singleton' -Tag 'Unit' {

    It 'detects the operating system once per import and hands back the same instance' {
        $same = InModuleScope SqlPowerDoc {
            $first = Get-SqlPowerDocPlatform
            $second = Get-SqlPowerDocPlatform

            $first | Should -Not -BeNullOrEmpty
            [object]::ReferenceEquals($first, $second)
        }

        $same | Should -BeTrue
    }

    It 'returns a SqlPowerDocPlatform' {
        InModuleScope SqlPowerDoc {
            (Get-SqlPowerDocPlatform).GetType().Name | Should -Be 'SqlPowerDocPlatform'
        }
    }
}
