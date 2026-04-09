BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'tests\fixtures\Get-SqlServerVersionName.ps1')
}

Describe 'Get-SqlServerVersionName (fixture; see tests/fixtures header)' {
    It 'maps SQL Server 2012 build numbers' {
        Get-SqlServerVersionName -MajorVersion 11 -MinorVersion 0 | Should -Be '2012'
    }

    It 'maps SQL Server 2022 and 2025 RTM build numbers' {
        Get-SqlServerVersionName -MajorVersion 16 -MinorVersion 0 | Should -Be '2022'
        Get-SqlServerVersionName -MajorVersion 17 -MinorVersion 0 | Should -Be '2025'
    }

    It 'maps SQL Server 2014 through 2019 RTM build numbers' {
        Get-SqlServerVersionName -MajorVersion 12 -MinorVersion 0 | Should -Be '2014'
        Get-SqlServerVersionName -MajorVersion 13 -MinorVersion 0 | Should -Be '2016'
        Get-SqlServerVersionName -MajorVersion 14 -MinorVersion 0 | Should -Be '2017'
        Get-SqlServerVersionName -MajorVersion 15 -MinorVersion 0 | Should -Be '2019'
    }

    It 'returns unknown label for unrecognized versions' {
        Get-SqlServerVersionName -MajorVersion 99 -MinorVersion 99 | Should -Be 'unknown '
    }
}
