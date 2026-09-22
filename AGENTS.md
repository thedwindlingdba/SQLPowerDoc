## Cursor Cloud specific instructions

### Overview

SQL Power Doc is a **Windows PowerShell** toolkit for discovering, documenting, and diagnosing SQL Server instances and their underlying Windows OS configurations. It is 100% PowerShell (`.ps1`, `.psm1`, `.psd1` files) with no package manager or build system.

### Environment

- **PowerShell Core (pwsh 7.x)** is installed on the Linux VM for parsing, linting, and testing.
- **`ImportExcel` 7.8.10 is preinstalled.** **`PSScriptAnalyzer` and `Pester` are NOT preinstalled** — install the pinned toolchain first:

```bash
pwsh -NoProfile -File /workspace/Tests/Install-DevDependencies.ps1
```

  Versions are pinned in `Tests/RequiredModules.psd1`. Pin Pester explicitly: the PowerShell Gallery default is now 6.x, while the test suites are written against Pester 5 idioms (both 5.7.1+ and 6.x are verified to run them).
- The codebase is Windows-targeted; full end-to-end execution (WMI, SMO, COM/Excel, AD) requires a Windows host with SQL Server. On Linux, static analysis, parsing, linting, and module-level testing are fully functional.

### Linting

```bash
pwsh -NoProfile -Command "Import-Module PSScriptAnalyzer; Invoke-ScriptAnalyzer -Path /workspace -Recurse -ExcludeRule PSAvoidUsingWriteHost"
```

Baseline is 3312 findings: 4 `Error`, 359 `Warning`, 2949 `Information` (2935 of which are `PSAvoidTrailingWhitespace`). The 4 `Error`-severity findings are pre-existing and by-design for this legacy codebase — note that only **three** are credential-parameter patterns:

| File:Line | Rule |
|---|---|
| `SqlServerInventory.psm1:1004` | `PSAvoidUsingUsernameAndPasswordParams` |
| `SqlServerDatabaseEngineInformation.psm1:4004` | `PSAvoidUsingUsernameAndPasswordParams` |
| `SqlServerDatabaseEngineInformation.psm1:11648` | `PSAvoidUsingUsernameAndPasswordParams` |
| `SqlServerDatabaseEngineInformation.psm1:2870` | `PSAvoidAssignmentToAutomaticVariable` |

`PSAvoidUsingWMICmdlet` reports **71** findings, which independently corroborates the AST-derived count of 71 live `Get-WmiObject` call sites. It is a useful burn-down metric for the WMI-to-CIM migration.

### Testing

Run the Phase 0 baseline suite, which pins the current state of the repository (67 tests, all passing):

```bash
pwsh -NoProfile -Command "Import-Module Pester; Invoke-Pester -Path /workspace/Tests -Output Detailed"
```

`LogHelper` is the only module that is fully *functional* on Linux, but **7 of 8 modules import successfully** — see the import gotcha below. Mocked-seam unit tests, pure-logic tests, and `ImportExcel` output tests all run natively on Linux.

### The v3 `SqlPowerDoc` module (in progress)

The rewrite lives under `src/SqlPowerDoc/` and is built with InvokeBuild + ModuleBuilder. The legacy `Modules/` tree stays in place as the reference until the final work item removes it.

```bash
pwsh -NoProfile -File /workspace/build/Install-DevDependencies.ps1   # pinned toolchain, PSResourceGet only
pwsh -NoProfile -Command "Import-Module InvokeBuild; Invoke-Build"   # Clean, Build, Lint, Test
pwsh -NoProfile -File /workspace/Tests/Phase0-Verification/Verify-Toolchain.ps1
```

- Dependencies are pinned in `build.requires.psd1`. Install with `build/Install-DevDependencies.ps1`; never with the retired PowerShellGet cmdlets, and never the SQL Server PowerShell module (dbatools replaces it).
- `Build` must run before `Lint` and `Test`: both operate on `output/SqlPowerDoc/<version>/`, never on the loose source files. PSScriptAnalyzer reports `TypeNotFound` on individual class files because a derived class's base type is declared in another file.
- The source manifest's `FunctionsToExport` is `'*'` by design, so the dev loader's `Export-ModuleMember` is not filtered. ModuleBuilder replaces it with the real list at build time. Repo-wide lint therefore reports one expected `PSUseToExportFieldsInManifest` warning against `src/SqlPowerDoc/SqlPowerDoc.psd1`.
- `Invoke-ScriptAnalyzer` throws an intermittent `NullReferenceException` from its own command cache on this VM (roughly one run in fifteen). The `Lint` task retries once and fails on a second throw.
- The new suite is `tests/` (lowercase); the legacy Phase 0 suite is `Tests/`. They are distinct on Linux but collide on case-insensitive filesystems until the legacy tree is removed.

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
- **Parsing cleanly is not the same as importing.** All 13 `.ps1`/`.psm1` files parse with zero errors, but `SqlServerDatabaseEngineInformation.psm1` **fails to import** on PowerShell 7: at line 12100, `[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')` returns `$null` on .NET Core, and `$null | ForEach-Object { ... }` still executes its body once with `$_ = $null`, so `$_.GetName()` throws `InvokeMethodOnNull`. The other 7 modules import fine.
- **CIM cmdlets are not merely non-functional on Linux — the `CimCmdlets` module is not shipped at all.** `Get-CimInstance` cannot even be resolved (`CommandNotFoundException`), which means **Pester cannot mock it** (`Could not find Command Get-CimInstance`). Any Linux-side unit test of CIM-dependent code must mock a wrapper function that exists on all platforms, not the cmdlet itself. `Microsoft.Management.Infrastructure.CimException` does resolve everywhere, so `catch [CimException]` blocks are portable.
- **`ImportExcel` traps verified on this VM:** `Close-ExcelPackage` has **no `-Save` parameter** (saving is the default; `-Save` binds as a prefix of `-SaveAs` and the file is silently never written). A `-TableName` that looks like a cell address (for example `Tbl35`) is rejected with only a warning and **no table is created**. `-AutoSize` cannot work on Linux at all — `System.Drawing.Common` is Windows-only on modern .NET, so installing `libgdiplus` does not help; set column widths explicitly.
- The `Convert-*ToExcel.ps1` scripts require Excel COM automation (Windows + Excel installed).
- `Tools/SQL Inventory.ps1` contains en-dash characters (`–le`) at lines 84 and 106. These **parse and evaluate correctly** — PowerShell accepts en-dash and em-dash as operator prefixes — so the file is not broken by them.
