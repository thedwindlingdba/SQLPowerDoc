---
title: Split SqlServerInventory and WindowsInventory into Classes/Public/Private and delete remaining COM Excel
depends_on:
  - rewrite-dbobjects-assessment-importexcel.feature.md
plan_quality_threshold: 4.5
plan_max_iterations: 3
implement_quality_threshold: 4.5
implement_max_iterations: 3
---

## Initial User Prompt

/add-task turn the current build plan into a series of tasks for the Spec driven design workflow

## Description

### Problem statement and goal

Large `.psm1` files hinder testing, review, and parallel development. **COM Excel** must be **fully eliminated** from the repo after ImportExcel migrations. This task **splits** `SqlServerInventory` and `WindowsInventory` into **`Classes/`**, **`Private/`**, **`Public/`** (or equivalent) with a **single root loader**, and runs a **final grep** to ensure **no** `Excel.Application` / `Microsoft.Office.Interop.Excel` remain anywhere under `Modules/` and `Tools/` (except documented third-party vendored code if any — default: **zero**).

**Goal:** Mechanical extraction with **no intentional behavior change**; **Import-Module** + **one smoke test per module** must pass. **TDD:** `[RED]` test that fails if public command missing after split; `[GREEN]` restore via correct exports/dot-source.

### In scope

- Folder structure under both modules; move **class** files already introduced by prior tasks.
- Update **`*.psd1`** `FunctionsToExport` / `NestedModules` / `RootModule` as needed.
- Repo-wide grep for COM Excel strings; fix stragglers (e.g. `Tools/SQL Inventory.ps1`).

### Out of scope

- New features in inventory logic.
- Pode dashboard.

### Risks and assumptions

| Risk | Mitigation |
|------|------------|
| Export breakage | Compare `Get-Command -Module` before/after lists in test. |
| Huge diff | Split PRs: **WindowsInventory** first, then **SqlServerInventory** in slices. |

**Analysis:** [.specs/analysis/analysis-split-modules-remove-com-excel.md](../../../.specs/analysis/analysis-split-modules-remove-com-excel.md)

## Acceptance criteria

1. **Given** `Import-Module` on both modules, **when** smoke tests run, **then** key public commands exist (list frozen in test file).
2. **Given** grep `Excel.Application` / `Office.Interop.Excel` on `Modules/**/*.psm1` + `Tools/**/*.ps1`, **when** run, **then** **zero** matches.
3. **Given** `Run-AllTests.ps1`, **when** executed, **then** exit 0.
4. **Given** git history, **when** split commits reviewed, **then** mechanical moves separated from logic fixes.

## Parallel Execution Plan

**WindowsInventory split** ∥ **SqlServerInventory: extract Classes only** first; then **serial** public/private extraction for SqlServerInventory to avoid conflicts.

## Implementation Process

### Step 1: Inventory exported commands (doc + test RED)

**Verification:** Judge 4.5/5.0

### Step 2: GREEN — WindowsInventory layout

**Verification:** Judge 4.5/5.0

### Step 3: SqlServerInventory phased extraction

**Verification:** Judge 4.5/5.0 per slice

### Step 4: COM grep gate + Tools cleanup

**Verification:** Judge 4.5/5.0

## Definition of Done

- [ ] Folder layout established; modules load.
- [ ] No COM Excel in scoped paths.
- [ ] RED/GREEN for smoke tests.

## Plan phase completion

- [x] Research / analysis / architecture / decomposition / parallelize / verifications

**Plan judge score (orchestrator):** 4.6/5.0
