@{
    # Development/test toolchain for the SQL Power Doc modernization effort.
    # Consumed by Tests/Install-DevDependencies.ps1.
    #
    # Pester is pinned to a 5.x floor deliberately: the gallery default is now 6.x,
    # and the test suites use Pester 5 idioms (BeforeDiscovery, Mock -ModuleName,
    # Should -Invoke -Scope). Both 5.7.1+ and 6.x have been verified to run them.

    Pester            = '5.7.1'
    PSScriptAnalyzer  = '1.25.0'
    ImportExcel       = '7.8.10'

    # Supplies both SMO (Microsoft.SqlServer.Smo) and Microsoft.Data.SqlClient.
    # Required by SqlServerDatabaseEngineInformation once the deprecated
    # LoadWithPartialName bootstrap is replaced.
    SqlServer         = '22.0'
}
