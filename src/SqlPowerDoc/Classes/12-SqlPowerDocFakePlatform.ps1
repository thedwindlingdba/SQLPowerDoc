#
# Tier 1x: the test seam (plan section 3.2).
#
# This ships inside the module rather than living in a .Tests.ps1 file, and the reason is
# mechanical: a class declared in a test file is in a different parse scope and cannot inherit
# from SqlPowerDocPlatform, which is declared inside the module. Shipping it costs ~80 lines, it
# is not exported, and it is what makes every CIM-backed collector unit-testable on a host where
# Get-CimInstance does not exist and therefore cannot be mocked.
#

class SqlPowerDocFakePlatform : SqlPowerDocPlatform {
    # Single-shot responses: 'ClassName' or 'ClassName@ComputerName' -> object[]
    [hashtable] $Responses = @{}

    # Queued responses for associator chains. GetDisk is not four independent lookups, it is a
    # dependent chain - Win32_DiskDrive, then ASSOCIATORS OF ... ResultClass = Win32_DiskPartition,
    # then Win32_LogicalDisk, then Win32_Volume - where each query's filter is built from the
    # previous result. A dictionary keyed only on class name cannot return different data for the
    # second and third hop, so each Dequeue() serves the next call matching the key and the table
    # above remains the fallback once a queue is drained (plan section 5.5).
    [hashtable] $ResponseQueue = @{}

    # 'Hive\Key\Name' -> value
    [hashtable] $Registry = @{}

    # 'Computer:Port' -> $true
    [hashtable] $OpenPorts = @{}

    # ComputerName -> canned session object, for collectors that pass a session around.
    [hashtable] $CimSessions = @{}

    # Every seam call, in order. Tests assert the REQUEST as well as the response: that is what
    # catches a collector which quietly starts pulling whole instances instead of an explicit
    # -Property list, the main cost driver of a remote inventory pass.
    [System.Collections.Generic.List[hashtable]] $Calls = [System.Collections.Generic.List[hashtable]]::new()

    # Flip to $false to exercise the unsupported-host path without needing a second platform type.
    [bool] $ForceWindows = $true

    [bool] Supports([SqlPowerDocCapability] $Capability) {
        return $this.ForceWindows
    }

    [object[]] GetCimInstance([hashtable] $Query) {
        $this.AssertSupported([SqlPowerDocCapability]::CimQuery)
        $this.Calls.Add($Query)

        $class = $this.QueryKey($Query)
        $scoped = '{0}@{1}' -f $class, $Query['ComputerName']

        foreach ($key in $scoped, $class) {
            if ($this.ResponseQueue.ContainsKey($key) -and $this.ResponseQueue[$key].Count -gt 0) {
                return @($this.ResponseQueue[$key].Dequeue())
            }
        }

        foreach ($key in $scoped, $class) {
            if ($this.Responses.ContainsKey($key)) { return @($this.Responses[$key]) }
        }

        return @()
    }

    [object] NewCimSession([string] $ComputerName, [pscredential] $Credential) {
        $this.AssertSupported([SqlPowerDocCapability]::CimQuery)
        $this.Calls.Add(@{ CimSession = $ComputerName; ComputerName = $ComputerName })

        if ($this.CimSessions.ContainsKey($ComputerName)) { return $this.CimSessions[$ComputerName] }

        return [PSCustomObject]@{ ComputerName = $ComputerName }
    }

    [object] GetRegistryValue([string] $ComputerName, [string] $Hive, [string] $Key, [string] $Name) {
        $this.AssertSupported([SqlPowerDocCapability]::RemoteRegistry)
        $this.Calls.Add(@{ Registry = "$Hive\$Key\$Name"; ComputerName = $ComputerName })

        return $this.Registry["$Hive\$Key\$Name"]
    }

    [bool] TestTcpPort([string] $ComputerName, [int] $Port, [int] $TimeoutMilliseconds) {
        return [bool] $this.OpenPorts["${ComputerName}:${Port}"]
    }

    # Stage one more response for $Key, to be served before the single-shot Responses table.
    [void] EnqueueResponse([string] $Key, [object[]] $Response) {
        if (-not $this.ResponseQueue.ContainsKey($Key)) {
            $this.ResponseQueue[$Key] = [System.Collections.Generic.Queue[object[]]]::new()
        }

        $this.ResponseQueue[$Key].Enqueue($Response)
    }

    # Direct queries name their target in ClassName; associator queries name it in the WQL
    # ResultClass clause, which is the only stable key a dependent chain can be staged against.
    hidden [string] QueryKey([hashtable] $Query) {
        $class = [string] $Query['ClassName']
        if (-not [string]::IsNullOrEmpty($class)) { return $class }

        $match = [regex]::Match([string] $Query['Query'], 'ResultClass\s*=\s*(?<class>\w+)', 'IgnoreCase')
        if ($match.Success) { return $match.Groups['class'].Value }

        return ''
    }
}
