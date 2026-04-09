# Synced from Modules/SqlServerDatabaseEngineInformation/SqlServerDatabaseEngineInformation.psm1
# (function Get-SqlServerVersionName). The full module manifest does not yet import cleanly on
# PowerShell 7+; this fixture keeps version-label tests runnable without SMO. Update both when
# changing the canonical implementation.

function Get-SqlServerVersionName {
    param([int]$MajorVersion, [int]$MinorVersion)
    if (($MajorVersion -eq 11) -and ($MinorVersion -eq 0)) { '2012' }
    elseif (($MajorVersion -eq 10) -and ($MinorVersion -eq 50)) { '2008 R2' }
    elseif (($MajorVersion -eq 10) -and ($MinorVersion -eq 0)) { '2008' }
    elseif (($MajorVersion -eq 9) -and ($MinorVersion -eq 0)) { '2005' }
    elseif (($MajorVersion -eq 8) -and ($MinorVersion -eq 0)) { '2000' }
    elseif (($MajorVersion -eq 7) -and ($MinorVersion -eq 0)) { '7.0' }
    elseif (($MajorVersion -eq 6) -and ($MinorVersion -eq 50)) { '6.5' }
    elseif (($MajorVersion -eq 6) -and ($MinorVersion -eq 0)) { '6.0' }
    else { 'unknown ' }
}
