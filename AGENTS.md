## Cursor Cloud specific instructions

### Overview

SQL Power Doc is a **Windows PowerShell** toolkit for discovering, documenting, and diagnosing SQL Server instances and their underlying Windows OS configurations. It is 100% PowerShell (`.ps1`, `.psm1`, `.psd1` files) with no package manager or build system.

### Environment

- **PowerShell Core (pwsh 7.x)** is installed on the Linux VM for parsing, linting, and testing.
- **PSScriptAnalyzer** (linting) and **Pester** (testing) are installed as PowerShell modules under `CurrentUser` scope.
- The codebase is Windows-targeted; full end-to-end execution (WMI, SMO, COM/Excel, AD) requires a Windows host with SQL Server. On Linux, static analysis, parsing, linting, and module-level testing are fully functional.

### Linting

```bash
pwsh -NoProfile -Command "Import-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path /workspace -Recurse -ExcludeRule PSAvoidUsingWriteHost"
```

There are 4 pre-existing `Error`-severity findings (credential parameter patterns in `SqlServerInventory.psm1` and `SqlServerDatabaseEngineInformation.psm1`). These are by-design for this legacy codebase.

### Testing

Pester 5.x is available. Example:

```bash
pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Path /path/to/tests -Output Detailed"
```

The `LogHelper` module is the only module that can be fully imported and tested on Linux since it has no Windows-specific dependencies.

### Module structure

All modules live under `Modules/`. Each has a `.psm1` (code) and most have a `.psd1` (manifest). All 8 modules and 5 scripts parse cleanly on PowerShell 7.x.

| Module | Functions | Linux-compatible |
|---|---|---|
| LogHelper | 6 | Yes |
| NetShell | 27 | Partial |
| NetworkScan | 9 | No (WMI) |
| WindowsMachineInformation | 55 | No (WMI) |
| WindowsInventory | 9 | No (WMI) |
| SqlServerDatabaseEngineInformation | 141 | No (SMO) |
| SqlServerInventory | 22 | No (SMO) |
| RDS-Manager | 25 | No (WMI) |

### Gotchas

- Module manifests use the deprecated `ModuleToProcess` key; this produces warnings but is non-breaking.
- `NetworkScan`, `WindowsInventory`, and `SqlServerInventory` manifests fail `Test-ModuleManifest` on Linux because they reference `NestedModules` by name (resolved via `$env:PSModulePath` on Windows). The `.psm1` files themselves parse fine.
- The `Convert-*ToExcel.ps1` scripts require Excel COM automation (Windows + Excel installed).
