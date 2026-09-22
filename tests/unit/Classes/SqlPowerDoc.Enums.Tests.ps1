#Requires -Version 7.4
<#
    Work item: A4 - enums, exceptions, SqlPowerDocBase (plan section 4, A4; code in section 3.1).
    Gate (plan section 4, A4): "unit tests asserting Log passes -FunctionName and -PSCmdlet, that
    Config falls back when a key is absent, and that each exception type carries Target through all
    three constructors." This file covers the enum half of Classes/00-Enums.ps1, which section 2.3
    names as the four enums the rest of the hierarchy is typed against.

    Everything runs inside InModuleScope: Import-Module does not export class or enum types to the
    caller's scope - only `using module` does - so a type lookup from the test's own scope returns
    $null however correct the module is. Verified on this VM before the tests were written.
#>

BeforeDiscovery {
    $script:EnumNames = @(
        'SqlPowerDocCapability'
        'SqlPowerDocSqlEdition'
        'SqlPowerDocCollectionScope'
        'SqlPowerDocSchemaScope'
    )
}

BeforeAll {
    $script:BuiltManifest = Join-Path $PSScriptRoot '..' '..' '..' 'output' 'SqlPowerDoc' '3.0.0' 'SqlPowerDoc.psd1'
    Import-Module -Name PSFramework -ErrorAction SilentlyContinue
    Import-Module -Name $script:BuiltManifest -Force -ErrorAction Stop
}

Describe 'SqlPowerDoc enums' -Tag 'Unit' {

    It 'declares <_> as an enum' -ForEach $script:EnumNames {
        InModuleScope SqlPowerDoc -Parameters @{ EnumName = $_ } {
            $type = $EnumName -as [type]
            $type | Should -Not -BeNullOrEmpty -Because "plan section 2.3 lists $EnumName in Classes/00-Enums.ps1"
            $type.IsEnum | Should -BeTrue
        }
    }

    It 'declares <_> in the first-loaded class file' -ForEach $script:EnumNames {
        $enumFile = Join-Path $PSScriptRoot '..' '..' '..' 'src' 'SqlPowerDoc' 'Classes' '00-Enums.ps1'
        $enumFile | Should -Exist
        Get-Content -Path $enumFile -Raw | Should -Match "(?m)^enum\s+$_\b"
    }
}

Describe 'SqlPowerDocCapability' -Tag 'Unit' {

    It 'names exactly the platform seams and gates from plan section 3.2' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocCapability' -as [type]
            $type | Should -Not -BeNullOrEmpty

            [enum]::GetNames($type) | Should -Be @(
                'CimQuery'
                'RemoteRegistry'
                'LocalSecurityPolicy'
                'SqlServiceEnumeration'
                'WindowsAuthentication'
                'ExcelAutoSize'
                'TcpProbe'
                'DnsResolution'
            )
        }
    }
}

Describe 'SqlPowerDocSqlEdition' -Tag 'Unit' {

    It 'defaults to Unknown so an unparsed edition is never mistaken for a real SKU' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocSqlEdition' -as [type]
            $type | Should -Not -BeNullOrEmpty

            [int][SqlPowerDocSqlEdition]::Unknown | Should -Be 0
            [SqlPowerDocSqlEdition] 0 | Should -Be ([SqlPowerDocSqlEdition]::Unknown)
        }
    }

    It 'covers the SKUs the legacy code branched on' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocSqlEdition' -as [type]
            $type | Should -Not -BeNullOrEmpty

            $names = [enum]::GetNames($type)

            # Express is gated out of two collectors by the legacy engine module's 'Express*' tests,
            # and its assessment rule fires on anything that is not Standard, Enterprise, or
            # Developer - so every edition those two checks can see needs a name here.
            foreach ($required in 'Express', 'Web', 'Standard', 'BusinessIntelligence', 'Developer', 'Enterprise', 'Evaluation', 'AzureSqlDatabase') {
                $names | Should -Contain $required
            }
        }
    }

    It 'orders on-premises SKUs by capability so a comparison means something' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocSqlEdition' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocSqlEdition]::Express | Should -BeLessThan ([SqlPowerDocSqlEdition]::Standard)
            [SqlPowerDocSqlEdition]::Standard | Should -BeLessThan ([SqlPowerDocSqlEdition]::Enterprise)
        }
    }
}

Describe 'SqlPowerDocCollectionScope' -Tag 'Unit' {

    It 'is a flags enum, because a caller selects several sections at once' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocCollectionScope' -as [type]
            $type | Should -Not -BeNullOrEmpty

            $type.GetCustomAttributes([System.FlagsAttribute], $false) | Should -Not -BeNullOrEmpty
        }
    }

    It 'names one member per method group in plan section 3.6' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocCollectionScope' -as [type]
            $type | Should -Not -BeNullOrEmpty

            [enum]::GetNames($type) | Should -Be @(
                'None'
                'Hardware'
                'OperatingSystem'
                'RuntimeState'
                'Security'
                'Software'
                'Network'
                'Web'
                'All'
            )
        }
    }

    It 'gives every section a distinct single bit' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocCollectionScope' -as [type]
            $type | Should -Not -BeNullOrEmpty

            $sections = @(
                [enum]::GetValues($type) |
                    Where-Object { $_ -ne [SqlPowerDocCollectionScope]::None -and $_ -ne [SqlPowerDocCollectionScope]::All }
            )

            foreach ($section in $sections) {
                $value = [int] $section
                # x -band (x - 1) is zero only for a power of two, i.e. exactly one bit set.
                ($value -band ($value - 1)) | Should -Be 0 -Because "$section must be independently selectable"
            }

            @($sections | Select-Object -Unique).Count | Should -Be $sections.Count
        }
    }

    It 'defines All as the union of every section and None as no bits at all' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocCollectionScope' -as [type]
            $type | Should -Not -BeNullOrEmpty

            [int][SqlPowerDocCollectionScope]::None | Should -Be 0

            $union = 0
            [enum]::GetValues($type) |
                Where-Object { $_ -ne [SqlPowerDocCollectionScope]::None -and $_ -ne [SqlPowerDocCollectionScope]::All } |
                ForEach-Object { $union = $union -bor [int] $_ }

            [int][SqlPowerDocCollectionScope]::All | Should -Be $union
        }
    }

    It 'composes sections with -bor' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocCollectionScope' -as [type]) | Should -Not -BeNullOrEmpty

            $scope = [SqlPowerDocCollectionScope]::Hardware -bor [SqlPowerDocCollectionScope]::Network

            $scope.HasFlag([SqlPowerDocCollectionScope]::Hardware) | Should -BeTrue
            $scope.HasFlag([SqlPowerDocCollectionScope]::Network) | Should -BeTrue
            $scope.HasFlag([SqlPowerDocCollectionScope]::Software) | Should -BeFalse
        }
    }
}

Describe 'SqlPowerDocSchemaScope' -Tag 'Unit' {

    It 'names the three parent object types the legacy 2-suffixed collectors split on' {
        InModuleScope SqlPowerDoc {
            $type = 'SqlPowerDocSchemaScope' -as [type]
            $type | Should -Not -BeNullOrEmpty

            # Get-ColumnInformation / Get-ColumnInformation2 and their three siblings existed only
            # because the legacy module duplicated each collector per parent object type; plan
            # section 6 collapses all four pairs onto this enum.
            [enum]::GetNames($type) | Should -Be @('Table', 'View', 'UserDefinedFunction')
        }
    }
}
