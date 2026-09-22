#
# Tier 1x: the root of the class hierarchy. Everything that logs or reads configuration derives
# from this (plan sections 2.3 and 3.1).
#
# Two rules this class exists to enforce:
#
#   * Classes never call Stop-PSFFunction. It needs a real advanced-function $PSCmdlet for its
#     ThrowTerminatingError path, which a class method does not have. Classes throw; the wrapper
#     function translates.
#   * Write-PSFMessage is always given -ModuleName and -FunctionName. PSFramework infers both from
#     the call stack, and when the caller is a class method that inference resolves to '<Unknown>'.
#
# [NoRunspaceAffinity()] would let bare Write-PSFMessage work without -PSCmdlet, but it changes
# class semantics invisibly, does not help Stop-PSFFunction, and would leave two logging idioms in
# the codebase. One explicit pattern is worth the extra parameter.
#

class SqlPowerDocBase {
    # The wrapper function's $PSCmdlet, when there is one. Passing it to Write-PSFMessage is what
    # keeps the caller's -Verbose and -Debug preferences working from inside a class method.
    hidden [System.Management.Automation.PSCmdlet] $Cmdlet

    SqlPowerDocBase() { }

    SqlPowerDocBase([System.Management.Automation.PSCmdlet] $Cmdlet) {
        $this.Cmdlet = $Cmdlet
    }

    hidden [void] Log([string] $Level, [string] $Message) {
        $this.Log($Level, $Message, $null, @())
    }

    hidden [void] Log([string] $Level, [string] $Message, [object] $Target, [string[]] $Tag) {
        $parameters = @{
            Level        = $Level
            Message      = $Message
            ModuleName   = 'SqlPowerDoc'
            FunctionName = $this.GetType().Name
        }

        if ($null -ne $Target) { $parameters['Target'] = $Target }
        if ($null -ne $Tag -and $Tag.Count -gt 0) { $parameters['Tag'] = $Tag }

        if ($null -ne $this.Cmdlet) {
            $parameters['PSCmdlet'] = $this.Cmdlet

            # MyCommand is null once the invocation that produced the PSCmdlet has returned, which
            # is the normal state for an object that outlives its wrapper. Attributing those lines
            # to the class beats attributing them to nothing.
            $caller = $this.Cmdlet.MyInvocation.MyCommand.Name
            if (-not [string]::IsNullOrEmpty($caller)) { $parameters['FunctionName'] = $caller }
        }

        Write-PSFMessage @parameters
    }

    # Read inside methods, never as a field initialiser: PowerShell evaluates property defaults at
    # class-definition time on some paths and at instantiation time on others, so an initialiser
    # silently ignores configuration changed after import.
    hidden [object] Config([string] $Name, [object] $Fallback) {
        return (Get-PSFConfigValue -FullName "SqlPowerDoc.$Name" -Fallback $Fallback)
    }
}
