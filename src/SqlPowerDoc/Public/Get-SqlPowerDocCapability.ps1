function Get-SqlPowerDocCapability {
    <#
        .SYNOPSIS
            Reports which SqlPowerDoc collection capabilities this control host can provide.

        .DESCRIPTION
            SqlPowerDoc collects from Windows hosts, but it does not have to run on one. Four of
            its six operating-system seams - CIM queries, remote registry reads, local security
            policy, and SQL service enumeration - need a Windows control host; TCP probes and DNS
            resolution do not, and Excel autosizing needs Windows because System.Drawing.Common
            does.

            This function reports one row per capability so a user can see what a run will and
            will not be able to collect before starting it, rather than discovering the gap fifty
            servers into an inventory.

        .PARAMETER Platform
            Platform abstraction override. Used by the test suite to inject a fake platform; not
            intended for interactive use.

        .PARAMETER EnableException
            Throw a terminating error instead of writing a warning when the capability report
            cannot be produced.

        .EXAMPLE
            PS C:\> Get-SqlPowerDocCapability

            Capability            Supported PlatformName
            ----------            --------- ------------
            CimQuery                   True Windows
            ...

            Reports every capability on the current host.

        .EXAMPLE
            PS C:\> Get-SqlPowerDocCapability | Where-Object { -not $_.Supported }

            Lists only what this host cannot collect.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [SqlPowerDocPlatform] $Platform,

        [switch] $EnableException
    )

    begin {
        $resolvedPlatform = if ($PSBoundParameters.ContainsKey('Platform')) { $Platform } else { Get-SqlPowerDocPlatform }
    }

    process {
        try {
            foreach ($capability in [enum]::GetValues([SqlPowerDocCapability])) {
                [PSCustomObject]@{
                    Capability   = $capability
                    Supported    = $resolvedPlatform.Supports($capability)
                    PlatformName = $resolvedPlatform.PlatformName
                }
            }
        }
        catch {
            Stop-PSFFunction -Message 'Failed to report platform capabilities.' -ErrorRecord $_ `
                -Target $resolvedPlatform.PlatformName -EnableException $EnableException
            return
        }
    }
}
