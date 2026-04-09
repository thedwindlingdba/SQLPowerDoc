# Analysis: SqlPowerDocInventoryCollector strangler

## Goal

Extract long `Get-SqlServerInventory` (or equivalent) **imperative** flow into **`class SqlPowerDocInventoryCollector`** with **phased** migration: existing function becomes **thin facade** calling the class.

## TDD

- **RED:** Test `SqlPowerDocInventoryCollector` **unit** with mocked SMO/CIM dependencies (where possible) or **integration** flag `Skip` when SMO absent.
- **GREEN:** Move **one** logical phase (e.g. server metadata) into class method per commit.

## Anchors

- Search `Get-SqlServerInventory` in `SqlServerInventory.psm1` for entrypoint and parameters.

## Risks

| Risk | Mitigation |
|------|------------|
| Tight coupling | Introduce **DTO** PSCustomObject shapes between phases. |
| Long runtime | Do not require full inventory in default Pester; use **minimal** mock graph. |
