---
title: Update README, requirements, and docs for PS 7+, SMO 2025, and ImportExcel
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

After modernization (CIM, ImportExcel, Pester, optional Pode), **documentation** is the **integration contract** for contributors and operators. Stale docs cause wrong prerequisites and failed first-run.

**Goal:** Synchronize **`README.md`**, **`requirements.md`**, and **`tests/README.md`** (and **wiki** pointer if applicable) with: **PowerShell 7+** as primary, **SMO / SSMS** expectations for SQL features, **ImportExcel** module requirement, **WinRM** for remote CIM, **no Office COM** requirement removed, **Pode** dashboard optional section, and **TDD** workflow (`Run-AllTests.ps1`, `[RED]`/`[GREEN]` discipline).

### In scope

- Single pass consistency review across the three files above.
- Cross-links between tasks in `.specs/tasks/todo/` (optional one-line “see also”).
- **TDD for docs task:** N/A for executable tests; use **checklist** verification with **Judge** rubric on completeness.

### Out of scope

- Rewriting entire wiki; only update pointers if broken.

### Risks and assumptions

| Risk | Mitigation |
|------|------------|
| Doc drift returns | Add “last verified” date and repo commit SHA note in README footer. |

**Analysis:** [.specs/analysis/analysis-update-docs-powershell7-smo-importexcel.md](../../../.specs/analysis/analysis-update-docs-powershell7-smo-importexcel.md)

## Acceptance criteria

1. **Given** new contributor, **when** they read README prerequisites, **then** they install PS7, Pester 5, ImportExcel, and understand SMO/SQL requirement.
2. **Given** remote scan scenario, **when** they read requirements, **then** WinRM/CIM is explicit.
3. **Given** COM Excel, **when** README searched, **then** text states **removed/deprecated** (not “install Excel”).
4. **Given** `tests/README.md`, **when** opened, **then** `Run-AllTests.ps1` command matches actual script.

## Implementation Process

### Step 1: Diff docs vs current `requirements.md` + code grep gates

**Verification:** Judge 4.5/5.0 (accuracy rubric)

### Step 2: README rewrite sections (install, run inventory, run tests, dashboard)

**Verification:** Judge 4.5/5.0

### Step 3: tests/README cross-links + footer “last verified”

**Verification:** Judge 4.0/5.0

## Definition of Done

- [ ] All three files consistent.
- [ ] No stale Office COM prerequisite.
- [ ] Judge self-score ≥ 4.5 recorded in plan completion.

## Plan phase completion

- [x] Research / analysis / architecture / decomposition / parallelize / verifications

**Plan judge score (orchestrator):** 4.6/5.0
