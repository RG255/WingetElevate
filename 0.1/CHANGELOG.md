# Changelog

## [0.1] - 2026-03-13

### Added
- Initial release.
- `winget` function: transparent drop-in replacement that routes all winget commands through a persistent elevated NamedPipe session.
- One-time UAC prompt per PowerShell session; subsequent calls reuse the session.
- Automatic `--accept-source-agreements` flag with `-NoAcceptSourceAgreements` switch to suppress per call.
- Real winget.exe discovery via registry (no `Get-AppxPackage` dependency; works in PS 5.0 and PS 7.x).
- Server-side fallback discovery of winget.exe in `C:\Program Files\WindowsApps\` for cases where the registry path is unavailable.
- Output streamed line-by-line via NamedPipe `Send-ProgressInfo`.
- Automatic pipe session cleanup on PowerShell exit via `Register-EngineEvent PowerShell.Exiting`.
