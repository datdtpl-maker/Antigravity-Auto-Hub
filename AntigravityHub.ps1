param([switch]$Preview, [switch]$NoShow)
if ($NoShow -and -not $Preview) { throw 'NoShow requires Preview.' }
# ==============================================================================
# ANTIGRAVITY MULTI-ACCOUNT HUB - 100% PURE ASCII UNICODE SAFE & PORTABLE
# ==============================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms, Microsoft.VisualBasic

$baseDir = $PSScriptRoot
if (-not $baseDir) { $baseDir = (Get-Location).Path }
$accDir = Join-Path $baseDir "accounts"
$activeFile = Join-Path $baseDir "current_active.txt"
$geminiTokenPath = Join-Path $env:USERPROFILE ".gemini\jetski-standalone-oauth-token"
$rotatorScript = Join-Path $baseDir "AutoRotator.ps1"
$xamlFile = Join-Path $baseDir "MainWindow.xaml"

if (-not (Test-Path $accDir)) {
    New-Item -ItemType Directory -Path $accDir -Force | Out-Null
}

if (-not $Preview) { . $rotatorScript }
. (Join-Path $baseDir 'Dashboard.ps1')
. (Join-Path $baseDir 'AccountLogin.ps1')

function Get-DaemonStatus {
    $procs = @(Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%AutoRotator.ps1%Daemon%'" -ErrorAction SilentlyContinue)
    return ($procs.Count -gt 0)
}

function Start-AutoRotatorDaemon {
    if (-not (Get-DaemonStatus)) {
        $vbs = Join-Path $baseDir "launch-rotator-daemon.vbs"
        if (Test-Path $vbs) {
            Start-Process "wscript.exe" -ArgumentList """$vbs"""
        } else {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""$rotatorScript"" -Daemon -IntervalSeconds 25"
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        }
    }
}

if (-not $Preview) { Start-AutoRotatorDaemon }

if (-not (Test-Path $xamlFile)) {
    Write-Error "Khong tim thay file MainWindow.xaml tai $xamlFile"
    exit 1
}

$xamlText = [System.IO.File]::ReadAllText($xamlFile, [System.Text.Encoding]::UTF8)
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlText))
$window = [System.Windows.Markup.XamlReader]::Load($reader)
$reader.Dispose()
$window.Width=[math]::Min($window.Width,[Windows.SystemParameters]::WorkArea.Width)
$window.Height=[math]::Min($window.Height,[Windows.SystemParameters]::WorkArea.Height)

$titleBar = $window.FindName("TitleBar")
$btnMinimize = $window.FindName("BtnMinimize")
$btnClose = $window.FindName("BtnClose")
$btnRefresh = $window.FindName("BtnRefresh")
$btnSaveCurrent = $window.FindName("BtnSaveCurrent")
$btnAddAccount = $window.FindName("BtnAddAccount")
$btnOpenFolder = $window.FindName("BtnOpenFolder")
$txtFooterPath = $window.FindName("TxtFooterPath")
$accountsContainer = $window.FindName("AccountsContainer")

if ($txtFooterPath) {
    $txtFooterPath.Text = "Th$([char]0x01B0) m$([char]0x1EE5)c l$([char]0x01B0)u tr$([char]0x1EEF): $baseDir"
}

$titleBar.Add_MouseLeftButtonDown({ param($sender,$event)
    if ($event.OriginalSource -is [Windows.Controls.Button]) { return }
    if ($event.ClickCount -eq 2) { Switch-HubWindowState } else { $window.DragMove() }
})
function Switch-HubWindowState {
    $window.WindowState=if($window.WindowState -eq 'Maximized'){'Normal'}else{'Maximized'}
}
$window.FindName('BtnMaximize').Add_Click({ Switch-HubWindowState })
$btnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$btnClose.Add_Click({ $window.Close() })
$btnOpenFolder.Add_Click({ Start-Process "explorer.exe" $baseDir })

$btnRefresh.Add_Click({ Load-Accounts-UI -Reconcile })

$btnSaveCurrent.Add_Click({
    if ($Preview) { return }
    $cred = [WinCred]::Read("gemini:antigravity")
    if (-not $cred -and (Test-Path $geminiTokenPath)) {
        $cred = [System.IO.File]::ReadAllText($geminiTokenPath, [System.Text.Encoding]::UTF8)
    }

    if (-not $cred) {
        [System.Windows.MessageBox]::Show("Kh$([char]0x00F4)ng t$([char]0x00EC)m th$([char]0x1EA5)y token $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p hi$([char]0x1EC7)n t$([char]0x1EA1)i trong Antigravity IDE.`nH$([char]0x00E3)y $([char]0x0111)$([char]0x1EA3)m b$([char]0x1EA3)o b$([char]0x1EA1)n $([char]0x0111)$([char]0x00E3) $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p Google tr$([char]0x00EA)n IDE.", "Th$([char]0x00F4)ng b$([char]0x00E1)o", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $email = ""
    try {
        $json = $cred | ConvertFrom-Json
        $refreshToken = Get-RefreshToken $json
        if ($refreshToken) {
            $fresh = Get-FreshToken $json
            $uinfo = Invoke-RestMethod -Uri "https://www.googleapis.com/oauth2/v3/userinfo" -Headers @{ Authorization = "Bearer $($fresh.token.access_token)" } -TimeoutSec 5
            $email = $uinfo.email
        }
    } catch {}

    $cleanName = if ($email) { $email.Split('@')[0] } else { "Acc_" + ((Get-ChildItem -Path $accDir -Filter "*.json" -ErrorAction SilentlyContinue).Count + 1) }

    $targetFile = Join-Path $accDir "$cleanName.json"
    [System.IO.File]::WriteAllText($targetFile, $cred, [System.Text.Encoding]::UTF8)
    
    Load-Accounts-UI
    $displayEmail = if ($email) { $email } else { $cleanName }
    [System.Windows.MessageBox]::Show("$([char]0x0110)$([char]0x00E3) t$([char]0x1EF1) $([char]0x0111)$([char]0x1ED9)ng nh$([char]0x1EAD)n di$([char]0x1EC7)n v$([char]0x00E0) l$([char]0x01B0)u t$([char]0x00E0)i kho$([char]0x1EA3)n: $displayEmail v$([char]0x00E0)o kho xoay tua th$([char]0x00E0)nh c$([char]0x00F4)ng!", "Th$([char]0x00E0)nh C$([char]0x00F4)ng", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
})

function Remove-LoginTempDirectory {
    param([string]$Path)
    if (-not $Path) { return }
    $resolved = [IO.Path]::GetFullPath($Path)
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^ag_login_[0-9]+$') { return }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}

function Complete-AccountLogin {
    if (-not $script:loginProtection) { return $true }
    $cleanupOk=$true
    try {
        if ($script:activeLoginTimer) { $script:activeLoginTimer.Stop() }
        if ($script:loginSession) { $script:loginSession.Dispose() }
        if ($script:loginSnapshotReady) {
            if ((Get-StoredCredential) -cne $script:loginOldCredential) {
                if ($script:loginOldCredential) { Restore-StoredCredential $script:loginOldCredential }
                elseif (-not [WinCred]::Delete('gemini:antigravity')) { throw 'LoginRestoreFailed' }
            }
            if ($null -ne $script:loginOldFallback) { Write-AtomicText $geminiTokenPath $script:loginOldFallback }
            elseif (Test-Path -LiteralPath $geminiTokenPath) { [IO.File]::Delete($geminiTokenPath) }
        }
        Remove-LoginTempDirectory $script:activeLoginTempDir
    } catch {
        $cleanupOk=$false
        Set-RotationState 'NeedsAttention'
        Write-RotatorLog 'Login cleanup requires verification; automatic rotation paused.'
    } finally {
        $script:loginProtection.ReleaseMutex()
        $script:loginProtection.Dispose()
        $script:loginProtection=$null; $script:loginSnapshotReady=$false
        $script:loginOldCredential=$null; $script:loginOldFallback=$null
        $script:loginSession=$null; $script:activeLoginTempDir=$null
        $accountsContainer.IsEnabled=$true; $btnAddAccount.IsEnabled=$true; $btnSaveCurrent.IsEnabled=$true
        $btnAddAccount.Content = "+ Th$([char]0x00EA)m T$([char]0x00E0)i Kho$([char]0x1EA3)n M$([char]0x1EDB)i"
    }
    return $cleanupOk
}

function Get-AccountLoginFailureMessage {
    param([string]$Code)
    $message = switch ($Code) {
        'LoginVerificationTimeout' { "$([char]0x0110)$([char]0x00E3) h$([char]0x1EBF)t 5 ph$([char]0x00FA)t ch$([char]0x1EDD) x$([char]0x00E1)c minh Google. Hub ch$([char]0x01B0)a l$([char]0x01B0)u t$([char]0x00E0)i kho$([char]0x1EA3)n. Ho$([char]0x00E0)n t$([char]0x1EA5)t y$([char]0x00EA)u c$([char]0x1EA7)u tr$([char]0x00EA)n trang x$([char]0x00E1)c minh r$([char]0x1ED3)i b$([char]0x1EA5)m Th$([char]0x00EA)m T$([char]0x00E0)i Kho$([char]0x1EA3)n M$([char]0x1EDB)i $([char]0x0111)$([char]0x1EC3) th$([char]0x1EED) l$([char]0x1EA1)i." }
        'LoginIneligible' { "Antigravity ch$([char]0x01B0)a x$([char]0x00E1)c nh$([char]0x1EAD)n phi$([char]0x00EA)n $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p n$([char]0x00E0)y (ineligible). Hub ch$([char]0x01B0)a l$([char]0x01B0)u t$([char]0x00E0)i kho$([char]0x1EA3)n v$([char]0x00E0) ch$([char]0x01B0)a nh$([char]0x1EAD)n $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c li$([char]0x00EA)n k$([char]0x1EBF)t x$([char]0x00E1)c minh $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c h$([char]0x1ED7) tr$([char]0x1EE3). H$([char]0x00E3)y ki$([char]0x1EC3)m tra th$([char]0x00F4)ng b$([char]0x00E1)o trong Antigravity ch$([char]0x00ED)nh th$([char]0x1EE9)c; m$([char]0x00E3) n$([char]0x00E0)y ch$([char]0x01B0)a x$([char]0x00E1)c $([char]0x0111)$([char]0x1ECB)nh $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c nguy$([char]0x00EA)n nh$([char]0x00E2)n c$([char]0x1EE5) th$([char]0x1EC3)." }
        'LoginVerificationRequired' { "Antigravity y$([char]0x00EA)u c$([char]0x1EA7)u x$([char]0x00E1)c minh th$([char]0x00EA)m t$([char]0x00E0)i kho$([char]0x1EA3)n. H$([char]0x00E3)y m$([char]0x1EDF) $([char]0x1EE9)ng d$([char]0x1EE5)ng Antigravity ch$([char]0x00ED)nh th$([char]0x1EE9)c, ho$([char]0x00E0)n t$([char]0x1EA5)t x$([char]0x00E1)c minh r$([char]0x1ED3)i th$([char]0x00EA)m l$([char]0x1EA1)i v$([char]0x00E0)o Hub. T$([char]0x00E0)i kho$([char]0x1EA3)n ch$([char]0x01B0)a $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c l$([char]0x01B0)u." }
        'LoginTermsRejected' { "Antigravity t$([char]0x1EEB) ch$([char]0x1ED1)i t$([char]0x00E0)i kho$([char]0x1EA3)n v$([char]0x1EDB)i tr$([char]0x1EA1)ng th$([char]0x00E1)i tosViolation. H$([char]0x00E3)y ki$([char]0x1EC3)m tra th$([char]0x00F4)ng b$([char]0x00E1)o trong $([char]0x1EE9)ng d$([char]0x1EE5)ng ch$([char]0x00ED)nh th$([char]0x1EE9)c ho$([char]0x1EB7)c li$([char]0x00EA)n h$([char]0x1EC7) h$([char]0x1ED7) tr$([char]0x1EE3) Antigravity. T$([char]0x00E0)i kho$([char]0x1EA3)n ch$([char]0x01B0)a $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c l$([char]0x01B0)u." }
        'LoginProviderError' { "Antigravity tr$([char]0x1EA3) v$([char]0x1EC1) l$([char]0x1ED7)i khi x$([char]0x00E1)c th$([char]0x1EF1)c t$([char]0x00E0)i kho$([char]0x1EA3)n. H$([char]0x00E3)y ki$([char]0x1EC3)m tra $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p trong $([char]0x1EE9)ng d$([char]0x1EE5)ng ch$([char]0x00ED)nh th$([char]0x1EE9)c r$([char]0x1ED3)i th$([char]0x1EED) l$([char]0x1EA1)i. T$([char]0x00E0)i kho$([char]0x1EA3)n ch$([char]0x01B0)a $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c l$([char]0x01B0)u." }
        'LoginProjectRequired' { "Antigravity y$([char]0x00EA)u c$([char]0x1EA7)u c$([char]0x1EA5)u h$([char]0x00EC)nh project tr$([char]0x01B0)$([char]0x1EDB)c khi d$([char]0x00F9)ng t$([char]0x00E0)i kho$([char]0x1EA3)n. H$([char]0x00E3)y ho$([char]0x00E0)n t$([char]0x1EA5)t y$([char]0x00EA)u c$([char]0x1EA7)u trong $([char]0x1EE9)ng d$([char]0x1EE5)ng ch$([char]0x00ED)nh th$([char]0x1EE9)c r$([char]0x1ED3)i th$([char]0x00EA)m l$([char]0x1EA1)i v$([char]0x00E0)o Hub." }
        'LoginInteractiveRequired' { "Antigravity y$([char]0x00EA)u c$([char]0x1EA7)u ph$([char]0x01B0)$([char]0x01A1)ng th$([char]0x1EE9)c x$([char]0x00E1)c th$([char]0x1EF1)c kh$([char]0x00E1)c (headlessAuthRequired); Hub ch$([char]0x01B0)a h$([char]0x1ED7) tr$([char]0x1EE3) b$([char]0x01B0)$([char]0x1EDB)c n$([char]0x00E0)y. H$([char]0x00E3)y $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p trong $([char]0x1EE9)ng d$([char]0x1EE5)ng ch$([char]0x00ED)nh th$([char]0x1EE9)c." }
        'LoginLicenseRequired' { "Antigravity y$([char]0x00EA)u c$([char]0x1EA7)u gi$([char]0x1EA5)y ph$([char]0x00E9)p s$([char]0x1EED) d$([char]0x1EE5)ng cho t$([char]0x00E0)i kho$([char]0x1EA3)n n$([char]0x00E0)y. H$([char]0x00E3)y ki$([char]0x1EC3)m tra quy$([char]0x1EC1)n truy c$([char]0x1EAD)p trong $([char]0x1EE9)ng d$([char]0x1EE5)ng ch$([char]0x00ED)nh th$([char]0x1EE9)c r$([char]0x1ED3)i th$([char]0x00EA)m l$([char]0x1EA1)i v$([char]0x00E0)o Hub." }
        'LoginAuthRejected' { "Antigravity ch$([char]0x01B0)a x$([char]0x00E1)c nh$([char]0x1EAD)n t$([char]0x00E0)i kho$([char]0x1EA3)n h$([char]0x1EE3)p l$([char]0x1EC7) d$([char]0x00F9) Google c$([char]0x00F3) th$([char]0x1EC3) $([char]0x0111)$([char]0x00E3) $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p th$([char]0x00E0)nh c$([char]0x00F4)ng. T$([char]0x00E0)i kho$([char]0x1EA3)n ch$([char]0x01B0)a $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c l$([char]0x01B0)u. H$([char]0x00E3)y ki$([char]0x1EC3)m tra $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p trong $([char]0x1EE9)ng d$([char]0x1EE5)ng Antigravity ch$([char]0x00ED)nh th$([char]0x1EE9)c." }
        'LoginCleanupFailed' { "Kh$([char]0x00F4)ng kh$([char]0x00F4)i ph$([char]0x1EE5)c $([char]0x0111)$([char]0x1EA7)y $([char]0x0111)$([char]0x1EE7) $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c th$([char]0x00F4)ng tin $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p tr$([char]0x01B0)$([char]0x1EDB)c $([char]0x0111)$([char]0x00F3). T$([char]0x1EF1) $([char]0x0111)$([char]0x1ED9)ng xoay $([char]0x0111)$([char]0x00E3) t$([char]0x1EA1)m d$([char]0x1EEB)ng. H$([char]0x00E3)y ki$([char]0x1EC3)m tra t$([char]0x00E0)i kho$([char]0x1EA3)n $([char]0x0111)ang d$([char]0x00F9)ng trong Antigravity tr$([char]0x01B0)$([char]0x1EDB)c khi ti$([char]0x1EBF)p t$([char]0x1EE5)c." }
        'LoginBusy' { "$([char]0x0110)ang c$([char]0x00F3) thao t$([char]0x00E1)c chuy$([char]0x1EC3)n ho$([char]0x1EB7)c th$([char]0x00EA)m t$([char]0x00E0)i kho$([char]0x1EA3)n. Vui l$([char]0x00F2)ng th$([char]0x1EED) l$([char]0x1EA1)i sau." }
        'LoginHelperMissing' { "Kh$([char]0x00F4)ng t$([char]0x00EC)m th$([char]0x1EA5)y language_server.exe c$([char]0x1EE7)a Antigravity." }
        'LoginUrlTimeout' { "Kh$([char]0x00F4)ng nh$([char]0x1EAD)n $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c li$([char]0x00EA)n k$([char]0x1EBF)t Google sau 30 gi$([char]0x00E2)y. Ki$([char]0x1EC3)m tra k$([char]0x1EBF)t n$([char]0x1ED1)i m$([char]0x1EA1)ng ho$([char]0x1EB7)c c$([char]0x1EAD)p nh$([char]0x1EAD)t Antigravity r$([char]0x1ED3)i th$([char]0x1EED) l$([char]0x1EA1)i." }
        'LoginTimeout' { "$([char]0x0110)$([char]0x00E3) h$([char]0x1EBF)t 5 ph$([char]0x00FA)t ch$([char]0x1EDD) $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p. B$([char]0x1EA5)m Th$([char]0x00EA)m T$([char]0x00E0)i Kho$([char]0x1EA3)n M$([char]0x1EDB)i $([char]0x0111)$([char]0x1EC3) th$([char]0x1EED) l$([char]0x1EA1)i." }
        'LoginBrowserFailed' { "Kh$([char]0x00F4)ng m$([char]0x1EDF) $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c tr$([char]0x00EC)nh duy$([char]0x1EC7)t m$([char]0x1EB7)c $([char]0x0111)$([char]0x1ECB)nh. Ki$([char]0x1EC3)m tra $([char]0x1EE9)ng d$([char]0x1EE5)ng m$([char]0x1EDF) li$([char]0x00EA)n k$([char]0x1EBF)t HTTPS trong Windows." }
        'LoginTokenMissing' { "$([char]0x0110)$([char]0x0103)ng nh$([char]0x1EAD)p ch$([char]0x01B0)a tr$([char]0x1EA3) v$([char]0x1EC1) token h$([char]0x1EE3)p l$([char]0x1EC7). Vui l$([char]0x00F2)ng th$([char]0x1EED) l$([char]0x1EA1)i." }
        default { "Kh$([char]0x00F4)ng ho$([char]0x00E0)n t$([char]0x1EA5)t $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c lu$([char]0x1ED3)ng $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p. Ki$([char]0x1EC3)m tra m$([char]0x1EA1)ng, c$([char]0x1EA5)u h$([char]0x00EC)nh OAuth v$([char]0x00E0) phi$([char]0x00EA)n b$([char]0x1EA3)n Antigravity r$([char]0x1ED3)i th$([char]0x1EED) l$([char]0x1EA1)i." }
    }
    return $message
}

function Show-AccountLoginFailure {
    param([string]$Code)
    $message=Get-AccountLoginFailureMessage $Code
    # Only fixed codes enter logs; never URLs, raw helper output or OAuth errors.
    $safeCode = if ($Code -in @('LoginBusy','LoginHelperMissing','LoginUrlTimeout','LoginTimeout','LoginBrowserFailed','LoginTokenMissing','LoginHelperExited','LoginRequestFailed','LoginListenerMismatch','LoginAuthRejected','LoginInvalidResponse','LoginIdentityMissing','LoginCleanupFailed','LoginIneligible','LoginVerificationRequired','LoginTermsRejected','LoginProviderError','LoginProjectRequired','LoginInteractiveRequired','LoginLicenseRequired','LoginVerificationTimeout')) { $Code } else { 'LoginFailed' }
    Write-RotatorLog "Account login failed: $safeCode."
    [System.Windows.MessageBox]::Show($window, $message, "Th$([char]0x00EA)m t$([char]0x00E0)i kho$([char]0x1EA3)n", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
}
$window.Add_Closed({ Complete-AccountLogin })

$btnAddAccount.Add_Click({
    if ($Preview) { return }
    if ($script:loginProtection) { Complete-AccountLogin; return }
    $lsPath=Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\resources\bin\language_server.exe'
    if (-not (Test-Path -LiteralPath $lsPath)) { Show-AccountLoginFailure 'LoginHelperMissing'; return }
    $loginLock=[Threading.Mutex]::new($false, 'Local\AntigravityAutoHub.Switch')
    $loginLocked=$false
    try { $loginLocked=$loginLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $loginLocked=$true }
    if (-not $loginLocked) { $loginLock.Dispose(); Show-AccountLoginFailure 'LoginBusy'; return }
    $script:loginProtection=$loginLock
    try {
        $script:loginSnapshotReady=$false
        $script:loginOldCredential=Get-StoredCredential
        $script:loginOldFallback=$null
        if (Test-Path -LiteralPath $geminiTokenPath) { $script:loginOldFallback=[IO.File]::ReadAllText($geminiTokenPath) }
        $script:loginSnapshotReady=$true
        $script:activeLoginTempDir=Join-Path $env:TEMP ('ag_login_'+(Get-Random))
        New-Item -ItemType Directory -Path $script:activeLoginTempDir -ErrorAction Stop | Out-Null
        $accountsContainer.IsEnabled=$false; $btnSaveCurrent.IsEnabled=$false
        $btnAddAccount.Content="H$([char]0x1EE7)y $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p"
        $script:loginSession=[AntigravityAccountLogin]::new($lsPath,$script:activeLoginTempDir)
        $script:loginClock=[Diagnostics.Stopwatch]::StartNew()
        $script:loginBrowserOpened=$false
        $script:loginResultAt=$null
        $script:loginVerificationAt=$null
        $loginTimer=New-Object System.Windows.Threading.DispatcherTimer
        $loginTimer.Interval=[TimeSpan]::FromMilliseconds(250)
        $script:activeLoginTimer=$loginTimer
        $loginTimer.Add_Tick({
            try {
                $session=$script:loginSession
                if (-not $session) { return }
                Update-AccountLoginSession $session
                if ($session.AuthUrl -and -not $script:loginBrowserOpened) {
                    $url=$session.AuthUrl
                    if ($url -notmatch '[?&]prompt=') { $url+='&prompt=select_account' }
                    try {
                        $browser=[Diagnostics.ProcessStartInfo]::new($url)
                        $browser.UseShellExecute=$true
                        [Diagnostics.Process]::Start($browser) | Out-Null
                    } catch { throw 'LoginBrowserFailed' }
                    $script:loginBrowserOpened=$true
                    Write-RotatorLog 'Account login: Google authorization opened.'
                }
                if (-not $script:loginBrowserOpened -and $script:loginClock.Elapsed.TotalSeconds -ge 30) { throw 'LoginUrlTimeout' }
                if ($null -eq $script:loginVerificationAt -and $script:loginClock.Elapsed.TotalSeconds -ge 300) { throw 'LoginTimeout' }
                if ($null -ne $script:loginVerificationAt -and $script:loginClock.Elapsed.TotalSeconds-$script:loginVerificationAt -ge 300) { throw 'LoginVerificationTimeout' }
                if (-not $session.Succeeded) { return }
                $script:activeLoginTimer.Stop()
                $listeners=@(Get-NetTCPConnection -LocalPort $session.Port -State Listen -ErrorAction Stop)
                if (-not ($listeners | Where-Object {$_.OwningProcess -eq $session.Process.Id -and $_.LocalAddress -in @('127.0.0.1','::1')})) { throw 'LoginListenerMismatch' }
                $progress=Get-AccountLoginProgress $session -Recheck:($null -ne $script:loginVerificationAt)
                if ($progress.Status -eq 'VerificationRequired') {
                    if ($null -eq $script:loginVerificationAt) {
                        $browser=[Diagnostics.ProcessStartInfo]::new($progress.VerificationUrl)
                        $browser.UseShellExecute=$true
                        try { [Diagnostics.Process]::Start($browser) | Out-Null } catch { throw 'LoginBrowserFailed' }
                        $script:loginVerificationAt=$script:loginClock.Elapsed.TotalSeconds
                        $btnAddAccount.Content="H$([char]0x1EE7)y x$([char]0x00E1)c minh"
                        Write-RotatorLog 'Account login: official Google verification opened; waiting for valid auth.'
                    }
                    $script:activeLoginTimer.Interval=[TimeSpan]::FromSeconds(2)
                    $script:activeLoginTimer.Start()
                    return
                }
                if ($null -eq $script:loginResultAt) { $script:loginResultAt=$script:loginClock.Elapsed.TotalSeconds }
                $identity=$session.ReadUserStatus() | ConvertFrom-Json
                $candidates=@(Get-AccountLoginTokenCandidates $script:activeLoginTempDir $geminiTokenPath)
                $verified=Get-VerifiedAccountLoginToken $candidates $identity.userStatus.email
                if (-not $verified) {
                    $tempTokens=@(Get-ChildItem -LiteralPath $script:activeLoginTempDir -Recurse -File -Filter '*token*' -ErrorAction SilentlyContinue).Count
                    Write-RotatorLog "Account login token verification pending: candidates=$($candidates.Count), helperTokenFiles=$tempTokens."
                    if ($script:loginClock.Elapsed.TotalSeconds-$script:loginResultAt -ge 15) { throw 'LoginTokenMissing' }
                    $script:activeLoginTimer.Interval=[TimeSpan]::FromSeconds(2)
                    $script:activeLoginTimer.Start()
                    return
                }
                $token=$verified.Token
                $user=[pscustomobject]@{email=$verified.Email}
                $cleanName=$user.email.Split('@')[0] -replace '[^a-zA-Z0-9._-]','_'
                if (-not $cleanName -or $cleanName -in @('.','..')) { throw 'LoginTokenMissing' }
                Write-AtomicText (Join-Path $accDir ($cleanName+'.json')) ($token | ConvertTo-Json -Depth 6 -Compress)
                if (-not (Complete-AccountLogin)) { throw 'LoginCleanupFailed' }
                Write-RotatorLog 'Account login completed; account saved and previous credential restored.'
                Load-Accounts-UI
                [System.Windows.MessageBox]::Show($window, "$([char]0x0110)$([char]0x00E3) th$([char]0x00EA)m t$([char]0x00E0)i kho$([char]0x1EA3)n: $($user.email)", "Th$([char]0x00EA)m t$([char]0x00E0)i kho$([char]0x1EA3)n", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            } catch {
                $code=$_.Exception.Message
                if (-not (Complete-AccountLogin)) { $code='LoginCleanupFailed' }
                Show-AccountLoginFailure $code
            }
        })
        $loginTimer.Start()
    } catch {
        $code='LoginFailed'
        if (-not (Complete-AccountLogin)) { $code='LoginCleanupFailed' }
        Show-AccountLoginFailure $code
    }
})

Initialize-HubDashboard

if (-not $NoShow) { $window.ShowDialog() | Out-Null }
