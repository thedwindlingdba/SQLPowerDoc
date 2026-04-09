#Requires -Version 5.1
<#
.SYNOPSIS
    Runs all Pester tests under tests/ with CI-friendly exit codes.
.DESCRIPTION
    From repo root: pwsh -File tests/Run-AllTests.ps1
    Prepends ./Modules to PSModulePath so modules resolve like production scripts.
#>
param()
$ErrorActionPreference = 'Stop'
$testsRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $testsRoot

$pesterCandidates = Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version.Major -ge 5 } | Sort-Object Version -Descending
if (-not $pesterCandidates) {
    Write-Error @'
Pester 5+ is required. Install with:
  Install-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.999999 -Scope CurrentUser -Force
'@
}

Import-Module -Name Pester -MinimumVersion 5.0.0 -MaximumVersion 5.999999 -Force

$modulesPath = Join-Path $repoRoot 'Modules'
$sep = [IO.Path]::PathSeparator
if ($env:PSModulePath -notlike "*$modulesPath*") {
    $env:PSModulePath = "${modulesPath}${sep}${env:PSModulePath}"
}

$config = New-PesterConfiguration
$config.Run.Path = $testsRoot
$config.Run.TestExtension = '.test.ps1'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Normal'

Invoke-Pester -Configuration $config
