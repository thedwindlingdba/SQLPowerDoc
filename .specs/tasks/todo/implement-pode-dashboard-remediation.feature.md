---
title: Add Pode and PSWriteHTML dashboard with allowlisted remediation actions
depends_on:
  - strangle-inventory-collector-class.refactor.md
plan_quality_threshold: 4.5
plan_max_iterations: 3
implement_quality_threshold: 4.5
implement_max_iterations: 3
---

## Initial User Prompt

/add-task turn the current build plan into a series of tasks for the Spec driven design workflow

## Description

### Problem statement and goal

Operators lack a **single pane** to view latest inventory summaries and approved **remediation** actions. Excel exports are batch-oriented.

**Goal:** Add a **`Pode`**-hosted **dashboard** using **PSWriteHTML** for read-only views (inventory highlights, last run status). Expose **optional** **POST** endpoints for **allowlisted** remediation operations (e.g. trigger re-scan, clear cache directory) guarded by **`SqlPowerDocRemediationGate`** class and **audit logging**. **TDD** for **gate** logic and **route** contracts (mock Pode context where needed).

### In scope

- New folder e.g. `Dashboard/` or `Modules/SqlPowerDocDashboard/` with `Start-SqlPowerDocDashboard.ps1` entry.
- **Dependencies** documented: `Pode`, `PSWriteHTML`.
- **Tests:** `tests/SqlPowerDocRemediationGate.test.ps1` (pure logic); optional `tests/PodeDashboard.routes.test.ps1` with lightweight stubs.

### Out of scope

- Full RBAC product; production SSO.
- Mobile-native apps.

### Risks and assumptions

| Risk | Mitigation |
|------|------------|
| Security footgun | Default **read-only**; remediation **disabled** unless env flag set. |

**Analysis:** [.specs/analysis/analysis-implement-pode-dashboard-remediation.md](../../../.specs/analysis/analysis-implement-pode-dashboard-remediation.md)

## Acceptance criteria

1. **Given** default config, **when** dashboard starts, **then** **GET** home returns **200** HTML with inventory summary placeholder or wired data.
2. **Given** remediation disabled flag, **when** **POST** remediation endpoint called, **then** **403** or **404** as documented.
3. **Given** allowlist unit tests, **when** Pester runs, **then** only approved action IDs pass gate.
4. **Given** audit log path, **when** approved action runs, **then** one audit line appended (format test).

## Architecture Overview

- `SqlPowerDocRemediationGate` — validates action id + parameters against static table.
- Pode routes: `/`, `/api/inventory/summary`, `/api/remediation` (optional).
- PSWriteHTML **New-HTML** pages.

## Parallel Execution Plan

**Gate class + tests** ∥ **static HTML layout prototype**; integrate in **serial** step.

## Implementation Process

### Step 1: RED — RemediationGate tests

**Commit:** `[RED]`  
**Verification:** Judge 4.5/5.0

### Step 2: GREEN — Gate implementation

**Commit:** `[GREEN]`  
**Verification:** Judge 4.5/5.0

### Step 3: Pode server + read-only page

**Verification:** Judge 4.5/5.0

### Step 4: Optional remediation + audit

**Verification:** Judge 4.5/5.0

### Step 5: Security + runbook doc

**Verification:** Judge 4.0/5.0

## Definition of Done

- [ ] Dashboard runs locally; tests green.
- [ ] Remediation off by default; audit when on.
- [ ] RED/GREEN for gate.

## Plan phase completion

- [x] Research / analysis / architecture / decomposition / parallelize / verifications

**Plan judge score (orchestrator):** 4.6/5.0
