#Requires -Version 7.4
<#
    Work item A6 - PSFramework configuration initialisation.

    Asserts that every configuration key documented in plan section 3.12 exists after the
    module is imported, carries the documented default and type, that a pre-import override
    survives the `-Initialize` replay (plan section 3.12: "-Initialize is idempotent across
    repeated imports and replays any override a user set before the module declared the key"),
    and that no SqlServer-branded configuration exists (corrected_requirements.md: the SqlServer
    module is excluded entirely, so nothing in our own configuration schema should reference it).
#>

BeforeDiscovery {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

    # The documented schema (plan section 3.12), one row per key. Declared at discovery time
    # so the -ForEach blocks below can enumerate it before Run phase.
    $script:ExpectedConfiguration = @(
        @{ Name = 'SqlPowerDoc.Sql.ConnectTimeoutSeconds'; Default = 15; Type = [int] }
        @{ Name = 'SqlPowerDoc.Sql.QueryTimeoutSeconds'; Default = 600; Type = [int] }
        @{ Name = 'SqlPowerDoc.Sql.MinimumVersion'; Default = '13.0'; Type = [string] }
        @{ Name = 'SqlPowerDoc.Discovery.MaxParallelHosts'; Default = 10; Type = [int] }
        @{ Name = 'SqlPowerDoc.Discovery.TcpTimeoutMilliseconds'; Default = 1000; Type = [int] }
        @{ Name = 'SqlPowerDoc.Discovery.SqlBrowserPort'; Default = 1434; Type = [int] }
        @{ Name = 'SqlPowerDoc.Cim.OperationTimeoutSeconds'; Default = 60; Type = [int] }
        @{ Name = 'SqlPowerDoc.Collection.IncludeSystemObjects'; Default = $false; Type = [bool] }
        @{ Name = 'SqlPowerDoc.Collection.IncludeDatabaseObjectPermissions'; Default = $false; Type = [bool] }
        @{ Name = 'SqlPowerDoc.Export.DefaultTableStyle'; Default = 'Medium15'; Type = [string] }
        @{ Name = 'SqlPowerDoc.Export.DefaultColumnWidth'; Default = 18; Type = [int] }
        @{ Name = 'SqlPowerDoc.Export.ColorTheme'; Default = 'Office'; Type = [string] }
    )
}

BeforeAll {
    $script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ManifestPath = Join-Path $script:RepositoryRoot 'src' 'SqlPowerDoc' 'SqlPowerDoc.psd1'

    Import-Module PSFramework -ErrorAction Stop
    Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'SqlPowerDoc' -Force -ErrorAction SilentlyContinue
}

Describe 'SqlPowerDoc configuration schema' -Tag 'Unit' {

    It 'declares <Name> with default <Default> after import' -ForEach $script:ExpectedConfiguration {
        Get-PSFConfigValue -FullName $Name | Should -Be $Default
    }

    It 'declares <Name> as type <Type>' -ForEach $script:ExpectedConfiguration {
        (Get-PSFConfigValue -FullName $Name) | Should -BeOfType $Type
    }

    It 'declares SqlPowerDoc.Logging.Path as a non-null string' {
        $value = Get-PSFConfigValue -FullName 'SqlPowerDoc.Logging.Path'
        $value | Should -Not -BeNullOrEmpty
        $value | Should -BeOfType [string]
        $value | Should -Match 'SqlPowerDoc[\\/]Logs$'
    }

    It 'rejects an unrecognised SqlPowerDoc.Export.ColorTheme value' {
        { Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Export.ColorTheme' -Value 'NotARealTheme' -EnableException } |
            Should -Throw
    }

    It 'accepts a documented SqlPowerDoc.Export.ColorTheme value' {
        try {
            { Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Export.ColorTheme' -Value 'Blue Green' -EnableException } |
                Should -Not -Throw
        }
        finally {
            Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Export.ColorTheme' -Value 'Office'
        }
    }

    It 'exposes the full schema for a support-bundle dump via Get-PSFConfig -Module SqlPowerDoc' {
        $keys = Get-PSFConfig -Module 'SqlPowerDoc' | Select-Object -ExpandProperty FullName
        foreach ($expected in $script:ExpectedConfiguration) {
            $keys | Should -Contain $expected.Name
        }
        $keys | Should -Contain 'SqlPowerDoc.Logging.Path'
    }

    It 'declares no configuration key referencing the excluded SqlServer module' {
        $keys = Get-PSFConfig -Module 'SqlPowerDoc' | Select-Object -ExpandProperty FullName
        $keys | Should -Not -Match 'SqlServer'
    }

    Context 'when a value is overridden before the module is imported' {

        BeforeAll {
            Remove-Module -Name 'SqlPowerDoc' -Force -ErrorAction SilentlyContinue

            # Simulates a caller tuning a setting (e.g. in a profile) before ever importing
            # SqlPowerDoc. -Initialize must replay this value rather than clobber it.
            Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Sql.ConnectTimeoutSeconds' -Value 999

            Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
        }

        AfterAll {
            Reset-PSFConfig -Module 'SqlPowerDoc' -Name 'Sql.ConnectTimeoutSeconds'
            Remove-Module -Name 'SqlPowerDoc' -Force -ErrorAction SilentlyContinue
            Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
        }

        It 'keeps the pre-import override instead of resetting it to the documented default' {
            Get-PSFConfigValue -FullName 'SqlPowerDoc.Sql.ConnectTimeoutSeconds' | Should -Be 999
        }
    }
}
