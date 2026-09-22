#Requires -Version 7.4
<#
    Work item: A4 - enums, exceptions, SqlPowerDocBase (plan section 4, A4; code in section 3.1).
    Gate (plan section 4, A4): "...and that each exception type carries Target through all three
    constructors."

    Target is the point of the hierarchy: wrappers call Stop-PSFFunction -Target
    $_.Exception.Target instead of parsing the message string (plan section 3.1), so a constructor
    that drops it is a silent defect in every wrapper at once.
#>

BeforeDiscovery {
    $script:ExceptionTypes = @(
        @{ Type = 'SqlPowerDocException'; Base = 'System.Exception' }
        @{ Type = 'SqlPowerDocPlatformException'; Base = 'SqlPowerDocException' }
        @{ Type = 'SqlPowerDocConnectionException'; Base = 'SqlPowerDocException' }
        @{ Type = 'SqlPowerDocUnsupportedVersionException'; Base = 'SqlPowerDocException' }
    )

    $script:DerivedTypes = @(
        $script:ExceptionTypes | Where-Object { $_.Base -eq 'SqlPowerDocException' }
    )
}

BeforeAll {
    $script:BuiltManifest = Join-Path $PSScriptRoot '..' '..' '..' 'output' 'SqlPowerDoc' '3.0.0' 'SqlPowerDoc.psd1'
    Import-Module -Name PSFramework -ErrorAction SilentlyContinue
    Import-Module -Name $script:BuiltManifest -Force -ErrorAction Stop
}

Describe 'SqlPowerDoc exception hierarchy' -Tag 'Unit' {

    It '<Type> derives from <Base>' -ForEach $script:ExceptionTypes {
        InModuleScope SqlPowerDoc -Parameters @{ TypeName = $Type; BaseName = $Base } {
            $type = $TypeName -as [type]
            $type | Should -Not -BeNullOrEmpty -Because "plan section 2.3 lists $TypeName in Classes/01-Exceptions.ps1"

            $expected = $BaseName -as [type]
            $expected | Should -Not -BeNullOrEmpty
            $type.BaseType | Should -Be $expected
        }
    }

    It '<Type> is an ordinary System.Exception, so try/catch and ErrorRecord work unchanged' -ForEach $script:ExceptionTypes {
        InModuleScope SqlPowerDoc -Parameters @{ TypeName = $Type } {
            $type = $TypeName -as [type]
            $type | Should -Not -BeNullOrEmpty

            [System.Exception].IsAssignableFrom($type) | Should -BeTrue
        }
    }
}

Describe 'SqlPowerDoc exception constructors' -Tag 'Unit' {

    It '<Type> sets Message alone from the one-argument constructor' -ForEach $script:ExceptionTypes {
        InModuleScope SqlPowerDoc -Parameters @{ TypeName = $Type } {
            $type = $TypeName -as [type]
            $type | Should -Not -BeNullOrEmpty

            $exception = $type::new('collection failed')

            $exception.Message | Should -Be 'collection failed'
            $exception.Target | Should -BeNullOrEmpty
            $exception.InnerException | Should -BeNullOrEmpty
        }
    }

    It '<Type> carries Target through the two-argument constructor' -ForEach $script:ExceptionTypes {
        InModuleScope SqlPowerDoc -Parameters @{ TypeName = $Type } {
            $type = $TypeName -as [type]
            $type | Should -Not -BeNullOrEmpty

            $exception = $type::new('collection failed', 'SPDHOST01')

            $exception.Message | Should -Be 'collection failed'
            $exception.Target | Should -Be 'SPDHOST01'
            $exception.InnerException | Should -BeNullOrEmpty
        }
    }

    It '<Type> carries Target and the inner exception through the three-argument constructor' -ForEach $script:ExceptionTypes {
        InModuleScope SqlPowerDoc -Parameters @{ TypeName = $Type } {
            $type = $TypeName -as [type]
            $type | Should -Not -BeNullOrEmpty

            $inner = [System.InvalidOperationException]::new('the WMI provider is unavailable')
            $exception = $type::new('collection failed', 'SPDHOST01', $inner)

            $exception.Message | Should -Be 'collection failed'
            $exception.Target | Should -Be 'SPDHOST01'
            $exception.InnerException | Should -Be $inner
            $exception.InnerException.Message | Should -Be 'the WMI provider is unavailable'
        }
    }

    It '<Type> exposes exactly the three documented constructors' -ForEach $script:ExceptionTypes {
        InModuleScope SqlPowerDoc -Parameters @{ TypeName = $Type } {
            $type = $TypeName -as [type]
            $type | Should -Not -BeNullOrEmpty

            # PowerShell classes do not inherit constructors, so every subclass has to redeclare
            # all three; this is what catches a subclass that quietly declares only one.
            $signatures = @(
                $type.GetConstructors() |
                    ForEach-Object { ($_.GetParameters() | ForEach-Object { $_.ParameterType.Name }) -join ',' }
            )

            $signatures | Should -HaveCount 3
            $signatures | Should -Contain 'String'
            $signatures | Should -Contain 'String,String'
            $signatures | Should -Contain 'String,String,Exception'
        }
    }
}

Describe 'SqlPowerDoc exception catch behaviour' -Tag 'Unit' {

    It '<Type> is caught by a catch block typed to SqlPowerDocException' -ForEach $script:DerivedTypes {
        InModuleScope SqlPowerDoc -Parameters @{ TypeName = $Type } {
            $type = $TypeName -as [type]
            $type | Should -Not -BeNullOrEmpty

            $caught = $null
            try { throw $type::new('collection failed', 'SPDHOST01') }
            catch [SqlPowerDocException] { $caught = $_ }

            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.GetType().Name | Should -Be $TypeName
            $caught.Exception.Target | Should -Be 'SPDHOST01'
        }
    }

    It 'survives the throw intact in the ErrorRecord a wrapper hands to Stop-PSFFunction' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocConnectionException' -as [type]) | Should -Not -BeNullOrEmpty

            $record = $null
            try { throw [SqlPowerDocConnectionException]::new('login failed', 'SPDSQL01\INST') }
            catch { $record = $_ }

            $record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $record.Exception | Should -BeOfType ([SqlPowerDocConnectionException])
            $record.Exception.Target | Should -Be 'SPDSQL01\INST'
        }
    }
}
