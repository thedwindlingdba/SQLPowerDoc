# Analysis: SqlPowerDocCimClient (replace Get-WmiObject)

## Code anchors

- `Modules/NetworkScan/NetworkScan.psm1` — multiple `Get-WmiObject` (lines ~22, 62, 106, 1358, 1515, 1605, 1647, 1662, 1756, 1771, 1823, 1839).
- `Tools/SQL Inventory.ps1` — `Get-WmiObject Win32_NetworkAdapterConfiguration` (~162).

## WMI → CIM mapping

| WMI pattern | CIM replacement |
|-------------|-----------------|
| `Get-WmiObject -Class X -Namespace root\CIMV2` | `Get-CimInstance -ClassName X -Namespace root/cimv2` |
| Remote `-ComputerName` | Same on `Get-CimInstance` with `-ComputerName` (requires WinRM/CIM session on PS7+) |

## TDD strategy

- Introduce **`class SqlPowerDocCimClient`** with methods wrapping `Get-CimInstance` and optional **session reuse**.
- Unit tests: **mock** at command level using Pester’s `Mock Get-CimInstance` returning synthetic CIM-like objects (hashtable cast to PSCustomObject with NoteProperty).

## Risks

| Risk | Mitigation |
|------|------------|
| PS7 remoting differs from DCOM WMI | Document **WinRM** prerequisite for remote scans; fallback note in README. |
| Large blast radius | Migrate **one** hotspot per commit behind same class API. |
