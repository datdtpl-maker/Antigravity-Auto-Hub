# ==============================================================================
# ANTIGRAVITY AUTO-HUB - 1-CLICK INSTALLER & PORTABLE SETUP
# ==============================================================================
$baseDir = $PSScriptRoot
if (-not $baseDir) { $baseDir = (Get-Location).Path }

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "   CAI DAT ANTIGRAVITY AUTO-ROTATION HUB (WINDOWS PORTABLE)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[1/4] Kiem tra thu muc cai dat: $baseDir" -ForegroundColor Yellow

$accDir = Join-Path $baseDir "accounts"
if (-not (Test-Path $accDir)) {
    New-Item -ItemType Directory -Path $accDir -Force | Out-Null
}

$antigravityExe = "$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe"
$hasIde = Test-Path $antigravityExe

# 2. Create Desktop Shortcut
Write-Host "[2/4] Tao Shortcut ngoai Desktop..." -ForegroundColor Yellow
$wsh = New-Object -ComObject WScript.Shell
$desktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$shortcutPath = Join-Path $desktopPath "Antigravity Auto-Hub.lnk"

$vbsPath = Join-Path $baseDir "launch-switcher.vbs"
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "wscript.exe"
$shortcut.Arguments = """$vbsPath"""
$shortcut.WorkingDirectory = $baseDir
$shortcut.Description = "Antigravity Multi-Account Hub & Auto-Quota Rotator"
if ($hasIde) {
    $shortcut.IconLocation = "$antigravityExe,0"
}
$shortcut.Save()
Write-Host "      -> Da tao shortcut: $shortcutPath" -ForegroundColor Green

# 3. Create Windows Startup Shortcut for Auto-Rotator Daemon
Write-Host "[3/4] Cai dat tu dong chay ngam cung Windows Startup..." -ForegroundColor Yellow
$startupPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup)
$startupLnk = Join-Path $startupPath "AntigravityAutoRotator.lnk"

$rotatorScript = Join-Path $baseDir "AutoRotator.ps1"
$sShortcut = $wsh.CreateShortcut($startupLnk)
$sShortcut.TargetPath = "powershell.exe"
$sShortcut.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""$rotatorScript"" -Daemon -IntervalSeconds 25"
$sShortcut.WorkingDirectory = $baseDir
$sShortcut.Description = "Antigravity Auto-Rotator Daemon Service"
if ($hasIde) {
    $sShortcut.IconLocation = "$antigravityExe,0"
}
$sShortcut.Save()
Write-Host "      -> Da dang ky service khoi dong cung Windows" -ForegroundColor Green

# 4. Start Background Daemon & Open GUI
Write-Host "[4/4] Khoi chay Background Daemon va mo Dashboard..." -ForegroundColor Yellow

$procs = Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%AutoRotator.ps1%Daemon%'" -ErrorAction SilentlyContinue
if ($procs.Count -eq 0) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""$rotatorScript"" -Daemon -IntervalSeconds 60"
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Write-Host "      -> Daemon da duoc khoi chay ngam thanh cong." -ForegroundColor Green
} else {
    Write-Host "      -> Daemon da dang chay ngam san sang (PID: $($procs[0].ProcessId))." -ForegroundColor Green
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host "   CAI DAT HOAN TAT 100%! DANG MO ANTIGRAVITY AUTO-HUB..." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

Start-Process "wscript.exe" """$vbsPath"""
