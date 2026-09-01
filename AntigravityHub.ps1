# ==============================================================================
# ANTIGRAVITY MULTI-ACCOUNT HUB - FONT FIXED & LIVE AUTO-ROTATION
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms, Microsoft.VisualBasic

$baseDir = "D:\AntigravityAccounts"
$accDir = Join-Path $baseDir "accounts"
$activeFile = Join-Path $baseDir "current_active.txt"
$geminiTokenPath = "C:\Users\datdt\.gemini\jetski-standalone-oauth-token"
$rotatorScript = Join-Path $baseDir "AutoRotator.ps1"
$xamlFile = Join-Path $baseDir "MainWindow.xaml"

if (-not (Test-Path $accDir)) {
    New-Item -ItemType Directory -Path $accDir -Force | Out-Null
}

# Helper to check if AutoRotator daemon is running
function Get-DaemonStatus {
    $procs = Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%AutoRotator.ps1%Daemon%'" -ErrorAction SilentlyContinue
    return ($procs.Count -gt 0)
}

function Start-AutoRotatorDaemon {
    if (-not (Get-DaemonStatus)) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File ""$rotatorScript"" -Daemon -IntervalSeconds 60"
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    }
}

# Auto start daemon on launch
Start-AutoRotatorDaemon

if (-not (Test-Path $xamlFile)) {
    Write-Error "Khong tim thay file MainWindow.xaml tai $xamlFile"
    exit 1
}

$xamlText = [System.IO.File]::ReadAllText($xamlFile, [System.Text.Encoding]::UTF8)
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlText))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$titleBar = $window.FindName("TitleBar")
$btnMinimize = $window.FindName("BtnMinimize")
$btnClose = $window.FindName("BtnClose")
$btnRefresh = $window.FindName("BtnRefresh")
$btnSaveCurrent = $window.FindName("BtnSaveCurrent")
$btnAddAccount = $window.FindName("BtnAddAccount")
$btnOpenFolder = $window.FindName("BtnOpenFolder")
$accountsContainer = $window.FindName("AccountsContainer")
$txtDaemonStatus = $window.FindName("TxtDaemonStatus")

$titleBar.Add_MouseLeftButtonDown({ $window.DragMove() })
$btnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$btnClose.Add_Click({ $window.Close() })
$btnOpenFolder.Add_Click({ Start-Process "explorer.exe" $baseDir })

function Get-CurrentActiveName {
    if (Test-Path $activeFile) {
        $name = (Get-Content $activeFile -Raw).Trim()
        if ($name -ne "") { return $name }
    }
    return ""
}

# Function to load and render accounts with Live Quota
function Load-Accounts-UI {
    $accountsContainer.Children.Clear()
    
    # Run quota check
    . $rotatorScript
    $accounts = Get-AllAccountsQuota
    $activeName = Get-CurrentActiveName

    if ($accounts.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes("ChÆ°a cĂ³ tĂ i khoáº£n nĂ o Ä‘Æ°á»£c thĂªm vĂ o há»‡ thá»‘ng.`nHĂ£y báº¥m 'â• ThĂªm TĂ i Khoáº£n Má»›i' á»Ÿ trĂªn Ä‘á»ƒ báº¯t Ä‘áº§u."))
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
        $isActive = ($accName -eq $activeName)
        $geminiPct = [Math]::Max(0, [Math]::Round($acc.Gemini5H * 100))
        $email = if ($acc.Email) { $acc.Email } else { "Äang xĂ¡c thá»±c..." }

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

        # Row 1: Icon + Name + Email + Status Badge
        $row1 = New-Object System.Windows.Controls.StackPanel
        $row1.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $icon = New-Object System.Windows.Controls.TextBlock
        $icon.Text = "[đŸ‘¤]"
        $icon.FontSize = 13
        $icon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#89B4FA")
        $icon.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        $icon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $row1.Children.Add($icon) | Out-Null

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
            $bText.Text = "ÄANG Káº¾T Ná»I"
            $bText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
            $bText.FontSize = 10
            $bText.FontWeight = [System.Windows.FontWeights]::Bold
            $badge.Child = $bText
            $row1.Children.Add($badge) | Out-Null
        }

        $info.Children.Add($row1) | Out-Null

        # Row 2: Quota Progress Bar
        $quotaRow = New-Object System.Windows.Controls.StackPanel
        $quotaRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $quotaRow.Margin = New-Object System.Windows.Thickness(23, 8, 0, 0)

        $qLabel = New-Object System.Windows.Controls.TextBlock
        $qLabel.Text = "Háº¡n má»©c Gemini 5H:"
        $qLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#6C7086")
        $qLabel.FontSize = 12
        $qLabel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $quotaRow.Children.Add($qLabel) | Out-Null

        # Progress bar container
        $pBorder = New-Object System.Windows.Controls.Border
        $pBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
        $pBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $pBorder.Width = 140
        $pBorder.Height = 8
        $pBorder.Margin = New-Object System.Windows.Thickness(8, 0, 8, 0)
        $pBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $pFill = New-Object System.Windows.Controls.Border
        $pFill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $pFill.Width = [Math]::Round(140 * ($geminiPct / 100))
        $pFill.CornerRadius = New-Object System.Windows.CornerRadius(4)

        if ($geminiPct -ge 50) {
            $pFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
        } elseif ($geminiPct -ge 20) {
            $pFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F9E2AF")
        } else {
            $pFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
        }
        $pBorder.Child = $pFill
        $quotaRow.Children.Add($pBorder) | Out-Null

        $qPctText = New-Object System.Windows.Controls.TextBlock
        $qPctText.Text = "$geminiPct%"
        $qPctText.FontWeight = [System.Windows.FontWeights]::Bold
        $qPctText.FontSize = 12
        if ($geminiPct -ge 50) {
            $qPctText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
        } elseif ($geminiPct -ge 20) {
            $qPctText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F9E2AF")
        } else {
            $qPctText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
        }
        $qPctText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $quotaRow.Children.Add($qPctText) | Out-Null

        $info.Children.Add($quotaRow) | Out-Null

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
            $btnSwitch.Content = "â¡ Chuyá»ƒn Thá»§ CĂ´ng"
            $btnSwitch.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
            $btnSwitch.Add_Click({
                Switch-ActiveAccount -targetAccountName $currName | Out-Null
                Load-Accounts-UI
            }.GetNewClosure())
            $actions.Children.Add($btnSwitch) | Out-Null
        }

        $btnDel = New-Object System.Windows.Controls.Button
        $btnDel.Style = $window.FindResource("DangerBtn")
        $btnDel.Content = "âœ• XĂ³a"
        $btnDel.Padding = New-Object System.Windows.Thickness(8, 6, 8, 6)
        $btnDel.ToolTip = "XĂ³a tĂ i khoáº£n khá»i kho xoay"
        $btnDel.Add_Click({
            $ans = [System.Windows.MessageBox]::Show("Báº¡n cĂ³ cháº¯c cháº¯n muá»‘n xĂ³a tĂ i khoáº£n '$currName' khá»i há»‡ thá»‘ng?", "XĂ¡c Nháº­n XĂ³a", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
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

# Event: Refresh Button
$btnRefresh.Add_Click({
    Load-Accounts-UI
})

# Event: Save Current Active Token
$btnSaveCurrent.Add_Click({
    if (-not (Test-Path $geminiTokenPath)) {
        [System.Windows.MessageBox]::Show("KhĂ´ng tĂ¬m tháº¥y token Ä‘Äƒng nháº­p hiá»‡n táº¡i trong Antigravity IDE.`nHĂ£y Ä‘áº£m báº£o báº¡n Ä‘Ă£ Ä‘Äƒng nháº­p Google trĂªn IDE.", "ThĂ´ng bĂ¡o", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $defaultName = "Acc_" + ((Get-ChildItem -Path $accDir -Filter "*.json" -ErrorAction SilentlyContinue).Count + 1)
    $inputName = [Microsoft.VisualBasic.Interaction]::InputBox("Nháº­p tĂªn gá»£i nhá»› cho tĂ i khoáº£n Google Ä‘ang Ä‘Äƒng nháº­p (vĂ­ dá»¥: Acc_Chinh, Google_2, Gmail_Phu):", "LÆ°u TĂ i Khoáº£n VĂ o Kho", $defaultName)

    if (-not [string]::IsNullOrWhiteSpace($inputName)) {
        $safeName = $inputName.Trim() -replace '[^a-zA-Z0-9_\-]', '_'
        $targetFile = Join-Path $accDir "$safeName.json"
        Copy-Item $geminiTokenPath $targetFile -Force
        Set-Content -Path $activeFile -Value $safeName -Encoding ASCII
        Load-Accounts-UI
        [System.Windows.MessageBox]::Show("ÄĂ£ lÆ°u tĂ i khoáº£n '$safeName' vĂ o kho xoay tua thĂ nh cĂ´ng!", "ThĂ nh CĂ´ng", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Event: Add Account (Logout & Sign In new)
$btnAddAccount.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show("CĂ¡c bÆ°á»›c thĂªm tĂ i khoáº£n má»›i:`n`n1. Há»‡ thá»‘ng sáº½ táº¡m cáº¥t tĂ i khoáº£n cÅ©.`n2. Antigravity IDE sáº½ yĂªu cáº§u báº¡n Ä‘Äƒng nháº­p tĂ i khoáº£n Google má»›i.`n3. ÄÄƒng nháº­p xong, má»Ÿ láº¡i Hub vĂ  báº¥m 'LÆ°u Acc NĂ y'.`n`nBáº¡n muá»‘n thĂªm tĂ i khoáº£n má»›i ngay bĂ¢y giá»?", "ThĂªm TĂ i Khoáº£n Má»›i", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
        if (Test-Path $geminiTokenPath) {
            $activeName = Get-CurrentActiveName
            if ($activeName -ne "") {
                Copy-Item $geminiTokenPath (Join-Path $accDir "$activeName.json") -Force
            }
            Remove-Item $geminiTokenPath -Force -ErrorAction SilentlyContinue
        }
        Set-Content -Path $activeFile -Value "Dang_Login_Acc_Moi" -Encoding ASCII
        Load-Accounts-UI
        [System.Windows.MessageBox]::Show("Sáºµn sĂ ng! HĂ£y quay láº¡i Antigravity IDE vĂ  tiáº¿n hĂ nh ÄÄƒng nháº­p tĂ i khoáº£n Google má»›i cá»§a báº¡n.`n`nÄÄƒng nháº­p xong, má»Ÿ láº¡i Hub nĂ y vĂ  báº¥m 'LÆ°u Acc NĂ y'.", "Äang ÄÄƒng Nháº­p", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Initial Load
Load-Accounts-UI

$window.ShowDialog() | Out-Null
