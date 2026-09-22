# src/SqlPowerDoc/SqlPowerDoc.psm1 - DEVELOPMENT LOADER. Not shipped; the built module
# is a single generated .psm1 that contains all of these files inline.
#
# No `using` statements here: dot-sourced class files do not reliably see each other's
# types through `using`, and ModuleBuilder's Move-UsingStatement generator handles the
# built module. Ordering below must mirror build.psd1's SourceDirectories exactly.

$script:SqlPowerDocPlatform = $null

foreach ($directory in 'Classes', 'Private', 'Public') {
    $path = Join-Path $PSScriptRoot $directory
    if (-not (Test-Path $path)) { continue }

    # The invariant-culture sort matches ModuleBuilder's cross-platform sort; the default
    # culture-aware sort puts '10-' before '02-' on some locales.
    Get-ChildItem -Path $path -Filter '*.ps1' -File |
        Sort-Object -Property Name -Culture ([System.Globalization.CultureInfo]::InvariantCulture) |
        ForEach-Object { . $_.FullName }
}

# Work item A6 introduces Initialize-SqlPowerDocConfiguration (PSFramework configuration and
# logging setup). The guard keeps the skeleton importable until then and costs nothing after.
if (Get-Command -Name 'Initialize-SqlPowerDocConfiguration' -ErrorAction SilentlyContinue) {
    Initialize-SqlPowerDocConfiguration
}

$publicPath = Join-Path $PSScriptRoot 'Public'
$exported = @(
    if (Test-Path $publicPath) {
        Get-ChildItem -Path $publicPath -Filter '*.ps1' -File | Select-Object -ExpandProperty BaseName
    }
)

# An empty -Function list exports nothing, which is the correct state until work item A8
# adds the first public function.
Export-ModuleMember -Function $exported
