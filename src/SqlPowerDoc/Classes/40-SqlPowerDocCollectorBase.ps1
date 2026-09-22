#
# Tier 4x: the collector base (plan sections 2.3 and 3.5).
#
# Every data collector (machine info, SQL server info, network scan) derives from this. It owns
# four things no individual collector should have to reimplement:
#
#   * Platform - the injected SqlPowerDocPlatform seam (plan section 3.2), so every collector
#     gets CIM/registry/process access through the same mockable boundary.
#   * Status/Scope - a caller can inspect where a collection is and filter which sections run,
#     without touching a single collector method.
#   * Start()/Complete()/Duration - timing that survives a partially-successful run instead of
#     being scattered across individual collector methods.
#   * Errors/AddError() - one collector class with 55 methods cannot let one missing WMI class
#     abort the whole inventory; AddError() records the failure instead of throwing, and
#     Complete() reports the aggregate result as Failed rather than losing the section silently.
#
# Derives from SqlPowerDocBase (Classes/10-) so every collector logs and reads configuration
# through the same Log/Config surface as the rest of the module.
#

class SqlPowerDocCollectorBase : SqlPowerDocBase {
    [SqlPowerDocPlatform] $Platform
    [SqlPowerDocCollectorStatus] $Status = [SqlPowerDocCollectorStatus]::NotStarted
    [SqlPowerDocCollectionScope] $Scope
    [System.Collections.Generic.List[hashtable]] $Errors
    [timespan] $Duration
    hidden [datetime] $StartTime

    SqlPowerDocCollectorBase([SqlPowerDocPlatform] $Platform) : base() {
        if ($null -eq $Platform) { throw [System.ArgumentNullException]::new('Platform') }
        $this.Platform = $Platform
        $this.Errors = [System.Collections.Generic.List[hashtable]]::new()
    }

    SqlPowerDocCollectorBase(
        [SqlPowerDocPlatform] $Platform,
        [System.Management.Automation.PSCmdlet] $Cmdlet
    ) : base($Cmdlet) {
        if ($null -eq $Platform) { throw [System.ArgumentNullException]::new('Platform') }
        $this.Platform = $Platform
        $this.Errors = [System.Collections.Generic.List[hashtable]]::new()
    }

    [void] Start() {
        $this.Status = [SqlPowerDocCollectorStatus]::Running
        $this.StartTime = [datetime]::UtcNow
        $this.Log('Verbose', "Starting collection: $($this.GetType().Name)")
    }

    [void] Complete() {
        $this.Duration = [datetime]::UtcNow - $this.StartTime
        $this.Status = if ($this.Errors.Count -gt 0) {
            [SqlPowerDocCollectorStatus]::Failed
        }
        else {
            [SqlPowerDocCollectorStatus]::Completed
        }
        $this.Log('Verbose', "Collection completed in $($this.Duration.TotalSeconds)s with $($this.Errors.Count) error(s)")
    }

    # Section-scoped soft failure. Callers record a failed operation here instead of letting it
    # abort the rest of the collection; Complete() turns one or more recorded errors into an
    # overall Failed status.
    [void] AddError([string] $Operation, [System.Exception] $Exception) {
        $this.Errors.Add(@{
                Operation = $Operation
                Message   = $Exception.Message
                Timestamp = [datetime]::UtcNow
                Exception = $Exception
            })
        $this.Log('Warning', "Error in ${Operation}: $($Exception.Message)")
    }

    [bool] ShouldCollect([SqlPowerDocCollectionScope] $RequiredScope) {
        return ($this.Scope -band $RequiredScope) -eq $RequiredScope
    }
}
