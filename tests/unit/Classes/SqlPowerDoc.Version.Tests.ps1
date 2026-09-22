#Requires -Version 7.4
<#
    Work item: B1 - SqlPowerDocVersion (plan section 4, B1; design in plan section 3.3).

    Gate (plan section 4, B1): Name/label returns 2016/2017/2019/2022 for majors 13-16;
    IsSupported is false for every pre-2016 major the legacy cascade's newest branch (2012)
    silently let 2016+ servers fall through to (8.0/9.0/10.0/10.50/11.0/12.0); AssertSupported
    throws SqlPowerDocUnsupportedVersionException for anything IsSupported rejects.

    SqlPowerDocVersion is a static helper (no SqlPowerDocBase, no instance state), so every test
    below calls the class directly rather than constructing an instance - there is nothing to
    construct.

    Everything that touches the class runs inside InModuleScope: Import-Module does not export
    class or enum types to the caller's scope, only `using module` does (see
    SqlPowerDoc.Platform.Tests.ps1 for the same note).
#>

BeforeDiscovery {
    # Major version numbers, per plan section 3.3: 13=2016, 14=2017, 15=2019, 16=2022. Only these
    # four are supported.
    $script:SupportedVersions = @(
        @{ Version = [System.Version] '13.0'; Label = '2016' }
        @{ Version = [System.Version] '14.0'; Label = '2017' }
        @{ Version = [System.Version] '15.0'; Label = '2019' }
        @{ Version = [System.Version] '16.0'; Label = '2022' }
    )

    # The six versions plan section 7 removes. The legacy cascade's newest branch was 2012, so a
    # 2016+ server silently took the 2012 code path - the new gate must refuse these outright
    # instead of repeating that mistake going forward.
    $script:UnsupportedVersions = @(
        @{ Version = [System.Version] '9.0'; Name = 'SQL Server 2005' }
        @{ Version = [System.Version] '10.0'; Name = 'SQL Server 2008' }
        @{ Version = [System.Version] '10.50'; Name = 'SQL Server 2008 R2' }
        @{ Version = [System.Version] '11.0'; Name = 'SQL Server 2012' }
        @{ Version = [System.Version] '12.0'; Name = 'SQL Server 2014' }
    )

    # SERVERPROPERTY('EngineEdition') / Microsoft.SqlServer.Management.Common.DatabaseEngineEdition
    # - the only edition identifier that is actually an [int]. It cannot distinguish Standard from
    # Web/BusinessIntelligence, or Enterprise from Developer/Evaluation (Microsoft's own enum
    # documentation folds those together), so GetEdition maps each EngineEdition value to the
    # closest SqlPowerDocSqlEdition member rather than claiming a precision the number does not
    # carry.
    $script:EditionMappings = @(
        @{ EditionId = 1; Expected = 'Unknown' } # Personal/Desktop Engine - retired before 2016
        @{ EditionId = 2; Expected = 'Standard' } # Standard, Web, Business Intelligence
        @{ EditionId = 3; Expected = 'Enterprise' } # Enterprise, Developer, Evaluation
        @{ EditionId = 4; Expected = 'Express' }
        @{ EditionId = 5; Expected = 'AzureSqlDatabase' } # Azure SQL Database
        @{ EditionId = 6; Expected = 'AzureSqlDatabase' } # Azure Synapse Analytics
        @{ EditionId = 8; Expected = 'AzureSqlDatabase' } # Azure SQL Managed Instance
        @{ EditionId = 9; Expected = 'AzureSqlDatabase' } # Azure SQL Edge
        @{ EditionId = 11; Expected = 'AzureSqlDatabase' } # Azure Synapse serverless / Fabric
        @{ EditionId = 0; Expected = 'Unknown' }
        @{ EditionId = 99; Expected = 'Unknown' } # no EngineEdition this old codebase knows about
    )
}

BeforeAll {
    $script:BuiltManifest = Join-Path $PSScriptRoot '..' '..' '..' 'output' 'SqlPowerDoc' '3.0.0' 'SqlPowerDoc.psd1'
    Import-Module -Name PSFramework -ErrorAction SilentlyContinue
    Import-Module -Name $script:BuiltManifest -Force -ErrorAction Stop
}

Describe 'SqlPowerDocVersion static version constants' -Tag 'Unit' {

    It 'maps <Label> to major version <Version>' -ForEach $script:SupportedVersions {
        InModuleScope SqlPowerDoc -Parameters @{ ExpectedVersion = $Version; ExpectedLabel = $Label } {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty -Because 'plan section 2.3 lists SqlPowerDocVersion in Classes/20-SqlPowerDocVersion.ps1'

            $propertyName = "SqlServer$ExpectedLabel"
            $constant = [SqlPowerDocVersion]::$propertyName

            $constant | Should -Not -BeNullOrEmpty -Because "the legacy module's `$SQLServer$ExpectedLabel constant (SqlServerDatabaseEngineInformation.psm1) must survive as a static field"
            $constant.Major | Should -Be $ExpectedVersion.Major
        }
    }

    It 'sets Minimum to the 2016 constant, the floor the legacy cascade never enforced' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::Minimum | Should -Be ([SqlPowerDocVersion]::SqlServer2016)
        }
    }

    It 'sets HighestTested to the 2022 constant, so newer servers have an explicit ceiling to clamp to' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::HighestTested | Should -Be ([SqlPowerDocVersion]::SqlServer2022)
        }
    }
}

Describe 'SqlPowerDocVersion.IsSupported' -Tag 'Unit' {

    It 'accepts SQL Server <Label> (major <Version>)' -ForEach $script:SupportedVersions {
        InModuleScope SqlPowerDoc -Parameters @{ TargetVersion = $Version } {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::IsSupported($TargetVersion) | Should -BeTrue
        }
    }

    It 'accepts a full four-part build number, because only Major decides support' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            # 13.0.1601.5 is the real SQL Server 2016 RTM build number.
            [SqlPowerDocVersion]::IsSupported([System.Version] '13.0.1601.5') | Should -BeTrue
        }
    }

    It 'rejects <Name> (major.minor <Version>)' -ForEach $script:UnsupportedVersions {
        InModuleScope SqlPowerDoc -Parameters @{ TargetVersion = $Version } {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::IsSupported($TargetVersion) | Should -BeFalse
        }
    }

    It 'accepts a version newer than the highest tested version, so 2025+ is not silently rejected' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::IsSupported([System.Version] '17.0') | Should -BeTrue
        }
    }

    It 'returns false, and does not throw, for a null version' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            { [SqlPowerDocVersion]::IsSupported($null) } | Should -Not -Throw
            [SqlPowerDocVersion]::IsSupported($null) | Should -BeFalse
        }
    }
}

Describe 'SqlPowerDocVersion.AssertSupported' -Tag 'Unit' {

    It 'does not throw for SQL Server <Label>' -ForEach $script:SupportedVersions {
        InModuleScope SqlPowerDoc -Parameters @{ TargetVersion = $Version } {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            { [SqlPowerDocVersion]::AssertSupported($TargetVersion) } | Should -Not -Throw
        }
    }

    It 'throws SqlPowerDocUnsupportedVersionException for <Name>' -ForEach $script:UnsupportedVersions {
        $exception = InModuleScope SqlPowerDoc -Parameters @{ TargetVersion = $Version } {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            try { [SqlPowerDocVersion]::AssertSupported($TargetVersion); $null }
            catch { $_.Exception }
        }

        $exception | Should -Not -BeNullOrEmpty
        $exception.GetType().Name | Should -Be 'SqlPowerDocUnsupportedVersionException'
        $exception.Message | Should -Match '2016'
    }

    It 'throws SqlPowerDocUnsupportedVersionException, not a NullReferenceException, for a null version' {
        $exception = InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            try { [SqlPowerDocVersion]::AssertSupported($null); $null }
            catch { $_.Exception }
        }

        $exception | Should -Not -BeNullOrEmpty
        $exception.GetType().Name | Should -Be 'SqlPowerDocUnsupportedVersionException'
    }

    It 'is caught by a catch block typed to SqlPowerDocException, matching every other wrapper' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            $caught = $null
            try { [SqlPowerDocVersion]::AssertSupported([System.Version] '11.0') }
            catch [SqlPowerDocException] { $caught = $_ }

            $caught | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'SqlPowerDocVersion.GetLabel' -Tag 'Unit' {

    It 'labels SQL Server <Label> as "SQL Server <Label>"' -ForEach $script:SupportedVersions {
        InModuleScope SqlPowerDoc -Parameters @{ TargetVersion = $Version; ExpectedLabel = $Label } {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::GetLabel($TargetVersion) | Should -Be "SQL Server $ExpectedLabel"
        }
    }

    It 'ignores build and revision, labelling a full build number the same as its bare major.minor' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::GetLabel([System.Version] '15.0.4003.23') | Should -Be 'SQL Server 2019'
        }
    }

    It 'labels an unsupported pre-2016 version as such, and still names the raw version' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            $label = [SqlPowerDocVersion]::GetLabel([System.Version] '11.0')

            $label | Should -Match 'unsupported'
            $label | Should -Match '11\.0'
        }
    }

    It 'labels a version newer than the highest tested version as such, without rejecting it' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            $label = [SqlPowerDocVersion]::GetLabel([System.Version] '17.0')

            $label | Should -Match 'newer than 2022'
        }
    }

    It 'returns a sensible label, and does not throw, for a null version' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            { [SqlPowerDocVersion]::GetLabel($null) } | Should -Not -Throw
            [SqlPowerDocVersion]::GetLabel($null) | Should -Match 'unknown'
        }
    }
}

Describe 'SqlPowerDocVersion.GetEdition' -Tag 'Unit' {

    It 'maps EngineEdition <EditionId> to SqlPowerDocSqlEdition.<Expected>' -ForEach $script:EditionMappings {
        InModuleScope SqlPowerDoc -Parameters @{ TargetEditionId = $EditionId; ExpectedEdition = $Expected } {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty
            ('SqlPowerDocSqlEdition' -as [type]) | Should -Not -BeNullOrEmpty -Because 'plan section 2.3 declares SqlPowerDocSqlEdition in Classes/00-Enums.ps1, ahead of the tier-2x version gate'

            [SqlPowerDocVersion]::GetEdition($TargetEditionId) | Should -Be ([SqlPowerDocSqlEdition] $ExpectedEdition)
        }
    }

    It 'returns a genuine SqlPowerDocSqlEdition value, not a bare int or string' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            [SqlPowerDocVersion]::GetEdition(3) | Should -BeOfType ([SqlPowerDocSqlEdition])
        }
    }

    It 'defaults negative and unrecognised IDs to Unknown instead of throwing' {
        InModuleScope SqlPowerDoc {
            ('SqlPowerDocVersion' -as [type]) | Should -Not -BeNullOrEmpty

            { [SqlPowerDocVersion]::GetEdition(-1) } | Should -Not -Throw
            [SqlPowerDocVersion]::GetEdition(-1) | Should -Be ([SqlPowerDocSqlEdition]::Unknown)
        }
    }
}
