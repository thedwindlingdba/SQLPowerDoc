# Tests (Pester 5)

## Prerequisites

- PowerShell **7+** (recommended for modernization work; Windows PowerShell 5.1 may still run this suite).
- Pester **5.x** (not Pester 3/4):

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.999999 -Scope CurrentUser -Force
```

## Run

From the **repository root**:

```powershell
pwsh -File .\tests\Run-AllTests.ps1
```

The runner prepends `./Modules` to `$env:PSModulePath`, discovers `*.test.ps1` under `tests/`, and exits non-zero when any test fails.

## Verify tests are not vacuous (AC4)

Use this occasionally on branch **`dev`** with a **clean working tree** (do not commit the rename).

1. Temporarily rename the LogHelper manifest:  
   `Modules\LogHelper\LogHelper.psd1` → `LogHelper.psd1.bak`
2. Run `pwsh -File .\tests\Run-AllTests.ps1` and confirm **non-zero** exit (import failure).
3. Restore: rename `LogHelper.psd1.bak` back to `LogHelper.psd1`.
4. Re-run tests; confirm **zero** exit.

## Optional module layout (LogHelper Public/Private split)

**Deferred.** The default suite imports `LogHelper.psd1` as-is; a structural split is not required for testability today.

## Get-SqlServerVersionName fixture

`Get-SqlServerVersionName` tests load `tests/fixtures/Get-SqlServerVersionName.ps1`, which mirrors the function in `SqlServerDatabaseEngineInformation.psm1`. Full import of that module’s manifest currently fails on PowerShell 7+ until that module is modernized; keep the fixture and the psm1 implementation in sync when changing version labels.
