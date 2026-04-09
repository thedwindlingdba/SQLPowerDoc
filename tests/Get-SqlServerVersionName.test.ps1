BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'tests\fixtures\Get-SqlServerVersionName.ps1')
}

Describe 'Get-SqlServerVersionName (fixture; see tests/fixtures header)' {
    It 'maps SQL Server 2012 build numbers' {
        Get-SqlServerVersionName -MajorVersion 11 -MinorVersion 0 | Should -Be '2012'
    }

    It 'returns unknown label for unrecognized versions' {
        Get-SqlServerVersionName -MajorVersion 99 -MinorVersion 99 | Should -Be 'unknown '
    }
}
