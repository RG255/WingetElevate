# WingetElevate

A transparent `winget` elevation wrapper for standard (non-admin) user accounts on Windows.

## The Problem

On some Windows configurations, `winget` fails for standard user accounts with:

```
0x80070005 : Access is denied.
```

This is a limitation of the WinRT AppX storage API, which rejects requests from
non-elevated processes in certain configurations. It is not an NTFS permissions issue
and cannot be resolved by adjusting file or folder permissions. The error has been
widely reported but remains unresolved at the OS level for affected users.

A secondary issue is that the AppX alias stub at
`%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe` spawns the real winget as a child
process that does not inherit redirected stdout handles, making output capture
unreliable even when elevation is not required.

## The Solution

WingetElevate provides a `winget` function that is a transparent drop-in replacement
for the real winget executable. It routes all winget commands through a persistent
elevated [NamedPipe](https://github.com/RG255/NamedPipe) session:

- On first use per PowerShell session, a single UAC prompt opens the elevated session.
- Subsequent calls in the same session reuse it — no further prompts.
- The elevated session closes automatically when the PowerShell window exits.
- The elevated server locates the real `winget.exe` directly in
  `C:\Program Files\WindowsApps\` (bypassing the AppX alias stub) and captures
  output correctly.
- Output is streamed line-by-line as winget runs.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.0 or later (PowerShell 7.x also supported)
- [NamedPipe](https://github.com/RG255/NamedPipe) module v0.6 or later
- Your user account must be able to elevate via UAC

## Installation

1. Install the [NamedPipe](https://github.com/RG255/NamedPipe) module v0.6 or later
   and ensure it is importable (`Import-Module NamedPipe` succeeds).

2. Copy the `WingetElevate\0.1` folder to your PowerShell modules directory:

```powershell
Copy-Item -Path '.\WingetElevate\0.1' `
          -Destination "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\WingetElevate\0.1" `
          -Recurse
```

3. Add the following line to your PowerShell profile (`$PROFILE`):

```powershell
Import-Module WingetElevate
```

## Usage

Use `winget` exactly as you normally would:

```powershell
winget list
winget upgrade --all
winget install 7zip.7zip
winget search firefox
```

On first use per session you will see:

```
Opening elevated winget session (one-time UAC prompt)...
```

A UAC prompt will appear. After approving, all winget commands run in that session
without further prompts.

## Source Agreements

By default, `--accept-source-agreements` is automatically appended to every winget
command. This bypasses the interactive Microsoft Store source agreement prompt that
would otherwise hang non-interactive sessions.

**To suppress it for a single call**, use the `-NoAcceptSourceAgreements` switch:

```powershell
winget list -NoAcceptSourceAgreements
```

**To remove the auto-append entirely**, edit `WingetElevate.psm1` and change:

```powershell
$extraArgs = if ($NoAcceptSourceAgreements) { @() } else { @('--accept-source-agreements') }
```

to:

```powershell
$extraArgs = @()
```

**To make it opt-in** (off by default, on when explicitly requested), replace the
`winget` function's `-NoAcceptSourceAgreements` switch with an `-AcceptSourceAgreements`
switch and update the line to:

```powershell
$extraArgs = if ($AcceptSourceAgreements) { @('--accept-source-agreements') } else { @() }
```

## Known Limitations

- **Progress indicators**: winget uses carriage-return (`\r`) overwriting for spinners
  and download progress bars. Because output is captured line-by-line through the pipe,
  each frame appears as an individual line rather than updating in place. The actual
  command output (package lists, install results) is unaffected.

- **Windows only**: winget is a Windows-only tool. This module has no Linux or macOS
  support.

- **NamedPipe dependency**: this module requires the
  [NamedPipe](https://github.com/RG255/NamedPipe) module. If NamedPipe is updated to
  a version that is not backwards-compatible with v0.6, update the `RequiredVersion`
  in `WingetElevate.psm1` accordingly.

## How It Works

```
PS Session (non-admin)
    │
    ├─ winget list           ← function call intercepted by WingetElevate
    │
    ├─ [first call only]
    │   └─ Start-PipeSession ─────────────────────────────────► UAC prompt
    │                                                            Elevated PS window (hidden)
    │                                                            NamedPipe server running
    │
    ├─ Send-Request ──────────────────────────────────────────► Server receives command
    │                                                            Locates real winget.exe
    │                                                            Runs via ProcessStartInfo
    │                                                            Streams output line-by-line
    │                                                            via Send-ProgressInfo
    │
    └─ Write-Information ◄────────────────────────────────────── Each output line received
```

## License

MIT — see [LICENSE](LICENSE).
