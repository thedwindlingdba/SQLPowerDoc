# Analysis: Export-WindowsInventoryToExcel → ImportExcel

## Anchor

- `Modules/WindowsInventory/WindowsInventory.psm1` — `Export-WindowsInventoryToExcel` (~741+), COM `Excel.Application` ~774 and ~837.
- Worksheet count / tab colors today use Interop enums — ImportExcel uses `-TableStyle`, `-AutoSize`, `-FreezeTopRow`.

## Strategy

- Extract **`SqlPowerDocExcelWorkbookBuilder`** class (or Windows-specific builder) building **in-memory** worksheet specs (title, data as `Object[]`, table options).
- **`Export-Excel`** per worksheet or single workbook with `-WorksheetName` passes.
- **Golden file** optional: compare worksheet **names** + **row counts** via `Import-Excel` round-trip in tests (requires `ImportExcel` module in CI/dev).

## TDD

- RED: test calls export function with **minimal fake** `WindowsInventory` PSCustomObject fixture; expects `.xlsx` exists and `Import-Excel` row count ≥ 1.
- GREEN: replace COM body with ImportExcel pipeline.

## Risks

| Risk | Mitigation |
|------|------------|
| Parity of color themes | Phase 1: Medium theme only; document theme gaps. |
| Large function | Strangler: extract **data gathering** from **presentation** first. |
