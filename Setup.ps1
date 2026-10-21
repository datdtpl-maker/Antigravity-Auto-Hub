# ==============================================================================
# ANTIGRAVITY AUTO-HUB - 1-CLICK INSTALLER & PORTABLE SETUP
# ==============================================================================
param([switch]$ConfigureOnly)
$ErrorActionPreference = 'Stop'
$baseDir = $PSScriptRoot
if (-not $baseDir) { $baseDir = (Get-Location).Path }
. (Join-Path $baseDir 'OAuthSetup.ps1')

try {
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "   CAI DAT ANTIGRAVITY AUTO-ROTATION HUB (WINDOWS PORTABLE)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[1/5] Kiem tra Antigravity va thu muc cai dat: $baseDir" -ForegroundColor Yellow

$accDir = Join-Path $baseDir "accounts"
if (-not (Test-Path $accDir)) {
    New-Item -ItemType Directory -Path $accDir -Force | Out-Null
}

$antigravityExe = "$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe"
$hasIde = Test-Path $antigravityExe
if (-not $hasIde) { throw 'SetupAntigravityMissing' }
. (Join-Path $baseDir 'AutoRotator.ps1')
try { Assert-AntigravityVersion (Get-Item -LiteralPath $antigravityExe).VersionInfo.ProductVersion $antigravityExe }
catch { throw 'SetupAntigravityUnsupported' }

Write-Host "[2/5] Tu dong cau hinh va xac minh OAuth (khong can nhap secret)..." -ForegroundColor Yellow
$setupLock=[Threading.Mutex]::new($false, 'Local\AntigravityAutoHub.Switch')
$setupLocked=$false
try {
    try { $setupLocked=$setupLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $setupLocked=$true }
    if (-not $setupLocked) { throw 'SetupBusy' }
    $oauthResult=Initialize-HubOAuth $baseDir (Join-Path (Split-Path $antigravityExe) 'resources\bin\language_server.exe') $geminiTokenPath
    Write-Host "      -> Da xac minh OAuth voi Google va luu cau hinh cho may nay ($($oauthResult.Source))." -ForegroundColor Green
} finally {
    if ($setupLocked) { $setupLock.ReleaseMutex() }
    $setupLock.Dispose()
}
if ($ConfigureOnly) {
    Write-Host 'Da cau hinh OAuth. Che do ConfigureOnly khong tao shortcut hoac khoi chay Hub/daemon.'
    exit 0
}

# 2. Create Desktop Shortcut
Write-Host "[3/5] Tao Shortcut ngoai Desktop..." -ForegroundColor Yellow
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
Write-Host "[4/5] Cai dat tu dong chay ngam cung Windows Startup..." -ForegroundColor Yellow
$startupPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup)
$startupLnk = Join-Path $startupPath "AntigravityAutoRotator.lnk"

$rotatorScript = Join-Path $baseDir "AutoRotator.ps1"
$sShortcut = $wsh.CreateShortcut($startupLnk)
$sShortcut.TargetPath = "wscript.exe"
$sShortcut.Arguments = """$(Join-Path $baseDir 'launch-rotator-daemon.vbs')"""
$sShortcut.WorkingDirectory = $baseDir
$sShortcut.Description = "Antigravity Auto-Rotator Daemon Service"
if ($hasIde) {
    $sShortcut.IconLocation = "$antigravityExe,0"
}
$sShortcut.Save()
Write-Host "      -> Da dang ky daemon khoi dong cung Windows" -ForegroundColor Green

# 4. Start Background Daemon & Open GUI
Write-Host "[5/5] Khoi chay Background Daemon va mo Dashboard..." -ForegroundColor Yellow

$procs = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { $_.CommandLine -like '*AutoRotator.ps1*' -and $_.CommandLine -match '(?i)\s-Daemon(?:\s|$)' })
if ($procs.Count -eq 0) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""$rotatorScript"" -Daemon -IntervalSeconds 25"
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Write-Host "      -> Daemon da duoc khoi chay ngam thanh cong." -ForegroundColor Green
} else {
    Write-Host "      -> Daemon da dang chay ngam san sang (PID: $($procs[0].ProcessId))." -ForegroundColor Green
    Write-Host "      -> Neu daemon/Hub duoc mo truoc khi sua cau hinh, hay luu cong viec va khoi dong lai Windows de nap lai."
}

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host "   CAI DAT HOAN TAT - OAUTH DA XAC MINH. DANG MO HUB..." -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

Start-Process "wscript.exe" """$vbsPath""" -WindowStyle Hidden
Write-Host 'Trong Hub: Luu acc hien tai -> Quet quota. Xac minh OAuth chua phai kiem tra quota/quyen su dung Antigravity.'
} catch {
    $setupFailure=$_.Exception.Message
    Write-Host ''
    Write-Host 'CAI DAT CHUA HOAN TAT' -ForegroundColor Red
    Write-Host (Get-OAuthSetupFailureMessage $setupFailure) -ForegroundColor Yellow
    # Codes are an allowlist, never raw exception text or provider responses.
    if ($setupFailure -in @('SetupOAuthNetwork','SetupOAuthDns','SetupOAuthProxy','SetupOAuthTls','SetupOAuthTimeout','SetupOAuthRateLimited','SetupOAuthServer','SetupOAuthRejected','SetupOAuthNoMatch','SetupOAuthEnvironmentInvalid','SetupOAuthLoginRequired','SetupOAuthUnsupported','SetupOAuthSaveFailed','SetupOAuthInvalidResponse','SetupAntigravityMissing','SetupAntigravityUnsupported','SetupBusy')) {
        Write-Host "Ma chan doan: $setupFailure"
    }
    exit 1
}
