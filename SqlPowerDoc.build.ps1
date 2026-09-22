#Requires -Version 7.4
<#
    InvokeBuild task file for the SqlPowerDoc module.

        Invoke-Build            # default: Clean, Build, Lint, Test
        Invoke-Build Build
        Invoke-Build Package
        Invoke-Build ?          # list tasks

    Build comes before Lint and Test on purpose. Both run against the assembled module in
    output/, never against the loose source files:

      * PSScriptAnalyzer reports TypeNotFound on every individual class file, because a
        derived class references a type declared in a file that is not loaded when that file
        is analysed alone. Analysing the concatenated output resolves every type.
      * The built .psm1 is what ships, so testing it is the only way a concatenation bug
        (wrong file order, an unhoisted `using` statement) can fail a test rather than ship.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExcludeTag',
    Justification = 'Consumed inside the Test task script block, which PSScriptAnalyzer does not follow.')]
param(
    [string] $ModuleName = 'SqlPowerDoc',
    [string] $SourcePath = (Join-Path $PSScriptRoot 'src' 'SqlPowerDoc'),
    [string] $OutputDirectory = (Join-Path $PSScriptRoot 'output'),
    [string[]] $ExcludeTag
)

Set-StrictMode -Version Latest

$script:ModuleVersion = (Import-PowerShellDataFile -Path (Join-Path $SourcePath "$ModuleName.psd1")).ModuleVersion
$script:BuiltModuleDirectory = Join-Path $OutputDirectory $ModuleName $script:ModuleVersion
$script:TestResultDirectory = Join-Path $OutputDirectory 'testresults'
$script:PackageDirectory = Join-Path $PSScriptRoot 'dist'

# Synopsis: Remove build output.
task Clean {
    foreach ($path in $OutputDirectory, $script:PackageDirectory) {
        if (Test-Path -Path $path) {
            Remove-Item -Path $path -Recurse -Force
            Write-Build DarkGray "Removed $path"
        }
    }
}

# Synopsis: Assemble the monolithic .psm1 from src/ with ModuleBuilder.
task Build {
    Import-Module -Name ModuleBuilder -ErrorAction Stop

    $built = Build-Module -SourcePath (Join-Path $SourcePath 'build.psd1') -OutputDirectory $OutputDirectory -Passthru

    # RootModule on the returned module info is relative to ModuleBase, not to the caller.
    $rootModule = Join-Path $built.ModuleBase $built.RootModule
    $regions = @(Select-String -Path $rootModule -Pattern '^#Region' -AllMatches)

    # With no source files to combine, ModuleBuilder leaves the copied dev-mode loader in
    # place as the root module. That is only true of the empty skeleton, and it stops being
    # true with the first file work item A4 adds, but shipping a loader that dot-sources
    # directories which are not in the package would be silent breakage, so say so.
    if ($regions.Count -eq 0) {
        Write-Build Yellow ('{0} has no source files yet; the built root module is the dev-mode loader.' -f $SourcePath)
    }

    Write-Build Green ('Built {0} {1} from {2} source file(s): {3}' -f
        $built.Name, $built.Version, $regions.Count, $rootModule)
}

# Synopsis: Run PSScriptAnalyzer against the built module.
task Lint Build, {
    # Import every runtime dependency BEFORE Invoke-ScriptAnalyzer. PSScriptAnalyzer resolves
    # commands on a worker thread; letting it auto-load PSFramework there deadlocks roughly
    # half the time because PSFramework starts a background runspace at import.
    Import-Module -Name PSFramework -ErrorAction Stop
    Import-Module -Name PSScriptAnalyzer -ErrorAction Stop

    # Written as a splat because work items A10 and D1 each add a CustomRulePath entry. When
    # they do they must also set IncludeDefaultRules: passing -CustomRulePath alone silently
    # switches the default rule set off, which would turn this gate green on everything
    # PSScriptAnalyzer normally catches.
    $analyzerParameters = @{
        Path        = $script:BuiltModuleDirectory
        Recurse     = $true
        ExcludeRule = @('PSAvoidUsingWriteHost', 'PSUseShouldProcessForStateChangingFunctions')
    }

    # ModuleBuilder rewrites FunctionsToExport from the Public/ filenames, so the built
    # manifest carries an explicit list as soon as one public function exists. Until then it
    # inherits the source manifest's '*' - which the source manifest needs, or the dev-mode
    # loader's Export-ModuleMember is filtered out. This exclusion therefore disappears by
    # itself with the first public function; it is not a standing waiver.
    if (-not (Get-ChildItem -Path (Join-Path $SourcePath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
        $analyzerParameters.ExcludeRule += 'PSUseToExportFieldsInManifest'
        Write-Build DarkGray 'No public functions yet: PSUseToExportFieldsInManifest excluded for this run.'
    }

    # PSScriptAnalyzer itself is intermittently unstable here: it resolves commands on worker
    # threads and occasionally throws a NullReferenceException out of its own command cache
    # rather than returning findings. Measured on this VM at roughly one run in fifteen, and
    # never reproducible twice in a row. One retry converts that into a slower run instead of
    # a red build; a second failure is reported, because a reproducible throw is a real defect
    # and must not be swallowed.
    $findings = $null
    foreach ($attempt in 1, 2) {
        try {
            $findings = @(
                Invoke-ScriptAnalyzer @analyzerParameters | Where-Object { $_.Severity -in @('Error', 'Warning') }
            )
            break
        }
        catch {
            if ($attempt -eq 2) { throw }
            Write-Build Yellow ('PSScriptAnalyzer threw ({0}); retrying once.' -f $_.Exception.GetType().Name)
        }
    }

    if ($findings.Count -gt 0) {
        $findings |
            Format-Table -Property RuleName, Severity, ScriptName, Line, Message -AutoSize |
            Out-String |
            Write-Build Yellow
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s)."
    }

    Write-Build Green 'Lint clean.'
}

# Synopsis: Run the Pester suite against the built module.
task Test Build, {
    Import-Module -Name Pester -MinimumVersion '5.5.0' -ErrorAction Stop

    if (-not (Test-Path -Path $script:TestResultDirectory)) {
        $null = New-Item -Path $script:TestResultDirectory -ItemType Directory -Force
    }

    $configuration = & (Join-Path $PSScriptRoot 'tests' 'PesterConfiguration.ps1') -ExcludeTag $ExcludeTag
    Invoke-Pester -Configuration $configuration
}

# Synopsis: Zip the built module into dist/.
task Package Build, {
    if (-not (Test-Path -Path $script:PackageDirectory)) {
        $null = New-Item -Path $script:PackageDirectory -ItemType Directory -Force
    }

    $archive = Join-Path $script:PackageDirectory ('{0}-{1}.zip' -f $ModuleName, $script:ModuleVersion)
    Compress-Archive -Path (Join-Path $script:BuiltModuleDirectory '*') -DestinationPath $archive -Force

    Write-Build Green "Packaged $archive"
}

# Synopsis: Default - the gate a change has to pass before it is reviewable.
task . Clean, Build, Lint, Test
