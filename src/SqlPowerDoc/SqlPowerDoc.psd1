#
# src/SqlPowerDoc/SqlPowerDoc.psd1 - the SOURCE manifest.
#
# ModuleBuilder copies this to output/ and overwrites exactly two keys: FunctionsToExport
# (from the Public/ filenames) and ModuleVersion (from the build). Everything below ships
# verbatim, including RequiredModules.
#
@{
    RootModule           = 'SqlPowerDoc.psm1'
    ModuleVersion        = '3.0.0'
    GUID                 = '3f657f63-a347-4e7e-bbb6-f8b88754181e'
    Author               = 'SQL Power Doc contributors'
    CompanyName          = 'SQL Power Doc'
    Copyright            = '(c) SQL Power Doc contributors. All rights reserved.'
    Description          = 'Discovers, documents, and diagnoses SQL Server instances and the Windows hosts that run them.'
    CompatiblePSEditions = @('Core')
    PowerShellVersion    = '7.4'

    # Runtime dependencies. Three, and only three.
    #
    # dbatools        - every SQL Server interaction. Brings dbatools.library transitively,
    #                   which supplies SMO and Microsoft.Data.SqlClient, so there is no
    #                   dependency on the excluded SQL Server PowerShell module and no
    #                   LoadWithPartialName bootstrap.
    # PSFramework     - all logging and configuration. Arrives as a dbatools NESTED module
    #                   anyway, and is declared explicitly regardless: relying on another
    #                   module's nested dependency is how a version floor silently moves.
    # ImportExcel     - all workbook output. Replaces every Excel COM instantiation.
    #
    # ModuleVersion here is a FLOOR, which is all a .psd1 can express. The reproducible
    # upper bound lives in build.requires.psd1, not here: pinning a ceiling in a shipped
    # manifest breaks consumers who legitimately run a newer dbatools.
    RequiredModules      = @(
        @{ ModuleName = 'dbatools'; ModuleVersion = '2.9.0' }
        @{ ModuleName = 'PSFramework'; ModuleVersion = '1.14.457' }
        @{ ModuleName = 'ImportExcel'; ModuleVersion = '7.8.10' }
    )

    # Deliberately empty. A nested module would defeat the monolithic-.psm1 requirement and
    # break `using module SqlPowerDoc` for class consumers.
    NestedModules        = @()

    RequiredAssemblies   = @()
    ScriptsToProcess     = @()
    TypesToProcess       = @()
    FormatsToProcess     = @()

    # '*' in the SOURCE manifest only. The dev-mode loader calls Export-ModuleMember, and a
    # manifest with an explicit or empty list filters that out, making every command appear
    # missing in dev mode. ModuleBuilder replaces this with the real list in the built
    # manifest.
    FunctionsToExport    = '*'
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('SQLServer', 'Inventory', 'Documentation', 'dbatools', 'Excel', 'Windows', 'CrossPlatform')
            LicenseUri   = 'https://github.com/thedwindlingdba/SQLPowerDoc/blob/master/LICENSE.txt'
            ProjectUri   = 'https://github.com/thedwindlingdba/SQLPowerDoc'
            ReleaseNotes = 'See CHANGELOG.md. v3.0.0 is a breaking release.'
            Prerelease   = ''
        }
    }
}
