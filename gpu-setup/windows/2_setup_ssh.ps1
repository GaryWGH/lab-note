# Run in PowerShell **as Administrator** (right-click Start > Terminal (Admin)):
#
#   powershell -ExecutionPolicy Bypass -File .\2_setup_ssh.ps1 -PubKey "ssh-ed25519 AAAA... you@mac"
#
# The value of -PubKey is the content of ~/.ssh/id_ed25519.pub on your Mac.
# Safe to run again (e.g. to add another key).
#
# What it does:
#   1. Install and start OpenSSH Server (auto-start on boot)
#   2. Allow port 22 in the firewall
#   3. Make SSH logins land directly in WSL (Ubuntu) bash
#   4. Install your Mac's public key (key login only, no password typing)
#   5. Never sleep while plugged in
#   6. WSL keep-alive task, so background jobs (tmux) survive after SSH disconnects
#      (skip with -NoKeepAlive)
# No Claude product is installed or logged in on this machine.

param(
    [Parameter(Mandatory = $true)][string]$PubKey,
    [switch]$NoKeepAlive
)
$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script in PowerShell as Administrator."
    exit 1
}
$PubKey = $PubKey.Trim()
if ($PubKey -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-\S+) ') {
    Write-Error "-PubKey does not look like an SSH public key (it should start with ssh-ed25519)."
    exit 1
}

Write-Host "[1/6] Installing OpenSSH Server..."
if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
    # Already installed (via Optional features or the GitHub MSI) - skip the slow Windows Update download
    Write-Host "      sshd already installed, skipping."
} else {
    Write-Host "      Downloading from Windows Update, this can take 5-20 minutes..."
    $cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*' | Select-Object -First 1
    Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

Write-Host "[2/6] Firewall rule for port 22..."
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}

Write-Host "[3/6] SSH logins go straight into WSL..."
$bash = Join-Path $env:WINDIR 'System32\bash.exe'
$shell = if (Test-Path $bash) { $bash } else { Join-Path $env:WINDIR 'System32\wsl.exe' }
if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) { New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null }
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $shell -PropertyType String -Force | Out-Null
Write-Host "      DefaultShell = $shell"

Write-Host "[4/6] Installing your Mac's public key..."
function Add-Key([string]$path) {
    $dir = Split-Path $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $existing = if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { "" }
    if (-not $existing.Contains($PubKey)) {
        if ($existing -and -not $existing.EndsWith("`n")) { $existing += "`n" }
        # sshd needs UTF-8 without BOM (not UTF-16)
        [IO.File]::WriteAllText($path, $existing + $PubKey + "`n", (New-Object Text.UTF8Encoding($false)))
    }
}
# Admin accounts read this file instead of ~/.ssh/authorized_keys
$adminKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
Add-Key $adminKeys
icacls $adminKeys /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null
# Non-admin accounts read this one
Add-Key (Join-Path $env:USERPROFILE '.ssh\authorized_keys')
Restart-Service sshd

Write-Host "[5/6] Never sleep while plugged in..."
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0

if (-not $NoKeepAlive) {
    Write-Host "[6/6] WSL keep-alive task (runs hidden at logon)..."
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoProfile -WindowStyle Hidden -Command "wsl.exe --exec /bin/sleep infinity"'
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'WSL keep-alive' -Action $action -Trigger $trigger `
        -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName 'WSL keep-alive'
} else {
    Write-Host "[6/6] Skipped WSL keep-alive."
}

Write-Host ""
Write-Host "Done. Put these into ~/.ssh/config on your Mac:"
Write-Host "  User     $env:USERNAME"
Write-Host "  HostName one of these IPs (use the one on the same network as your Mac):"
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notlike 'vEthernet*' } |
    ForEach-Object { Write-Host "           $($_.IPAddress)   ($($_.InterfaceAlias))" }
