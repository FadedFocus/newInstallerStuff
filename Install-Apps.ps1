#requires -Version 5.1

<#
PC Bootstrap - Windows 11 application installer

Normal user experience:
  1. Double-click Run-Setup.bat.
  2. Accept one UAC prompt if elevation is required.
  3. Applications install silently in the background.
  4. If everything succeeds, Windows restarts once at the end.

Recovery behavior:
  - The script registers a temporary scheduled task before installing apps.
  - If Windows restarts unexpectedly during setup, the task resumes setup at the
    next logon with highest privileges.
  - Re-running is safe because WinGet is instructed not to upgrade packages that
    are already installed.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# -----------------------------
# User-editable configuration
# -----------------------------
$RestartAfterSuccessfulInstall = $true

$Apps = @(
    [PSCustomObject]@{
        Name         = 'Discord'
        Id           = 'Discord.Discord'
        ProcessNames = @('Discord')
    },
    [PSCustomObject]@{
        Name         = 'Mozilla Firefox'
        Id           = 'Mozilla.Firefox'
        ProcessNames = @('firefox')
    },
    [PSCustomObject]@{
        Name         = 'Opera GX'
        Id           = 'Opera.OperaGX'
        ProcessNames = @('opera', 'opera_crashreporter')
    },
    [PSCustomObject]@{
        Name         = 'Steam'
        Id           = 'Valve.Steam'
        ProcessNames = @('steam', 'steamwebhelper')
    },
    [PSCustomObject]@{
        Name         = '7-Zip'
        Id           = '7zip.7zip'
        ProcessNames = @('7zFM')
    }
)

$TaskName = 'PCBootstrap-Resume'
$WorkDir = Join-Path $env:ProgramData 'PCBootstrap'
$PersistentScript = Join-Path $WorkDir 'Install-Apps.ps1'
$LogPath = Join-Path $WorkDir 'install.log'
$ResultPath = Join-Path $WorkDir 'last-run.txt'

# Current WinGet return code for "package already installed".
$WingetPackageAlreadyInstalled = -1978335135

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WingetPath {
    $command = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }
    return $null
}

function Request-WingetRegistration {
    # On a brand-new Windows profile, WinGet registration can still be pending.
    # Microsoft documents this registration command for that scenario.
    try {
        Add-AppxPackage -RegisterByFamilyName `
            -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' `
            -ErrorAction Stop
        Start-Sleep -Seconds 2
    }
    catch {
        # We handle the missing-WinGet condition explicitly below.
    }
}

function Show-SetupMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    try {
        & "$env:SystemRoot\System32\msg.exe" * $Message | Out-Null
    }
    catch {
        # Do not allow an error notification failure to crash cleanup logic.
    }
}

# Do the WinGet registration check before elevation so App Installer is
# registered for the interactive user rather than a different account context.
$WingetPath = Get-WingetPath
if (-not $WingetPath) {
    Request-WingetRegistration
    $WingetPath = Get-WingetPath
}

if (-not $WingetPath) {
    Show-SetupMessage 'PC Bootstrap could not find Windows Package Manager (WinGet). Make sure App Installer is installed, then run setup again.'
    exit 2
}

# Elevate only once. The UAC prompt is the only expected user interaction.
if (-not (Test-IsAdministrator)) {
    $PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""

    try {
        Start-Process -FilePath $PowerShellExe `
            -ArgumentList $Arguments `
            -Verb RunAs `
            -WindowStyle Hidden | Out-Null
        exit 0
    }
    catch {
        Show-SetupMessage 'PC Bootstrap requires administrator approval to install machine-wide applications.'
        exit 5
    }
}

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value "[$Timestamp] [$Level] $Message" -Encoding UTF8
}

function Register-ResumeTask {
    Copy-Item -LiteralPath $PSCommandPath -Destination $PersistentScript -Force

    $PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $TaskArguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PersistentScript`""
    $UserId = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    $Action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $TaskArguments
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
    $Principal = New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Force | Out-Null

    Write-Log "Resume task registered for $UserId."
}

function Remove-ResumeTask {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log 'Resume task removed.'
    }
    catch {
        Write-Log "Could not remove resume task: $($_.Exception.Message)" 'WARN'
    }
}

function Get-ProcessSnapshot {
    param([string[]]$ProcessNames)

    $Ids = @{}
    foreach ($ProcessName in $ProcessNames) {
        $Processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        foreach ($Process in $Processes) {
            $Ids[$Process.Id] = $true
        }
    }
    return $Ids
}

function Stop-NewAppProcesses {
    param(
        [string[]]$ProcessNames,
        [hashtable]$BeforeSnapshot
    )

    foreach ($ProcessName in $ProcessNames) {
        $Processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        foreach ($Process in $Processes) {
            if (-not $BeforeSnapshot.ContainsKey($Process.Id)) {
                try {
                    Stop-Process -Id $Process.Id -Force -ErrorAction Stop
                    Write-Log "Closed process launched during installation: $($Process.ProcessName) (PID $($Process.Id))."
                }
                catch {
                    Write-Log "Could not close $($Process.ProcessName) (PID $($Process.Id)): $($_.Exception.Message)" 'WARN'
                }
            }
        }
    }
}

function Install-App {
    param(
        [Parameter(Mandatory = $true)]$App,
        [Parameter(Mandatory = $true)][string]$WingetExecutable
    )

    Write-Log "Starting $($App.Name) [$($App.Id)]."
    $BeforeProcesses = Get-ProcessSnapshot -ProcessNames $App.ProcessNames

    $Arguments = @(
        'install',
        '--id', $App.Id,
        '--exact',
        '--source', 'winget',
        '--silent',
        '--disable-interactivity',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--no-upgrade'
    )

    $Output = & $WingetExecutable @Arguments 2>&1
    $ExitCode = $LASTEXITCODE

    foreach ($Line in $Output) {
        if ($null -ne $Line) {
            Write-Log "[$($App.Name)] $($Line.ToString())"
        }
    }

    Stop-NewAppProcesses -ProcessNames $App.ProcessNames -BeforeSnapshot $BeforeProcesses

    if (($ExitCode -eq 0) -or ($ExitCode -eq $WingetPackageAlreadyInstalled)) {
        if ($ExitCode -eq $WingetPackageAlreadyInstalled) {
            Write-Log "$($App.Name) is already installed; skipping."
        }
        else {
            Write-Log "$($App.Name) installed successfully."
        }
        return $true
    }

    Write-Log "$($App.Name) failed with WinGet exit code $ExitCode." 'ERROR'
    return $false
}

$Mutex = $null
$OwnsMutex = $false

try {
    $CreatedNew = $false
    $Mutex = [System.Threading.Mutex]::new($true, 'Global\PCBootstrapInstaller', [ref]$CreatedNew)
    $OwnsMutex = $CreatedNew

    if (-not $OwnsMutex) {
        Write-Log 'Another PC Bootstrap instance is already running. Exiting.' 'WARN'
        exit 0
    }

    Write-Log '============================================================'
    Write-Log 'PC Bootstrap started.'
    Write-Log "Script source: $PSCommandPath"

    # Resolve WinGet again in the elevated process.
    $WingetPath = Get-WingetPath
    if (-not $WingetPath) {
        Write-Log 'WinGet disappeared after elevation; setup cannot continue.' 'ERROR'
        Show-SetupMessage 'PC Bootstrap could not start WinGet after elevation. See C:\ProgramData\PCBootstrap\install.log.'
        exit 2
    }

    Register-ResumeTask

    $FailedApps = New-Object System.Collections.Generic.List[string]

    foreach ($App in $Apps) {
        try {
            $Installed = Install-App -App $App -WingetExecutable $WingetPath
            if (-not $Installed) {
                $FailedApps.Add($App.Name)
            }
        }
        catch {
            $FailedApps.Add($App.Name)
            Write-Log "$($App.Name) threw an unexpected error: $($_.Exception.Message)" 'ERROR'
        }
    }

    if ($FailedApps.Count -gt 0) {
        $FailureText = 'Failed applications: ' + ($FailedApps -join ', ')
        Set-Content -Path $ResultPath -Value $FailureText -Encoding UTF8
        Write-Log $FailureText 'ERROR'
        Write-Log 'Setup completed with errors. The computer will not restart automatically.' 'ERROR'
        Remove-ResumeTask
        Show-SetupMessage "PC Bootstrap finished with errors. See $ResultPath and $LogPath."
        exit 1
    }

    Set-Content -Path $ResultPath -Value 'All configured applications installed successfully.' -Encoding UTF8
    Write-Log 'All configured applications completed successfully.'
    Remove-ResumeTask

    if ($RestartAfterSuccessfulInstall) {
        Write-Log 'Scheduling one final Windows restart in 15 seconds.'
        & "$env:SystemRoot\System32\shutdown.exe" /r /t 15 /c 'PC Bootstrap finished installing applications.' /d p:0:0 | Out-Null
    }
    else {
        Write-Log 'Automatic final restart is disabled by configuration.'
    }
}
catch {
    Write-Log "Fatal setup error: $($_.Exception.Message)" 'ERROR'
    Show-SetupMessage "PC Bootstrap stopped because of an unexpected error. See $LogPath."
    exit 1
}
finally {
    if (($null -ne $Mutex) -and $OwnsMutex) {
        try {
            $Mutex.ReleaseMutex()
        }
        catch {
        }
        $Mutex.Dispose()
    }
}
