#Requires -Version 7.4
<#
    .SYNOPSIS
        Shared Pester 5.x configuration for the SqlPowerDoc suite.

    .DESCRIPTION
        Consumed by the Test task in SqlPowerDoc.build.ps1 and usable directly:

            Invoke-Pester -Configuration (& ./tests/PesterConfiguration.ps1)

        Tag exclusion is computed from the host, not hard-coded, so one configuration file
        serves the Linux leg, the Windows leg, and the self-hosted SQL leg with no branching
        in CI YAML. The tag taxonomy is Unit, RequiresWindows, RequiresSql,
        RequiresExcelRoundTrip, and Golden.

    .PARAMETER Path
        Test paths. Defaults to tests/unit and tests/integration.

    .PARAMETER ExcludeTag
        Additional tags to exclude on top of the ones derived from the host.
#>
[CmdletBinding()]
param(
    [string[]] $Path = @("$PSScriptRoot/unit", "$PSScriptRoot/integration"),
    [string[]] $ExcludeTag
)

Set-StrictMode -Version Latest

$exclude = [System.Collections.Generic.List[string]]::new()

if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows)) {
    $exclude.Add('RequiresWindows')
}
if (-not $env:SQLPOWERDOC_TEST_INSTANCE) {
    $exclude.Add('RequiresSql')
}
if ($ExcludeTag) {
    $exclude.AddRange([string[]] $ExcludeTag)
}

$outputRoot = Join-Path $PSScriptRoot '..' 'output' 'testresults'
$builtModule = Join-Path $PSScriptRoot '..' 'output' 'SqlPowerDoc' '3.0.0' 'SqlPowerDoc.psm1'

$configuration = New-PesterConfiguration
$configuration.Run.Path = @($Path | Where-Object { Test-Path -Path $_ })
$configuration.Run.Throw = $true      # so InvokeBuild's Test task fails the build
$configuration.Filter.ExcludeTag = $exclude.ToArray()
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputFormat = 'NUnitXml'
$configuration.TestResult.OutputPath = Join-Path $outputRoot 'pester.xml'

# Coverage is measured against the BUILT module, never the source files: the built .psm1 is
# what ships, and it is the only artifact where every class type resolves. It is skipped when
# no build output is present so the suite still runs standalone.
if (Test-Path -Path $builtModule) {
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.OutputFormat = 'JaCoCo'
    $configuration.CodeCoverage.OutputPath = Join-Path $outputRoot 'coverage.xml'
    $configuration.CodeCoverage.Path = $builtModule
    $configuration.CodeCoverage.CoveragePercentTarget = 75
}

$configuration
