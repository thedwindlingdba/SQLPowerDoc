# src/SqlPowerDoc/Private/Initialize-SqlPowerDocConfiguration.ps1 - work item A6.
#
# Declares every PSFramework configuration key SqlPowerDoc reads (plan section 3.12) and wires
# up the `logfile` logging provider that replaces the deleted LogHelper module's Set-LogFile.
#
# Called once from the dev-mode loader (SqlPowerDoc.psm1) and once from Suffix.ps1 in the built
# module. `-Initialize` is idempotent across repeated imports and replays any override a caller
# set on these keys before this function first ran, so re-running it (e.g. multiple
# `Import-Module -Force` cycles during development, or repeated Pester runs in one session)
# never clobbers a value someone already configured.
function Initialize-SqlPowerDocConfiguration {
    [CmdletBinding()]
    param ()

    # Excel colour theme names ImportExcel/Excel ship out of the box. Registered once; safe to
    # call on every import because Register-PSFConfigValidation simply overwrites the named
    # validator with the same scriptblock.
    Register-PSFConfigValidation -Name 'SqlPowerDoc.ExportColorTheme' -ScriptBlock {
        param ($Value)

        $result = [PSCustomObject]@{ Message = ''; Value = $Value; Success = $true }
        $validThemes = @(
            'Office', 'Grayscale', 'Blue', 'Blue Green', 'Blue Warm', 'Green', 'Green Yellow',
            'Marquee', 'Median', 'Orange', 'Orange Red', 'Paper', 'Red', 'Red Orange',
            'Red Violet', 'Slice', 'Violet', 'Violet II', 'Yellow', 'Yellow Orange'
        )
        if ($Value -notin $validThemes) {
            $result.Message = "'$Value' is not a recognised Excel colour theme."
            $result.Success = $false
        }
        return $result
    }

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Sql.ConnectTimeoutSeconds' -Value 15 -Initialize `
        -Validation 'integer' `
        -Description 'SMO/ADO connection timeout, in seconds, when reaching a target SQL Server instance.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Sql.QueryTimeoutSeconds' -Value 600 -Initialize `
        -Validation 'integer' `
        -Description 'SMO/ADO command timeout, in seconds, for collection queries.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Sql.MinimumVersion' -Value '13.0' -Initialize `
        -Validation 'string' `
        -Description 'Lowest SQL Server major.minor version SqlPowerDoc supports collecting from.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Discovery.MaxParallelHosts' -Value 10 -Initialize `
        -Validation 'integer' `
        -Description 'Maximum number of hosts to inventory concurrently.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Discovery.TcpTimeoutMilliseconds' -Value 1000 -Initialize `
        -Validation 'integer' `
        -Description 'Timeout, in milliseconds, for TCP reachability probes during discovery.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Discovery.SqlBrowserPort' -Value 1434 -Initialize `
        -Validation 'integer' `
        -Description 'UDP port used to query the SQL Server Browser service during discovery.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Cim.OperationTimeoutSeconds' -Value 60 -Initialize `
        -Validation 'integer' `
        -Description 'Timeout, in seconds, for CIM/WMI operations against a target host.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Collection.IncludeSystemObjects' -Value $false -Initialize `
        -Validation 'bool' `
        -Description 'Include system databases and objects in collection results.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Collection.IncludeDatabaseObjectPermissions' -Value $false -Initialize `
        -Validation 'bool' `
        -Description 'Include per-object database permissions in collection results.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Export.DefaultTableStyle' -Value 'Medium15' -Initialize `
        -Validation 'string' `
        -Description 'Default ImportExcel table style applied to exported worksheets.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Export.DefaultColumnWidth' -Value 18 -Initialize `
        -Validation 'integer' `
        -Description 'Default column width, in characters, applied to exported worksheets.'

    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Export.ColorTheme' -Value 'Office' -Initialize `
        -Validation 'SqlPowerDoc.ExportColorTheme' `
        -Description 'Excel colour theme applied to exported workbooks.'

    # <CommonApplicationData>/SqlPowerDoc/Logs (plan section 3.12). On Windows this resolves
    # under %ProgramData%; on Linux/macOS, .NET maps CommonApplicationData to /usr/share, which
    # this function does not assume is writable - Set-PSFLoggingProvider's background logging
    # runspace tolerates an unwritable path (it drops the write and keeps running rather than
    # throwing here), and a caller who needs a writable default on such a host overrides
    # SqlPowerDoc.Logging.Path before or after import like any other setting.
    $defaultLogDirectory = Join-Path ([System.Environment]::GetFolderPath('CommonApplicationData')) 'SqlPowerDoc' 'Logs'
    Set-PSFConfig -Module 'SqlPowerDoc' -Name 'Logging.Path' -Value $defaultLogDirectory -Initialize `
        -Validation 'string' `
        -Description 'Directory where SqlPowerDoc writes its rotated log files.'

    $logDirectory = Get-PSFConfigValue -FullName 'SqlPowerDoc.Logging.Path' -Fallback $defaultLogDirectory
    Set-PSFLoggingProvider -Name 'logfile' -InstanceName 'SqlPowerDoc' `
        -FilePath (Join-Path $logDirectory 'SqlPowerDoc-%Date%.log') -Enabled $true -Wait

    Write-PSFMessage -Level Verbose -Message 'SqlPowerDoc configuration and logging initialised.' `
        -ModuleName 'SqlPowerDoc' -FunctionName 'Initialize-SqlPowerDocConfiguration'
}
