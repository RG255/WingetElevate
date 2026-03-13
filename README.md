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
- Output is streamed line-by-line as winget runs.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.0 or later (PowerShell 7.x also supported)
- [NamedPipe](https://github.com/RG255/NamedPipe) module v0.6 or later
- Your user account must be able to elevate via UAC

## Installation

1. Install the [NamedPipe](https://github.com/RG255/NamedPipe) module v0.6 or later.

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
```

On first use per session you will see a UAC prompt to open the elevated session.
After approving, all winget commands run without further prompts.

## Versions

| Version | Notes |
|---------|-------|
| [0.1](0.1/README.md) | Initial release |

## License

MIT — see [LICENSE](0.1/LICENSE).
