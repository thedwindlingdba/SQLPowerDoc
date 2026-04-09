# Analysis: SqlPowerDocLogWriter (PoshBot-style structured logging)

## Code anchors

- `Modules/LogHelper/LogHelper.psm1` — `Write-Log`, queue, `Set-LoggingPreference`, file path.
- `tests/LogHelper.test.ps1` — extend or add parallel `SqlPowerDocLogWriter.test.ps1` after class lands.

## Design constraints

- **TDD:** New class/module surface requires **RED** test for line format + host mirroring, then **GREEN** implementation.
- **Performance:** Avoid per-line `Format-Hex`; prefer single `StringBuilder` or interpolated structured prefix.
- **Compatibility:** PowerShell 7+ primary; avoid breaking existing `Write-Log` callers — add **wrapper** or **optional** sink rather than silent behavior change until feature-flagged.

## References

- [PoshBot logging patterns](https://github.com/poshbotio/poshbot) (conceptual: timestamp + severity + message).
- Pester 5: `BeforeAll`, mock `Write-Host`/`Write-Information` sparingly; prefer testing **returned** structured records or **file** lines.

## Risks

| Risk | Mitigation |
|------|------------|
| Flaky host-stream tests | Assert **file** and **object** output; host optional. |
| Log queue races | Reuse LogHelper synchronization patterns; document thread model. |
