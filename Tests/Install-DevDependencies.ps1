#Requires -Version 7.0
<#
    .SYNOPSIS
        Installs the development/test toolchain declared in Tests/RequiredModules.psd1.

    .DESCRIPTION
        Idempotent: modules already present at or above the declared minimum version
        are left alone. Safe to run on every CI job and on developer workstations.

    .PARAMETER Scope
        Install scope passed to Install-Module. Defaults to CurrentUser.

    .PARAMETER Force
        Reinstall even when an acceptable version is already present.

    .EXAMPLE
        pwsh -NoProfile -File ./Tests/Install-DevDependencies.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$required = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'RequiredModules.psd1')

foreach ($name in $required.Keys | Sort-Object) {
    $minimum = [version]$required[$name]
    $present = Get-Module -ListAvailable -Name $name |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $Force -and $present -and $present.Version -ge $minimum) {
        Write-Host ('[skip]    {0,-18} {1} already satisfies >= {2}' -f $name, $present.Version, $minimum)
        continue
    }

    Write-Host ('[install] {0,-18} need >= {1} (have {2})' -f $name, $minimum, ($present.Version ?? 'none'))

    $splat = @{
        Name            = $name
        MinimumVersion  = $minimum
        Scope           = $Scope
        Force           = $true
        ErrorAction     = 'Stop'
    }
    # Pester ships with a different publisher certificate than the bundled 3.x.
    if ($name -eq 'Pester')    { $splat['SkipPublisherCheck'] = $true }
    # SqlServer collides with SQLPS command names where both are present.
    if ($name -eq 'SqlServer') { $splat['AllowClobber'] = $true }

    Install-Module @splat

    $installed = Get-Module -ListAvailable -Name $name |
        Sort-Object Version -Descending | Select-Object -First 1
    Write-Host ('[ok]      {0,-18} {1}' -f $name, $installed.Version)
}

Write-Host ''
Write-Host 'Toolchain ready:'
foreach ($name in $required.Keys | Sort-Object) {
    $m = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending | Select-Object -First 1
    Write-Host ('  {0,-18} {1}' -f $name, ($m.Version ?? 'MISSING'))
}
