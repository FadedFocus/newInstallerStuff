# PC Bootstrap

PC Bootstrap sets up a clean Windows 11 installation with a personal group of
applications. The GitHub launcher installs Git if needed, clones this repository,
and runs the installer. Later launches update the existing checkout first, so the
newest committed version is used automatically.

## Applications

- Discord (`Discord.Discord`)
- Mozilla Firefox (`Mozilla.Firefox`)
- Opera GX (`Opera.OperaGX`)
- Steam (`Valve.Steam`)
- 7-Zip (`7zip.7zip`)

## One-command setup on a clean PC

This workflow requires a **public** repository so a new PC can retrieve the
launcher before GitHub authentication has been configured.

1. Open Windows Terminal or Windows PowerShell as your normal user.
2. Paste the command below and press Enter.
3. Approve the administrator prompt when it appears.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-RestMethod 'https://raw.githubusercontent.com/FadedFocus/newInstallerStuff/main/Bootstrap.ps1' | Invoke-Expression"
```

The launcher performs this sequence:

1. Locates WinGet, which is included with current Windows 11 installations.
2. Installs Git through WinGet if Git is missing.
3. Clones this repository into
   `%LOCALAPPDATA%\PCBootstrap\Repository`, creating the `origin` connection.
4. On later runs, fetches and fast-forwards the local checkout from `main`.
5. Runs `Install-Apps.ps1` from the checkout.

No GitHub sign-in is needed to clone a public repository. A private repository
cannot provide the same zero-login first-run experience: the PC must authenticate
with GitHub before it can read either the launcher or the installer. Never put a
GitHub access token inside these scripts.

## Windows 11 installation USB

The same USB drive can hold both the official Windows 11 installation media and
the PC Bootstrap launcher.

1. Let Microsoft's Media Creation Tool finish creating the Windows 11 USB first.
   It formats the drive, so anything copied beforehand would be erased.
2. Copy `Start-PC-Bootstrap.cmd` to the root of the finished USB drive. Do not
   alter or remove the Windows setup files and folders.
3. Install Windows normally and finish the initial Windows setup until the normal
   desktop appears.
4. Connect the PC to the internet, open the USB drive in File Explorer, and
   double-click `Start-PC-Bootstrap.cmd`.
5. Approve the administrator prompt when it appears.

The USB launcher downloads the latest `Bootstrap.ps1` from this repository each
time, so the USB copy does not become stale when the installer changes. Do not
run it from the Windows Setup command prompt: the setup environment does not
reliably provide WinGet or the normal user profile that this installer needs.

Recreating the Windows installation media formats the USB again. Copy
`Start-PC-Bootstrap.cmd` back to the drive afterward.

## Publishing this folder

Create an empty GitHub repository named `newInstallerStuff`, then run the following
from this folder:

```powershell
git init -b main
git add .
git commit -m "Initial PC bootstrap"
git remote add origin https://github.com/FadedFocus/newInstallerStuff.git
git push -u origin main
```

GitHub may open a browser so Git Credential Manager can authenticate the first
push. The generated ZIP bundle is excluded from Git because the repository itself
is now the source of truth.

## Local launch

`Run-Setup.bat` remains available for launching a copy that is already on disk.
Keep it beside `Install-Apps.ps1`, double-click it, and approve the administrator
prompt.

## Installation behavior

- Applications install silently through WinGet.
- Already-installed packages are skipped rather than upgraded.
- A temporary scheduled task resumes setup after an unexpected restart.
- A successful run schedules one final Windows restart after 15 seconds.
- A failed run does not restart the computer automatically.

Logs and the latest result are stored here:

```text
C:\ProgramData\PCBootstrap\install.log
C:\ProgramData\PCBootstrap\last-run.txt
```

Set `$RestartAfterSuccessfulInstall = $false` in `Install-Apps.ps1` if the final
automatic restart is not wanted.
