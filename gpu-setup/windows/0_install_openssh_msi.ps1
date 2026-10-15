# Fast OpenSSH Server install: downloads the official MSI from GitHub (PowerShell/Win32-OpenSSH)
# instead of the slow "Add-WindowsCapability" download from Windows Update.
#
# Run in PowerShell **as Administrator**:
#   powershell -ExecutionPolicy Bypass -File .\0_install_openssh_msi.ps1
#
# If you already downloaded the .msi with a browser, pass it in to skip the download:
#   powershell -ExecutionPolicy Bypass -File .\0_install_openssh_msi.ps1 -MsiPath "$env:USERPROFILE\Downloads\OpenSSH-Win64-v10.0.0.0.msi"
#
# Afterwards run 2_setup_ssh.ps1 as usual; it sees sshd is installed and skips the slow step.

param([string]$MsiPath = "")
$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script in PowerShell as Administrator."
    exit 1
}

if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Write-Host "sshd is already installed. Nothing to do - go on to 2_setup_ssh.ps1."
    exit 0
}

# Known-good fallback (latest release as of 2026-10)
$fallbackUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi"

if (-not $MsiPath) {
    $url = $fallbackUrl
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest" -TimeoutSec 15
        $asset = $rel.assets | Where-Object { $_.name -match '^OpenSSH-Win64-v[\d\.]+\.msi$' } | Select-Object -First 1
        if ($asset) { $url = $asset.browser_download_url }
    } catch {
        Write-Host "Could not query GitHub API, using the known release link."
    }
    $MsiPath = Join-Path $env:TEMP (Split-Path $url -Leaf)
    Write-Host "Downloading $url"
    # curl.exe ships with Windows 10/11, shows progress and is much faster than Invoke-WebRequest
    & "$env:WINDIR\System32\curl.exe" -L --fail --retry 3 -o $MsiPath $url
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Download failed. Open the link above in a browser (or download it on another computer), then rerun with -MsiPath <file>."
        exit 1
    }
}

if (-not (Test-Path $MsiPath)) { Write-Error "File not found: $MsiPath"; exit 1 }

Write-Host "Installing OpenSSH Server from $MsiPath ..."
$p = Start-Process msiexec.exe -ArgumentList @('/i', "`"$MsiPath`"", 'ADDLOCAL=Server', '/passive', '/norestart') -Wait -PassThru
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Write-Error "msiexec failed with exit code $($p.ExitCode)"; exit 1 }

if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    Write-Host "Done. sshd installed. Next: run 2_setup_ssh.ps1 -PubKey `"...`""
} else {
    Write-Error "Install finished but the sshd service was not found."
}
