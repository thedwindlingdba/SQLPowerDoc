# src/SqlPowerDoc/Private/Get-SqlPowerDocPlatform.ps1 - work item A8.
#
# The module-wide SqlPowerDocPlatform singleton (plan section 3.2). Operating-system detection
# happens once per import rather than once per collector, and every public function that reaches
# the OS resolves its platform through here unless the caller injected one with -Platform.
function Get-SqlPowerDocPlatform {
    [CmdletBinding()]
    [OutputType([SqlPowerDocPlatform])]
    param ()

    # Read through Get-Variable rather than $script:SqlPowerDocPlatform directly: the dev-mode
    # loader declares the variable, the built module has no prefix file to declare it in, and a
    # bare reference to an undeclared variable is a terminating error under Set-StrictMode.
    $existing = Get-Variable -Name 'SqlPowerDocPlatform' -Scope 'Script' -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $existing) { return $existing }

    $platform = [SqlPowerDocPlatform]::new()
    Set-Variable -Name 'SqlPowerDocPlatform' -Scope 'Script' -Value $platform

    return $platform
}
