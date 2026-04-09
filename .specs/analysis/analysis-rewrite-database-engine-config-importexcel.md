# Analysis: Export-SqlServerInventoryDatabaseEngineConfigToExcel → ImportExcel

## Anchor

- `Modules/SqlServerInventory/SqlServerInventory.psm1` — `Export-SqlServerInventoryDatabaseEngineConfigToExcel`, COM from ~4619; `$WorksheetCount = 55`; heavy Interop enums.

## Approach

- Same **workbook builder** pattern as Windows task; prefer **shared** `SqlPowerDocExcelWorkbookBuilder` in `Modules/SqlServerInventory/Classes/` if Windows task landed first — **this task** may extract shared base class or duplicate minimal builder then consolidate in `split-modules` task.
- Strangler: keep **outer** cmdlet; replace **`process {}`** Excel block.

## TDD

- Minimal `SqlServerInventory` fixture (or subset object the export reads) — discover required properties during RED test authoring.
- Assert worksheet **names** match a frozen list (subset acceptable for first GREEN).

## Risks

| Risk | Mitigation |
|------|------------|
| 55 sheets | Incremental: implement **N** sheets per PR with tests per slice; task allows multiple RED/GREEN cycles. |
| Memory | Use streaming `Export-Excel` where possible; avoid loading full Excel COM (goal). |
