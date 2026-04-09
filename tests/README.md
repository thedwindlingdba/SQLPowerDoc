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

`Get-SqlServerVersionName` tests load `tests/fixtures/Get-SqlServerVersionName.ps1`, which mirrors the function in `SqlServerDatabaseEngineInformation.psm1`. Keep the fixture and the psm1 implementation **identical** whenever you change version labels (including **2014–2025** RTM majors **12–17** / **0**).

Script-scope constants `SQLServer2022` (**16.0.0.0**) and `SQLServer2025` (**17.0.0.0**) are defined in both `SqlServerDatabaseEngineInformation.psm1` and `SqlServerInventory.psm1` next to the existing version constants.

### CompatibilityLevel display (SMO)

Database **compatibility level** friendly names (**Version120**–**Version170** → SQL Server 2014–2025) are resolved in the engine-information module using **`$enumValue.ToString()`** string keys so older SMO assemblies that lack newer enum members do not break module load; unknown values fall back to the raw enum string.

## SqlPowerDocLogWriter (structured / PoshBot-style lines)

`Modules/LogHelper` exposes **`SqlPowerDocLogWriter`** (class) and **`New-SqlPowerDocLogWriter`**. Each event appends **one UTF-8 line** to the configured file and mirrors to host streams (`Write-Information` / `Write-Warning` / `Write-Error` / `Write-Verbose` for **DEBUG**).

**Field order (single line):**

1. **Timestamp** — UTC `DateTime.ToString('o')` (ISO-8601, ends with `Z`)
2. **Severity** — `INFO`, `WARN`, `ERROR`, or `DEBUG` (uppercase)
3. **Source** — bracketed label, default `SqlPowerDoc`
4. **Message** — remainder of line (no embedded newlines)

**Validation regex (entire line, after trim):**

```regex
^(?<ts>\d{4}-\d{2}-\d{2}T[\d:\.]+Z) (?<sev>INFO|WARN|ERROR|DEBUG) \[(?<src>[^\]]+)\] (?<msg>.*)$
```

**Examples:**

```text
2026-04-08T14:32:01.2345678Z INFO [SqlPowerDoc] Inventory started
2026-04-08T14:32:02.1234567Z WARN [MyScript] Retry 1 of 3
```

Tests: `tests/SqlPowerDocLogWriter.test.ps1`.
