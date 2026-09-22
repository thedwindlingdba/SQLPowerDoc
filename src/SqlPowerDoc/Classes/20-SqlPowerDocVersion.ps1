#
# Version gate. Tier 2x: depends only on tier-0x exceptions/enums (plan section 2.3, section 3.3).
#
# Supported: SQL Server 2016, 2017, 2019, 2022 only. The legacy cascade's newest branch was 2012
# (SqlServerDatabaseEngineInformation.psm1 declared $SQLServer2016/2017/2019 constants near the
# top of the file, lines 24-26, but every version-gated feature check below them still compared
# against $SQLServer2008/$SQLServer2012), so a 2016-2022 server silently fell through to the 2012
# code path instead of being recognised. This class is a static helper - no SqlPowerDocBase, no
# instance state - so nothing here can be instantiated; every member is called on the type itself.
#
# Static fields, not a lookup built at call time, so [SqlPowerDocVersion]::SqlServer2019 reads the
# same as the legacy $SQLServer2019 constant it replaces.
#

class SqlPowerDocVersion {
    static [System.Version] $SqlServer2016 = [System.Version] '13.0'
    static [System.Version] $SqlServer2017 = [System.Version] '14.0'
    static [System.Version] $SqlServer2019 = [System.Version] '15.0'
    static [System.Version] $SqlServer2022 = [System.Version] '16.0'

    # The floor the legacy cascade never enforced, and the ceiling of what has actually been
    # tested. A version above HighestTested is still supported (Effective would clamp it for a
    # collector that needs one concrete branch to run), it is just unverified.
    static [System.Version] $Minimum = [SqlPowerDocVersion]::SqlServer2016
    static [System.Version] $HighestTested = [SqlPowerDocVersion]::SqlServer2022

    # Major version number -> the year label the legacy module's Get-SqlServerVersionName used
    # (SqlServerDatabaseEngineInformation.psm1, line 3944), restricted to the four majors this
    # gate still recognises.
    hidden static [hashtable] $LabelByMajor = @{
        13 = '2016'
        14 = '2017'
        15 = '2019'
        16 = '2022'
    }

    static [bool] IsSupported([System.Version] $Version) {
        if ($null -eq $Version) { return $false }

        # Anything at or above the highest tested major is accepted too: the legacy cascade's
        # newest branch was 2012, so every 2016+ server silently fell through to it, and the new
        # gate must not repeat that mistake against 2025 and later by rejecting what it has not
        # tested yet. GetLabel still marks that version 'unverified' so the distinction is not lost.
        return [SqlPowerDocVersion]::LabelByMajor.ContainsKey($Version.Major) -or
        $Version.Major -gt [SqlPowerDocVersion]::HighestTested.Major
    }

    static [void] AssertSupported([System.Version] $Version) {
        if ([SqlPowerDocVersion]::IsSupported($Version)) { return }

        throw [SqlPowerDocUnsupportedVersionException]::new(
            "$([SqlPowerDocVersion]::GetLabel($Version)) is not supported. " +
            'Supported versions: SQL Server 2016, 2017, 2019, 2022.')
    }

    static [string] GetLabel([System.Version] $Version) {
        if ($null -eq $Version) { return 'Unknown SQL Server version' }

        if ([SqlPowerDocVersion]::LabelByMajor.ContainsKey($Version.Major)) {
            return "SQL Server $([SqlPowerDocVersion]::LabelByMajor[$Version.Major])"
        }

        if ($Version.Major -gt [SqlPowerDocVersion]::HighestTested.Major) {
            return "SQL Server $Version (newer than 2022, unverified)"
        }

        return "SQL Server $Version (unsupported, pre-2016)"
    }

    # Maps SERVERPROPERTY('EngineEdition') / Server.EngineEdition (the only edition identifier
    # that is actually an [int]; Microsoft.SqlServer.Management.Common.DatabaseEngineEdition and
    # Microsoft.SqlServer.Management.Smo.Edition are its .NET names) to the closest
    # SqlPowerDocSqlEdition member. EngineEdition cannot itself distinguish Standard from
    # Web/BusinessIntelligence, or Enterprise from Developer/Evaluation - Microsoft's own
    # documentation folds each of those groups into one numeric value - so callers that need that
    # finer distinction still have to parse Server.Information.Edition; this mapping only carries
    # the precision the number actually has.
    static [SqlPowerDocSqlEdition] GetEdition([int] $EditionId) {
        switch ($EditionId) {
            1 { return [SqlPowerDocSqlEdition]::Unknown }              # Personal/Desktop Engine, retired before 2016
            2 { return [SqlPowerDocSqlEdition]::Standard }             # Standard, Web, Business Intelligence
            3 { return [SqlPowerDocSqlEdition]::Enterprise }           # Enterprise, Developer, Evaluation
            4 { return [SqlPowerDocSqlEdition]::Express }              # Express, Express with Tools/Advanced Services
            5 { return [SqlPowerDocSqlEdition]::AzureSqlDatabase }     # Azure SQL Database
            6 { return [SqlPowerDocSqlEdition]::AzureSqlDatabase }     # Azure Synapse Analytics
            8 { return [SqlPowerDocSqlEdition]::AzureSqlDatabase }     # Azure SQL Managed Instance
            9 { return [SqlPowerDocSqlEdition]::AzureSqlDatabase }     # Azure SQL Edge
            11 { return [SqlPowerDocSqlEdition]::AzureSqlDatabase }    # Azure Synapse serverless / Microsoft Fabric
            12 { return [SqlPowerDocSqlEdition]::AzureSqlDatabase }    # Microsoft Fabric SQL database
            default { return [SqlPowerDocSqlEdition]::Unknown }
        }
        return [SqlPowerDocSqlEdition]::Unknown
    }
}
