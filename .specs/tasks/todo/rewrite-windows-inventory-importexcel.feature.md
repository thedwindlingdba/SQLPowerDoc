---
title: Rewrite Windows inventory export to ImportExcel via workbook builder class
depends_on:
  - bootstrap-dev-branch-pester-module-skeleton.chore.md
plan_quality_threshold: 4.5
plan_max_iterations: 3
implement_quality_threshold: 4.5
implement_max_iterations: 3
---

## Initial User Prompt

/add-task turn the current build plan into a series of tasks for the Spec driven design workflow

## Description

### Problem statement and goal

`Export-WindowsInventoryToExcel` in **`WindowsInventory.psm1`** depends on **COM Excel** and `Microsoft.Office.Interop.Excel`, which is fragile on servers without Office, blocks headless automation, and fails on many PS7/Core scenarios.

**Goal:** Reimplement export using the community **`ImportExcel`** module (`Export-Excel`), driving layout through a **`SqlPowerDocExcelWorkbookBuilder`** (or `SqlPowerDocWindowsInventoryWorkbookBuilder`) **class** that collects worksheet definitions then emits `.xlsx`. Remove **COM** and **Interop** from this code path. Follow **TDD**: fixture inventory object → **RED** (expect xlsx + schema) → **GREEN** (ImportExcel implementation).

### In scope

- `Export-WindowsInventoryToExcel` body replacement; **public** parameters preserved (`Path`, `ColorTheme`, etc.) — map unsupported theme combos to documented defaults.
- **Dependency:** declare `ImportExcel` in `requirements.md` / module manifest if applicable.
- **Tests:** `tests/Export-WindowsInventoryToExcel.test.ps1` with **synthetic** `WindowsInventory` fixture (minimal required properties discovered via code read in implementation).
- **COM removal** for this function only (other functions unchanged unless they share the same block).

### Out of scope

- Rewriting `Get-WindowsInventory` data collection.
- SQL Server inventory exports (separate tasks).

### Risks and assumptions

| Risk | Mitigation |
|------|------------|
| Fixture drift | Document required properties in test file header. |
| ImportExcel not installed | `BeforeAll { Import-Module ImportExcel -ErrorAction Stop }` with skip message in README. |

**Analysis:** [.specs/analysis/analysis-rewrite-windows-inventory-importexcel.md](../../../.specs/analysis/analysis-rewrite-windows-inventory-importexcel.md)

## Acceptance criteria

1. **Given** synthetic `WindowsInventory` fixture, **when** `Export-WindowsInventoryToExcel` runs with `-Path` temp xlsx, **then** file exists and `Import-Excel` can read ≥1 worksheet.
2. **Given** grep on `WindowsInventory.psm1` for this function’s code path, **when** checked, **then** no `New-Object -Com Excel.Application` remains for **Export-WindowsInventoryToExcel**.
3. **Given** `Run-AllTests.ps1`, **when** run with `ImportExcel` installed, **then** exit 0.
4. **Given** README/requirements, **when** read, **then** `Install-Module ImportExcel` documented.

## Architecture Overview

### Strategy

1. Read current function; list worksheets and data sources.
2. Builder class: `AddWorksheet(name, data, options)`.
3. RED test for file + worksheet name set.
4. GREEN: `Export-Excel` loop.

## Parallel Execution Plan

**Step 1** inventory of worksheets (doc) ∥ **Step 2** fixture design; then serial **Step 3–5** implementation.

## Implementation Process

### Step 1: Worksheet inventory doc

**Verification:** Judge 4.0/5.0

### Step 2: RED — Pester fails without implementation

**Commit:** `[RED]`  
**Verification:** Judge 4.5/5.0

### Step 3: Builder class + GREEN

**Commit:** `[GREEN]`  
**Verification:** Judge 4.5/5.0

### Step 4: Remove Interop/COM and verify grep

**Verification:** Judge 4.5/5.0

### Step 5: Docs + requirements

**Verification:** Judge 4.0/5.0

## Definition of Done

- [ ] COM-free Windows inventory Excel export.
- [ ] ImportExcel documented.
- [ ] RED/GREEN commits.

## Plan phase completion

- [x] Research / analysis / architecture / decomposition / parallelize / verifications

**Plan judge score (orchestrator):** 4.6/5.0
