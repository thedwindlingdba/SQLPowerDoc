#Requires -Version 7.4
<#
    .SYNOPSIS
        Asserts the toolchain and legacy-codebase facts the Phase 2 plan was built on.

    .DESCRIPTION
        Two groups of checks, both measured rather than assumed:

          Toolchain - PowerShell is at or above the 7.4 floor, and every dependency pinned in
                      build.requires.psd1 is installed at a version inside its pin.

          Legacy    - the function counts and live Get-WmiObject call count the plan quotes are
                      still true of the tree. Both are derived from an encoding-aware read
                      (NetShell.psm1 is UTF-16 BE and RDS-Manager.psm1 is UTF-16 LE, so
                      Get-Content and ripgrep both undercount them) followed by an AST walk.
                      Commented-out calls never enter the AST, so the WMI count is live calls
                      only.

        Exits 0 when every check passes, 1 otherwise.

    .EXAMPLE
        pwsh -NoProfile -File ./Tests/Phase0-Verification/Verify-Toolchain.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Write-Check {
    param([bool] $Ok, [string] $Label, [string] $Detail)

    $status = if ($Ok) { '[ ok ]' } else { '[fail]' }
    $colour = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ('{0} {1,-52} {2}' -f $status, $Label, $Detail) -ForegroundColor $colour

    if (-not $Ok) { $script:failures.Add(('{0}: {1}' -f $Label, $Detail)) }
}

function Test-VersionInPin {
    param([version] $Version, [string] $Pin)

    # Exact pin ('5.14.23') or NuGet-style range ('[5.5.0,7.0)').
    if ($Pin -notmatch '^[\[(]') { return $Version -ge [version]($Pin -replace '-.*$') }

    $open = $Pin[0]
    $close = $Pin[-1]
    $bounds = $Pin.Substring(1, $Pin.Length - 2).Split(',')
    $lower = [version]$bounds[0]
    $upper = if ($bounds[1]) { [version]$bounds[1] } else { $null }

    $lowerOk = if ($open -eq '[') { $Version -ge $lower } else { $Version -gt $lower }
    $upperOk = if (-not $upper) { $true } elseif ($close -eq ']') { $Version -le $upper } else { $Version -lt $upper }

    $lowerOk -and $upperOk
}

function Get-DecodedContent {
    param([string] $Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Get-FileAst {
    param([string] $Path)

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseInput(
        (Get-DecodedContent -Path $Path), [ref] $tokens, [ref] $errors)
}

Write-Host ''
Write-Host 'Toolchain' -ForegroundColor Cyan

Write-Check -Ok ($PSVersionTable.PSVersion -ge [version]'7.4') `
    -Label 'PowerShell >= 7.4' -Detail $PSVersionTable.PSVersion

$requiresPath = Join-Path $repositoryRoot 'build.requires.psd1'
Write-Check -Ok (Test-Path -Path $requiresPath) -Label 'build.requires.psd1 present' -Detail $requiresPath

if (Test-Path -Path $requiresPath) {
    $required = Import-PowerShellDataFile -Path $requiresPath

    foreach ($name in $required.Keys | Sort-Object) {
        $pin = $required[$name].version
        $installed = Get-Module -ListAvailable -Name $name |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if (-not $installed) {
            Write-Check -Ok $false -Label $name -Detail "not installed (pin $pin)"
            continue
        }

        $ok = Test-VersionInPin -Version $installed.Version -Pin $pin
        Write-Check -Ok $ok -Label $name -Detail ('{0} (pin {1})' -f $installed.Version, $pin)
    }
}

Write-Host ''
Write-Host 'Legacy codebase' -ForegroundColor Cyan

$expectedFunctionCounts = [ordered]@{
    'LogHelper'                          = 6
    'NetShell'                           = 27
    'NetworkScan'                        = 9
    'RDS-Manager'                        = 25
    'SqlServerDatabaseEngineInformation' = 141
    'SqlServerInventory'                 = 22
    'WindowsInventory'                   = 9
    'WindowsMachineInformation'          = 55
}

$totalFunctions = 0
foreach ($module in $expectedFunctionCounts.Keys) {
    $path = Join-Path $repositoryRoot 'Modules' $module "$module.psm1"
    if (-not (Test-Path -Path $path)) {
        Write-Check -Ok $false -Label "Modules/$module" -Detail 'missing'
        continue
    }

    $ast = Get-FileAst -Path $path
    $count = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count
    $totalFunctions += $count

    Write-Check -Ok ($count -eq $expectedFunctionCounts[$module]) `
        -Label "$module functions" -Detail ('{0} (expected {1})' -f $count, $expectedFunctionCounts[$module])
}

Write-Check -Ok ($totalFunctions -eq 294) -Label 'legacy function total' -Detail ('{0} (expected 294)' -f $totalFunctions)

$wmiCalls = 0
$legacyFiles = @(
    Get-ChildItem -Path (Join-Path $repositoryRoot 'Modules') -Filter '*.psm1' -Recurse -File
    Get-ChildItem -Path $repositoryRoot -Filter '*.ps1' -File
    Get-ChildItem -Path (Join-Path $repositoryRoot 'Tools') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
)

foreach ($file in $legacyFiles) {
    $ast = Get-FileAst -Path $file.FullName
    $wmiCalls += @(
        $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Get-WmiObject'
            }, $true)
    ).Count
}

Write-Check -Ok ($wmiCalls -eq 71) -Label 'live Get-WmiObject call sites' -Detail ('{0} (expected 71)' -f $wmiCalls)

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host ('{0} check(s) failed:' -f $failures.Count) -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'All checks passed.' -ForegroundColor Green
exit 0
