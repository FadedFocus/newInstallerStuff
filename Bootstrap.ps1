#requires -Version 5.1

<#
PC Bootstrap - GitHub launcher

This is the only file fetched directly on a clean Windows 11 installation.
It installs Git when necessary, clones or updates the configured repository,
and starts Install-Apps.ps1 from that Git checkout.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$RepositoryUrl = 'https://github.com/FadedFocus/newInstallerStuff.git'
$RepositoryBranch = 'main'
$CheckoutPath = Join-Path $env:LOCALAPPDATA 'PCBootstrap\Repository'

# These overrides are useful for testing and advanced use. Normal users do not
# need to set them.
if ($env:PC_BOOTSTRAP_REPOSITORY_URL) {
    $RepositoryUrl = $env:PC_BOOTSTRAP_REPOSITORY_URL
}
if ($env:PC_BOOTSTRAP_REPOSITORY_BRANCH) {
    $RepositoryBranch = $env:PC_BOOTSTRAP_REPOSITORY_BRANCH
}
if ($env:PC_BOOTSTRAP_CHECKOUT_PATH) {
    $CheckoutPath = $env:PC_BOOTSTRAP_CHECKOUT_PATH
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[PC Bootstrap] $Message" -ForegroundColor Cyan
}

function Get-WingetPath {
    $Command = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    # App Installer can be present but not registered yet on a new profile.
    try {
        Add-AppxPackage -RegisterByFamilyName `
            -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' `
            -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 2
    }
    catch {
        # The explicit missing-WinGet error below is more useful to the user.
    }

    $Command = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    return $null
}

function Get-GitPath {
    $Command = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    $Candidates = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )

    if (${env:ProgramFiles(x86)}) {
        $Candidates += Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe'
    }

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return $Candidate
        }
    }

    return $null
}

function Install-Git {
    $WingetPath = Get-WingetPath
    if (-not $WingetPath) {
        throw 'Windows Package Manager (WinGet) is unavailable. Install or update App Installer from Microsoft Store, then try again.'
    }

    Write-Step 'Git is not installed. Installing it with WinGet...'

    $WingetOutput = @(& $WingetPath install `
        --id 'Git.Git' `
        --exact `
        --source 'winget' `
        --silent `
        --disable-interactivity `
        --accept-package-agreements `
        --accept-source-agreements 2>&1)

    $WingetExitCode = $LASTEXITCODE

    # Native command output is part of a PowerShell function's output stream
    # unless it is consumed. Keep WinGet's messages visible without allowing
    # them to become part of the Git path returned by this function.
    foreach ($Line in $WingetOutput) {
        if ($null -ne $Line) {
            Write-Host $Line.ToString()
        }
    }

    [string]$GitPath = Get-GitPath

    if (-not $GitPath) {
        throw "Git installation failed or Git could not be located. WinGet exit code: $WingetExitCode"
    }

    return $GitPath
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$GitPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    & $GitPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed with exit code ${LASTEXITCODE}: git $($Arguments -join ' ')"
    }
}

try {
    $GitPath = Get-GitPath
    if (-not $GitPath) {
        $GitPath = Install-Git
    }
    else {
        Write-Step "Using Git at $GitPath"
    }

    $CheckoutParent = Split-Path -Parent $CheckoutPath
    New-Item -ItemType Directory -Path $CheckoutParent -Force | Out-Null

    if (Test-Path -LiteralPath $CheckoutPath) {
        $GitMetadataPath = Join-Path $CheckoutPath '.git'
        if (-not (Test-Path -LiteralPath $GitMetadataPath)) {
            throw "The checkout path already exists but is not a Git repository: $CheckoutPath"
        }

        Write-Step 'Updating the existing Git checkout...'
        Invoke-Git -GitPath $GitPath -Arguments @(
            '-C', $CheckoutPath, 'fetch', '--prune', 'origin', $RepositoryBranch
        )
        Invoke-Git -GitPath $GitPath -Arguments @(
            '-C', $CheckoutPath, 'checkout', $RepositoryBranch
        )
        Invoke-Git -GitPath $GitPath -Arguments @(
            '-C', $CheckoutPath, 'pull', '--ff-only', 'origin', $RepositoryBranch
        )
    }
    else {
        Write-Step 'Cloning the installer from GitHub...'
        Invoke-Git -GitPath $GitPath -Arguments @(
            'clone', '--branch', $RepositoryBranch, '--single-branch',
            $RepositoryUrl, $CheckoutPath
        )
    }

    $InstallerPath = Join-Path $CheckoutPath 'Install-Apps.ps1'
    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
        throw "Install-Apps.ps1 was not found in the repository checkout: $InstallerPath"
    }

    Write-Step 'Starting the application installer. Approve the Windows administrator prompt when it appears.'
    $PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $PowerShellExe `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $InstallerPath

    if ($LASTEXITCODE -ne 0) {
        throw "The application installer exited with code $LASTEXITCODE."
    }
}
catch {
    Write-Host ''
    Write-Host "PC Bootstrap could not continue: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'No automatic restart was requested by the GitHub launcher.' -ForegroundColor Yellow
    exit 1
}
