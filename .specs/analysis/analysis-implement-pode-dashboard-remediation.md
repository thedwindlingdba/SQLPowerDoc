# Analysis: Pode + PSWriteHTML dashboard

## Stack

- [Pode](https://badgerati.github.io/Pode/) — lightweight PS web server.
- [PSWriteHTML](https://github.com/EvotecIT/PSWriteHTML) — HTML components from PowerShell.

## Security

- **Allowlist** remediation actions (e.g. restart service name pattern, max count per hour).
- **Audit log** via `SqlPowerDocLogWriter` or LogHelper to file with **who/when/what**.
- **Auth:** Windows auth or API key in **environment variable** — document threat model; default **read-only** dashboard.

## TDD

- **RED:** Pester tests for **allowlist** pure functions (class `SqlPowerDocRemediationGate`).
- **GREEN:** Pode routes call gate before executing scriptblocks.

## Risks

| Risk | Mitigation |
|------|------------|
| Arbitrary code execution | No `Invoke-Expression` of user input; fixed cmdlet map only. |
