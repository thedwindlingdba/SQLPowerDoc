#Requires -Version 7.4
<#
    .SYNOPSIS
        Installs every pinned development and runtime dependency declared in build.requires.psd1.

    .DESCRIPTION
        Installs each pin with PSResourceGet, always passing -Prerelease. PSResourceGet is the
        only installer permitted here; the retired PowerShellGet cmdlets are not used anywhere
        in the repository. -Prerelease widens the candidate set without overriding a pin, so
        the versions in build.requires.psd1 still decide what lands.

        This installs resource by resource rather than through one
        -RequiredResourceFile call, because the two cannot be combined: in
        Microsoft.PowerShell.PSResourceGet 1.2.0, -Prerelease belongs to NameParameterSet and
        -RequiredResourceFile to RequiredResourceFileParameterSet, so the combined command
        fails with "Parameter set cannot be resolved using the specified named parameters."
        The manifest stays the single source of truth either way - it is read here and each
        entry is installed by name, version, and repository.

        After installing, the script reports what actually resolved. -RecordPath writes that
        same list to disk so a CI run records the exact versions it built against; without it,
        a green build against a prerelease that later disappears from the gallery is not
        reproducible.

    .PARAMETER RequiredResourceFile
        Path to the pinned dependency manifest. Defaults to build.requires.psd1 at the
        repository root.

    .PARAMETER Scope
        Install scope. Defaults to CurrentUser, matching this project's CI.

    .PARAMETER RecordPath
        Optional path for a CLIXML record of the resolved versions.

    .EXAMPLE
        pwsh -NoProfile -File ./build/Install-DevDependencies.ps1

    .EXAMPLE
        pwsh -NoProfile -File ./build/Install-DevDependencies.ps1 -RecordPath ./output/resolved-dependencies.clixml
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string] $RequiredResourceFile = (Join-Path $PSScriptRoot '..' 'build.requires.psd1'),

    [ValidateSet('CurrentUser', 'AllUsers')]
    [string] $Scope = 'CurrentUser',

    [string] $RecordPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RequiredResourceFile = (Resolve-Path -Path $RequiredResourceFile).Path
$required = Import-PowerShellDataFile -Path $RequiredResourceFile

Write-Host ('Installing {0} pinned dependencies from {1}' -f $required.Count, $RequiredResourceFile)

foreach ($name in $required.Keys | Sort-Object) {
    $pin = $required[$name]

    $installParameters = @{
        Name            = $name
        Version         = $pin.version
        Scope           = $Scope
        TrustRepository = $true
        Prerelease      = $true
        ErrorAction     = 'Stop'
    }
    if ($pin.repository) { $installParameters['Repository'] = $pin.repository }

    Write-Host ('  {0,-20} {1}' -f $name, $pin.version)
    Install-PSResource @installParameters
}

$resolved = foreach ($name in $required.Keys | Sort-Object) {
    $installed = Get-InstalledPSResource -Name $name -ErrorAction SilentlyContinue |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    [pscustomobject]@{
        Name       = $name
        Requested  = $required[$name].version
        Version    = $installed.Version
        Prerelease = $installed.Prerelease
    }
}

$resolved | Format-Table -AutoSize | Out-String | Write-Host

$missing = @($resolved | Where-Object { -not $_.Version })
if ($missing.Count -gt 0) {
    throw ('Unresolved dependencies: {0}' -f ($missing.Name -join ', '))
}

if ($RecordPath) {
    $recordDirectory = Split-Path -Path $RecordPath -Parent
    if ($recordDirectory -and -not (Test-Path -Path $recordDirectory)) {
        $null = New-Item -Path $recordDirectory -ItemType Directory -Force
    }
    $resolved | Export-Clixml -Path $RecordPath
    Write-Host ('Resolved versions recorded at {0}' -f $RecordPath)
}
