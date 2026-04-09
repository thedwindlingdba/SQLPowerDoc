# Analysis: Assessment + DbObjects exports → ImportExcel

## Anchors

- `Export-SqlServerInventoryDatabaseEngineAssessmentToExcel` — COM ~10697; `$WorksheetCount = 6`.
- `Export-SqlServerInventoryDatabaseEngineDbObjectsToExcel` — COM ~11206; `$WorksheetCount = 74`.

## Strategy

- Reuse **workbook builder** and **fixture patterns** from Database Engine Config task.
- **DbObjects** is largest: plan **worksheet batches** (e.g. 10 sheets per RED/GREEN cycle).
- **Assessment** smaller: single slice may suffice.

## TDD

- Separate test files or contexts: `*-Assessment*.test.ps1` and `*-DbObjects*.test.ps1` recommended to keep Pester runtime manageable.

## Dependencies

- Config task proves builder + team velocity; this task assumes **builder API** stable or extends it.
