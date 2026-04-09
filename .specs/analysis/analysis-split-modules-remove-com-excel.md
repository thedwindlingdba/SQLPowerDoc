# Analysis: Split SqlServerInventory / WindowsInventory layout

## Current state

- `SqlServerInventory.psm1` — monolithic (10k+ lines); multiple concerns (inventory, export, assessment).
- `WindowsInventory.psm1` — smaller but mixed concerns.

## Target layout (incremental)

```
Modules/SqlServerInventory/
  SqlServerInventory.psd1
  SqlServerInventory.psm1   # dot-sources below
  Classes/*.ps1
  Private/*.ps1
  Public/*.ps1
```

## COM removal gate

- After ImportExcel tasks, grep for `Excel.Application` / `Office.Interop` — **must be zero** before marking this task complete.

## TDD

- **RED:** Moving a function breaks import — add test `Import-Module` + invoke one public cmdlet with fixture.
- **GREEN:** Fix dot-source order (`Classes` before `Public`).

## Risks

| Risk | Mitigation |
|------|------------|
| Dot-source order | Single `RootModule` loader script documented in README. |
| Circular deps | Keep cross-calls only via public functions in same module first. |
