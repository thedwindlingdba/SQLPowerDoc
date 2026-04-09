# Codebase impact: SQL Server 2022/2025 version map

**Task:** `implement-sql-version-map-sql2025.feature.md`  
**Risk:** Medium (large `SqlServerDatabaseEngineInformation.psm1`, SMO enum availability varies by SSMS/SMO install)

## Files to modify (primary)

| Path | Change |
|------|--------|
| `Modules/SqlServerDatabaseEngineInformation/SqlServerDatabaseEngineInformation.psm1` | Add `SQLServer2022` (16.0.0.0), `SQLServer2025` (17.0.0.0) script constants after `SQLServer2019`; extend `Get-SqlServerVersionName`; extend `CompatibilityLevel` switch (~8824) for Version120–Version170 when enum exists; grep-driven updates where `SQLServer2019` is the implicit “latest” cap. |
| `Modules/SqlServerInventory/SqlServerInventory.psm1` | Mirror version constants (lines ~38–46 region); review duplicate `New-Variable` pattern near ~1457 when editing. |
| `Modules/SqlServerDatabaseEngineInformation/SqlServerDatabaseEngineInformation.psd1` | Optionally add `Get-SqlServerVersionName` to `FunctionsToExport` once module imports on PS 7+ (may be same task or follow-up). |

## Files to modify (tests)

| Path | Change |
|------|--------|
| `tests/fixtures/Get-SqlServerVersionName.ps1` | Keep in sync with psm1 function (16/0 → 2022, 17/0 → 2025). |
| `tests/Get-SqlServerVersionName.test.ps1` | New cases for 2022/2025; retain unknown-case test. |

## Integration points

- **Product strings:** `Get-SqlServerVersionName` used in SMO-based product labeling (~5035 region in `SqlServerDatabaseEngineInformation.psm1`).
- **Version compares:** Many `CompareTo($SQLServer2012)` / `$SQLServer2019` patterns; only change where behavior must treat 2022/2025 as newer than 2019 (feature gates, not every historical branch).
- **CompatibilityLevel:** Current switch ends at `Version110` then `default { $_.ToString() }`; newer DBs show raw enum unless Version120+ mapped.

## Key function (current)

`Get-SqlServerVersionName` (~3944): major/minor → marketing name; trailing space in `'unknown '` is legacy—tests must match unless intentionally normalized in this task (call out as optional cleanup).
