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

. $rotatorScript
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

Start-AutoRotatorDaemon

if (-not (Test-Path $xamlFile)) {
    Write-Error "Khong tim thay file MainWindow.xaml tai $xamlFile"
    exit 1
}

$xamlText = [System.IO.File]::ReadAllText($xamlFile, [System.Text.Encoding]::ASCII)
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlText))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

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

$titleBar.Add_MouseLeftButtonDown({ $window.DragMove() })
$btnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$btnClose.Add_Click({ $window.Close() })
$btnOpenFolder.Add_Click({ Start-Process "explorer.exe" $baseDir })

function Load-Accounts-UI {
    $accountsContainer.Children.Clear()
    
    $accounts = @(Get-AllAccountsQuota)
    $runtime = $null
    $runtimeFailure = $null
    try { $runtime = Get-RuntimeIdentity } catch { $runtimeFailure = Get-RuntimeFailureMessage $_ }
    $activeEmail = if ($runtime) { $runtime.Email } else { '' }
    $state = Read-RotationState
    $daemonText = $window.FindName('TxtDaemonStatus')
    if ($state.Status -in @('Switching','NeedsAttention')) {
        $daemonText.Text = "C$([char]0x1EA7)n ki$([char]0x1EC3)m tra chuy$([char]0x1EC3)n t$([char]0x00E0)i kho$([char]0x1EA3)n"
    } elseif ($runtimeFailure) {
        $daemonText.Text = $runtimeFailure
    } elseif (-not $runtime) {
        $daemonText.Text = "Ch$([char]0x01B0)a x$([char]0x00E1)c minh IDE"
    } elseif (-not (Get-DaemonStatus)) {
        $daemonText.Text = "Daemon ch$([char]0x01B0)a ch$([char]0x1EA1)y"
    } elseif (-not $runtime.Idle) {
        $daemonText.Text = "IDE $([char]0x0111)ang ch$([char]0x1EA1)y t$([char]0x00E1)c v$([char]0x1EE5)"
    } else {
        $daemonText.Text = "S$([char]0x1EB5)n s$([char]0x00E0)ng xoay khi quota th$([char]0x1EA5)p"
    }

    if ($accounts.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = "Ch$([char]0x01B0)a c$([char]0x00F3) t$([char]0x00E0)i kho$([char]0x1EA3)n n$([char]0x00E0)o trong h$([char]0x1EC7) th$([char]0x1ED1)ng.`nH$([char]0x00E3)y b$([char]0x1EA5)m '+ Th$([char]0x00EA)m T$([char]0x00E0)i Kho$([char]0x1EA3)n M$([char]0x1EDB)i' $ linh ho$([char]0x1EA1)t b$([char]0x1EAF)t $([char]0x0111)$([char]0x1EA7)u."
        $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#6C7086")
        $empty.FontSize = 13
        $empty.Margin = New-Object System.Windows.Thickness(0, 40, 0, 0)
        $empty.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $empty.TextAlignment = [System.Windows.TextAlignment]::Center
        $accountsContainer.Children.Add($empty) | Out-Null
        return
    }

    foreach ($acc in $accounts) {
        $accName = $acc.AccountName
        $isActive = ($activeEmail -and $acc.Email -eq $activeEmail)
        $gemini5hPct = [Math]::Max(0, [Math]::Round($acc.Gemini5H * 100))
        $geminiWeeklyPct = [Math]::Max(0, [Math]::Round($acc.GeminiWeekly * 100))
        $email = if ($acc.Email) { $acc.Email } else { "$([char]0x0110)ang x$([char]0x00E1)c th$([char]0x1EF1)c..." }

        # Card Border
        $card = New-Object System.Windows.Controls.Border
        if ($isActive) {
            $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#23283B")
            $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#89B4FA")
            $card.BorderThickness = New-Object System.Windows.Thickness(1.5)
        } else {
            $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E2E")
            $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
        }
        $card.CornerRadius = New-Object System.Windows.CornerRadius(10)
        $card.Padding = New-Object System.Windows.Thickness(18, 14, 18, 14)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)

        $grid = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($c1)
        $grid.ColumnDefinitions.Add($c2)

        # Left Info Stack
        $info = New-Object System.Windows.Controls.StackPanel
        $info.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        # Row 1: Name + Email + Status Badge
        $row1 = New-Object System.Windows.Controls.StackPanel
        $row1.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $name = New-Object System.Windows.Controls.TextBlock
        $name.Text = $accName
        $name.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CDD6F4")
        $name.FontSize = 14
        $name.FontWeight = [System.Windows.FontWeights]::Bold
        $name.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $row1.Children.Add($name) | Out-Null

        $emailText = New-Object System.Windows.Controls.TextBlock
        $emailText.Text = "($email)"
        $emailText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6ADC8")
        $emailText.FontSize = 12
        $emailText.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
        $emailText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $row1.Children.Add($emailText) | Out-Null

        if ($isActive) {
            $badge = New-Object System.Windows.Controls.Border
            $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E382B")
            $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
            $badge.Padding = New-Object System.Windows.Thickness(8, 2, 8, 2)
            $badge.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0)
            $badge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

            $bText = New-Object System.Windows.Controls.TextBlock
            $bText.Text = "$([char]0x0110)ANG K$([char]0x1EBF)T N$([char]0x1ED0)I"
            $bText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
            $bText.FontSize = 10
            $bText.FontWeight = [System.Windows.FontWeights]::Bold
            $badge.Child = $bText
            $row1.Children.Add($badge) | Out-Null
        }

        $info.Children.Add($row1) | Out-Null

        # Row 2: Dual Quota Progress Bars (5H & Weekly)
        $quotaRow = New-Object System.Windows.Controls.StackPanel
        $quotaRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $quotaRow.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)

        # 1. 5H Quota
        $q5hLabel = New-Object System.Windows.Controls.TextBlock
        $q5hLabel.Text = "5H:"
        $q5hLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6ADC8")
        $q5hLabel.FontSize = 11
        $q5hLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
        $q5hLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $quotaRow.Children.Add($q5hLabel) | Out-Null

        $p5hBorder = New-Object System.Windows.Controls.Border
        $p5hBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
        $p5hBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $p5hBorder.Width = 90
        $p5hBorder.Height = 7
        $p5hBorder.Margin = New-Object System.Windows.Thickness(6, 0, 6, 0)
        $p5hBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $p5hFill = New-Object System.Windows.Controls.Border
        $p5hFill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $p5hFill.Width = [Math]::Round(90 * ($gemini5hPct / 100))
        $p5hFill.CornerRadius = New-Object System.Windows.CornerRadius(4)
        if ($gemini5hPct -ge 50) {
            $p5hFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
        } elseif ($gemini5hPct -ge 20) {
            $p5hFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F9E2AF")
        } else {
            $p5hFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
        }
        $p5hBorder.Child = $p5hFill
        $quotaRow.Children.Add($p5hBorder) | Out-Null

        $q5hPctText = New-Object System.Windows.Controls.TextBlock
        $q5hPctText.Text = if ($acc.Success) { "$gemini5hPct%" } else { "N/A" }
        $q5hPctText.FontWeight = [System.Windows.FontWeights]::Bold
        $q5hPctText.FontSize = 11
        $q5hPctText.Foreground = $p5hFill.Background
        $q5hPctText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $quotaRow.Children.Add($q5hPctText) | Out-Null

        # Divider
        $divider = New-Object System.Windows.Controls.TextBlock
        $divider.Text = "|"
        $divider.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#45475A")
        $divider.FontSize = 11
        $divider.Margin = New-Object System.Windows.Thickness(12, 0, 12, 0)
        $divider.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $quotaRow.Children.Add($divider) | Out-Null

        # 2. Weekly Quota
        $qWLabel = New-Object System.Windows.Controls.TextBlock
        $qWLabel.Text = "Tu$([char]0x1EA7)n:"
        $qWLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6ADC8")
        $qWLabel.FontSize = 11
        $qWLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
        $qWLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $quotaRow.Children.Add($qWLabel) | Out-Null

        $pWBorder = New-Object System.Windows.Controls.Border
        $pWBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
        $pWBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $pWBorder.Width = 90
        $pWBorder.Height = 7
        $pWBorder.Margin = New-Object System.Windows.Thickness(6, 0, 6, 0)
        $pWBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $pWFill = New-Object System.Windows.Controls.Border
        $pWFill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $pWFill.Width = [Math]::Round(90 * ($geminiWeeklyPct / 100))
        $pWFill.CornerRadius = New-Object System.Windows.CornerRadius(4)
        if ($geminiWeeklyPct -ge 50) {
            $pWFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#89B4FA")
        } elseif ($geminiWeeklyPct -ge 20) {
            $pWFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F9E2AF")
        } else {
            $pWFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
        }
        $pWBorder.Child = $pWFill
        $quotaRow.Children.Add($pWBorder) | Out-Null

        $qWPctText = New-Object System.Windows.Controls.TextBlock
        $qWPctText.Text = if ($acc.Success) { "$geminiWeeklyPct%" } else { "N/A" }
        $qWPctText.FontWeight = [System.Windows.FontWeights]::Bold
        $qWPctText.FontSize = 11
        $qWPctText.Foreground = $pWFill.Background
        $qWPctText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $quotaRow.Children.Add($qWPctText) | Out-Null

        $info.Children.Add($quotaRow) | Out-Null
        if (-not $acc.Success) {
            $quotaStatus=New-Object System.Windows.Controls.TextBlock
            $quotaStatus.Text=if($acc.ErrorCode -eq 'AccountVerificationRequired'){"C$([char]0x1EA7)n x$([char]0x00E1)c minh Google $([char]0x0111)$([char]0x1EC3) $([char]0x0111)$([char]0x1ECD)c quota"}else{"Ch$([char]0x01B0)a $([char]0x0111)$([char]0x1ECD)c $([char]0x0111)$([char]0x01B0)$([char]0x1EE3)c quota. Th$([char]0x1EED) Qu$([char]0x00E9)t Quota l$([char]0x1EA1)i. "}
            $quotaStatus.Foreground=[System.Windows.Media.BrushConverter]::new().ConvertFromString("#F9E2AF")
            $quotaStatus.FontSize=11
            $quotaStatus.TextWrapping=[System.Windows.TextWrapping]::Wrap
            $quotaStatus.Margin=New-Object System.Windows.Thickness(0,6,8,0)
            $info.Children.Add($quotaStatus) | Out-Null
            if($acc.VerificationUrl) {
                $verificationUrl=$acc.VerificationUrl
                $btnVerify=New-Object System.Windows.Controls.Button
                $btnVerify.Style=$window.FindResource("SuccessBtn")
                $btnVerify.Content="X$([char]0x00E1)c minh Google"
                $btnVerify.HorizontalAlignment=[System.Windows.HorizontalAlignment]::Left
                $btnVerify.Margin=New-Object System.Windows.Thickness(0,6,0,0)
                $btnVerify.ToolTip="Ho$([char]0x00E0)n t$([char]0x1EA5)t x$([char]0x00E1)c minh r$([char]0x1ED3)i b$([char]0x1EA5)m Qu$([char]0x00E9)t Quota"
                $btnVerify.Add_Click({
                    if(-not [AntigravityAccountLogin]::IsVerificationUrl($verificationUrl)){return}
                    try {
                        $browser=[Diagnostics.ProcessStartInfo]::new($verificationUrl)
                        $browser.UseShellExecute=$true
                        [Diagnostics.Process]::Start($browser) | Out-Null
                    } catch { Show-AccountLoginFailure 'LoginBrowserFailed' }
                }.GetNewClosure())
                $info.Children.Add($btnVerify) | Out-Null
            }
        }

        [System.Windows.Controls.Grid]::SetColumn($info, 0)
        $grid.Children.Add($info) | Out-Null

        # Right Action Buttons
        $actions = New-Object System.Windows.Controls.StackPanel
        $actions.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $actions.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $currName = $accName
        $currFile = $acc.TokenPath

        if (-not $isActive) {
            $btnSwitch = New-Object System.Windows.Controls.Button
            $btnSwitch.Style = $window.FindResource("SuccessBtn")
            $btnSwitch.Content = "$([char]0x26A1) Chuy$([char]0x1EC3)n Th$([char]0x1EE7) C$([char]0x00F4)ng"
            $btnSwitch.IsEnabled = $acc.Success
            $btnSwitch.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
            $btnSwitch.Add_Click({
                Switch-ActiveAccount -targetAccountName $currName -Notify | Out-Null
                Load-Accounts-UI
            }.GetNewClosure())
            $actions.Children.Add($btnSwitch) | Out-Null
        }

        $btnDel = New-Object System.Windows.Controls.Button
        $btnDel.Style = $window.FindResource("DangerBtn")
        $btnDel.Content = "$([char]0x2715) X$([char]0x00F3)a"
        $btnDel.Padding = New-Object System.Windows.Thickness(10, 6, 10, 6)
        $btnDel.ToolTip = "X$([char]0x00F3)a t$([char]0x00E0)i kho$([char]0x1EA3)n"
        $btnDel.Add_Click({
            $ans = [System.Windows.MessageBox]::Show("B$([char]0x1EA1)n c$([char]0x00F3) ch$([char]0x1EAF)c mu$([char]0x1ED1)n x$([char]0x00F3)a t$([char]0x00E0)i kho$([char]0x1EA3)n '$currName' kh$([char]0x1ECF)i h$([char]0x1EC7) th$([char]0x1ED1)ng?", "X$([char]0x00E1)c Nh$([char]0x1EAD)n X$([char]0x00F3)a", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
            if ($ans -eq [System.Windows.MessageBoxResult]::Yes) {
                Remove-Item $currFile -Force -ErrorAction SilentlyContinue
                Load-Accounts-UI
            }
        }.GetNewClosure())
        $actions.Children.Add($btnDel) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($actions, 1)
        $grid.Children.Add($actions) | Out-Null

        $card.Child = $grid
        $accountsContainer.Children.Add($card) | Out-Null
    }
}

$btnRefresh.Add_Click({
    Repair-RotationState | Out-Null
    Load-Accounts-UI
})

$btnSaveCurrent.Add_Click({
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
        $refreshToken = $json.token.refresh_token
        if ($refreshToken) {
            $tResp = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body @{
                client_id = $script:GoogleClientId; client_secret = $script:GoogleClientSecret; refresh_token = $refreshToken; grant_type = "refresh_token"
            } -TimeoutSec 10
            $uinfo = Invoke-RestMethod -Uri "https://www.googleapis.com/oauth2/v3/userinfo" -Headers @{ Authorization = "Bearer $($tResp.access_token)" } -TimeoutSec 5
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

Load-Accounts-UI

$window.ShowDialog() | Out-Null
