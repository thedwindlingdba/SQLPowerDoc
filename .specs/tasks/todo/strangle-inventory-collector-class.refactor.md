---
title: Move Get-SqlServerInventory logic into SqlPowerDocInventoryCollector class
depends_on:
  - split-modules-remove-com-excel.refactor.md
plan_quality_threshold: 4.5
plan_max_iterations: 3
implement_quality_threshold: 4.5
implement_max_iterations: 3
---

## Initial User Prompt

/add-task turn the current build plan into a series of tasks for the Spec driven design workflow

## Description

### Problem statement and goal

Server inventory collection is embedded in **large procedural functions**, making unit testing and reuse (e.g. dashboard APIs) expensive.

**Goal:** Introduce **`SqlPowerDocInventoryCollector`** and **strangler-migrate** logic from **`Get-SqlServerInventory`** (name verified at implementation) into **methods** while preserving the **public** function signature as a **facade**. Each migration slice uses **TDD** (`[RED]` test for method behavior with mocks, `[GREEN]` move code).

### In scope

- Class in `Modules/SqlServerInventory/Classes/SqlPowerDocInventoryCollector.ps1` (or path after split task).
- Facade function delegates to class; **no** output schema change without explicit ADR note.
- Pester tests: `tests/SqlPowerDocInventoryCollector.test.ps1`.

### Out of scope

- Rewriting export layer.
- Live SQL integration in default CI (mock-first).

### Risks and assumptions

| Risk | Mitigation |
|------|------------|
| SMO required for many paths | Use `Skip` when module missing; mock `Server` object where feasible. |

**Analysis:** [.specs/analysis/analysis-strangle-inventory-collector-class.md](../../../.specs/analysis/analysis-strangle-inventory-collector-class.md)

## Acceptance criteria

1. **Given** mocked dependencies, **when** collector method `X` is tested, **then** expected partial inventory fragment is returned.
2. **Given** `Get-SqlServerInventory` (or actual name), **when** called, **then** it invokes collector (assert via `Mock` of constructor or trace hook documented in test).
3. **Given** `Run-AllTests.ps1`, **when** run, **then** exit 0.
4. **Given** migration plan in task notes, **when** reviewed, **then** ≥3 distinct phases with RED/GREEN pairs are listed.

## Parallel Execution Plan

**Serial** strangler by phase inside same file to avoid merge conflicts; optional parallel **test** file additions vs **class** file if in separate paths.

## Implementation Process

### Step 1: Locate entry function; document phases

**Verification:** Judge 4.0/5.0

### Step 2–N: Per-phase RED/GREEN extractions

**Verification:** Judge 4.5/5.0 each

### Final: Facade cleanup + docs

**Verification:** Judge 4.5/5.0

## Definition of Done

- [ ] Class owns migrated logic slices.
- [ ] Public API stable.
- [ ] TDD commits evidenced.

## Plan phase completion

- [x] Research / analysis / architecture / decomposition / parallelize / verifications

**Plan judge score (orchestrator):** 4.6/5.0
