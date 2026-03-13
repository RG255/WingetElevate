# WingetElevate.psm1
#
# Transparent winget elevation wrapper for non-admin users on Windows.
# Routes all winget commands through a persistent elevated NamedPipe session.
# On first use per PS session, a single UAC prompt opens the elevated session.
# Subsequent calls reuse the session with no further prompts.
#
# Requires: NamedPipe module v0.6 or later

$script:WingetPipeInfo = $null
$script:WingetSRP      = $null
$script:WingetExe      = $null

function winget {
    <#
    .SYNOPSIS
        Transparent winget elevation wrapper for non-admin users.

    .DESCRIPTION
        Workaround for winget error 0x80070005 (Access is denied) on standard user
        accounts. Routes winget commands through an elevated NamedPipe session,
        presenting a single UAC prompt on first use per PowerShell session.

        Output is streamed line-by-line as winget runs. Note: winget progress
        indicators (spinners, download bars) use carriage-return overwriting and
        will appear as individual lines rather than in-place animations.

        --accept-source-agreements is appended automatically by default. To suppress
        it for a single call, use -NoAcceptSourceAgreements.

    .PARAMETER ArgList
        Arguments to pass to winget (all standard winget commands and flags).

    .PARAMETER NoAcceptSourceAgreements
        Suppress the automatic --accept-source-agreements flag for this call.

    .EXAMPLE
        winget list
        winget upgrade --all
        winget install 7zip.7zip
        winget search firefox -NoAcceptSourceAgreements
    #>
    param(
        [Parameter(ValueFromRemainingArguments)][string[]]$ArgList,
        [switch]$NoAcceptSourceAgreements
    )

    if (-not (Get-Module NamedPipe -ErrorAction SilentlyContinue)) {
        Import-Module NamedPipe -RequiredVersion 0.6 -ErrorAction Stop
    }

    if (-not $script:WingetPipeInfo -or -not (Test-PipeSession -PipeInfo $script:WingetPipeInfo)) {
        Write-Host 'Opening elevated winget session (one-time UAC prompt)...' -ForegroundColor Cyan
        $Session = Start-PipeSession -MyParameters @{ Action = 'Invoke' } -Options @{
            AdminRequired = $true
            WindowStyle   = 'Hidden'
            InfoDisplay   = 0
        }
        $script:WingetPipeInfo = $Session.'ServerClientParams'.'PipeInfo'
        $script:WingetSRP      = $Session.'SendRequestParams'

        # Register cleanup on PS exit using captured locals so the handler is
        # self-contained and works correctly with multiple concurrent pipe sessions.
        $captured_PipeInfo = $script:WingetPipeInfo
        $captured_SRP      = $script:WingetSRP
        Register-EngineEvent PowerShell.Exiting -SupportEvent -Action {
            if ($captured_PipeInfo -and $captured_SRP) {
                NamedPipe\Stop-PipeSession -SendRequestParams $captured_SRP -PipeInfo $captured_PipeInfo
            }
        } | Out-Null
    }

    # Locate the real winget.exe via registry (works PS5 + PS7, no Appx module needed).
    # The AppX alias stub at %LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe spawns the
    # real winget as a child process that does not inherit redirected stdout handles,
    # so output capture requires the real executable path.
    if (-not $script:WingetExe) {
        $pkgBase = 'HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages'
        $pkg = Get-ChildItem $pkgBase -ErrorAction SilentlyContinue |
               Where-Object { $_.PSChildName -like 'Microsoft.DesktopAppInstaller_*' } |
               Sort-Object PSChildName -Descending |
               Select-Object -First 1
        $script:WingetExe = if ($pkg) {
            $installPath = (Get-ItemProperty $pkg.PSPath -ErrorAction SilentlyContinue).Path
            if ($installPath) { Join-Path $installPath 'winget.exe' } else { $null }
        }
        if (-not $script:WingetExe) {
            $script:WingetExe = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
        }
    }

    $extraArgs = if ($NoAcceptSourceAgreements) { @() } else { @('--accept-source-agreements') }
    $safeExe   = $script:WingetExe -replace "'", "''"
    $safeArgs  = (($ArgList + $extraArgs) -join ' ') -replace "'", "''"

    # The elevated server locates the real winget.exe in WindowsApps (admin access required)
    # and streams each output line back to the client via Send-ProgressInfo.
    $cmd  = "`$wx = (Get-ChildItem 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName); "
    $cmd += "if (-not `$wx) { `$wx = '$safeExe' }; "
    $cmd += "`$psi = [System.Diagnostics.ProcessStartInfo]::new(`$wx); "
    $cmd += "`$psi.Arguments = '$safeArgs'; "
    $cmd += "`$psi.RedirectStandardOutput = `$true; `$psi.RedirectStandardError = `$true; `$psi.UseShellExecute = `$false; "
    $cmd += "`$p = [System.Diagnostics.Process]::Start(`$psi); "
    $cmd += "while (-not `$p.StandardOutput.EndOfStream) { `$line = `$p.StandardOutput.ReadLine(); if (`$line.Trim()) { Send-ProgressInfo -String `$line -Type 'Console' } }; "
    $cmd += "`$p.WaitForExit(); "
    $cmd += "`$p.StandardError.ReadToEnd() -split [Environment]::NewLine | Where-Object { `$_.Trim() } | ForEach-Object { Send-ProgressInfo -String `$_ -Type 'Console' }"

    $SRP = $script:WingetSRP
    $SRP.DataObject = $cmd | Send-Request @SRP

    if ($SRP.DataObject.Error) { Write-Error $SRP.DataObject.Error }
}
