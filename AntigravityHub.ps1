# ==============================================================================
# ANTIGRAVITY MULTI-ACCOUNT HUB - 100% PURE ASCII UNICODE SAFE
# ==============================================================================
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
$accountsContainer = $window.FindName("AccountsContainer")

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

function Load-Accounts-UI {
    $accountsContainer.Children.Clear()
    
    . $rotatorScript
    $accounts = Get-AllAccountsQuota
    $activeName = Get-CurrentActiveName

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
        $isActive = ($accName -eq $activeName)
        $geminiPct = [Math]::Max(0, [Math]::Round($acc.Gemini5H * 100))
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

        # Row 2: Quota Progress Bar
        $quotaRow = New-Object System.Windows.Controls.StackPanel
        $quotaRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $quotaRow.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)

        $qLabel = New-Object System.Windows.Controls.TextBlock
        $qLabel.Text = "H$([char]0x1EA1)n m$([char]0x1EE9)c Gemini 5H:"
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
            $btnSwitch.Content = "$([char]0x26A1) Chuy$([char]0x1EC3)n Th$([char]0x1EE7) C$([char]0x00F4)ng"
            $btnSwitch.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
            $btnSwitch.Add_Click({
                Switch-ActiveAccount -targetAccountName $currName | Out-Null
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
    Load-Accounts-UI
})

$btnSaveCurrent.Add_Click({
    if (-not (Test-Path $geminiTokenPath)) {
        [System.Windows.MessageBox]::Show("Kh$([char]0x00F4)ng t$([char]0x00EC)m th$([char]0x1EA5)y token $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p hi$([char]0x1EC7)n t$([char]0x1EA1)i trong Antigravity IDE.`nH$([char]0x00E3)y $([char]0x0111)$([char]0x1EA3)m b$([char]0x1EA3)o b$([char]0x1EA1)n $([char]0x0111)$([char]0x00E3) $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p Google tr$([char]0x00EA)n IDE.", "Th$([char]0x00F4)ng b$([char]0x00E1)o", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $defaultName = "Acc_" + ((Get-ChildItem -Path $accDir -Filter "*.json" -ErrorAction SilentlyContinue).Count + 1)
    $inputName = [Microsoft.VisualBasic.Interaction]::InputBox("Nh$([char]0x1EAD)p t$([char]0x00EA)n g$([char]0x1EE3)i nh$([char]0x1EDB) cho t$([char]0x00E0)i kho$([char]0x1EA3)n Google $([char]0x0111)$([char]0x0103)ng $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p (v$([char]0x00ED) d$([char]0x1EE5): Acc_Chinh, Google_2, Gmail_Phu):", "L$([char]0x01B0)u T$([char]0x00E0)i Kho$([char]0x1EA3)n V$([char]0x00E0)o Kho", $defaultName)

    if (-not [string]::IsNullOrWhiteSpace($inputName)) {
        $safeName = $inputName.Trim() -replace '[^a-zA-Z0-9_\-]', '_'
        $targetFile = Join-Path $accDir "$safeName.json"
        Copy-Item $geminiTokenPath $targetFile -Force
        Set-Content -Path $activeFile -Value $safeName -Encoding ASCII
        Load-Accounts-UI
        [System.Windows.MessageBox]::Show("$([char]0x0110)$([char]0x00E3) l$([char]0x01B0)u t$([char]0x00E0)i kho$([char]0x1EA3)n '$safeName' v$([char]0x00E0)o kho xoay tua th$([char]0x00E0)nh c$([char]0x00F4)ng!", "Th$([char]0x00E0)nh C$([char]0x00F4)ng", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

$btnAddAccount.Add_Click({
    $msg = "C$([char]0x00E1)c b$([char]0x01B0)$([char]0x1EDB)c th$([char]0x00EA)m t$([char]0x00E0)i kho$([char]0x1EA3)n m$([char]0x1EDB)i:`n`n1. H$([char]0x1EC7) th$([char]0x1ED1)ng s$([char]0x1EBD) t$([char]0x1EA1)m c$([char]0x1EA5)t t$([char]0x00E0)i kho$([char]0x1EA3)n c$([char]0x0169).`n2. Antigravity IDE s$([char]0x1EBD) y$([char]0x00EA)u c$([char]0x1EA7)u b$([char]0x1EA1)n $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p t$([char]0x00E0)i kho$([char]0x1EA3)n Google m$([char]0x1EDB)i.`n3. $([char]0x0110)$([char]0x0103)ng nh$([char]0x1EAD)p xong, m$([char]0x1EDF) l$([char]0x1EA1)i Hub v$([char]0x00E0) b$([char]0x1EA5)m 'L$([char]0x01B0)u Acc N$([char]0x00E0)y'.`n`nB$([char]0x1EA1)n c$([char]0x00F3) mu$([char]0x1ED1)n th$([char]0x00EA)m t$([char]0x00E0)i kho$([char]0x1EA3)n m$([char]0x1EDB)i ngay b$([char]0x00E2)y gi$([char]0x1EDD) kh$([char]0x00F4)ng?"
    $confirm = [System.Windows.MessageBox]::Show($msg, "Th$([char]0x00EA)m T$([char]0x00E0)i Kho$([char]0x1EA3)n M$([char]0x1EDB)i", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
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
        [System.Windows.MessageBox]::Show("S$([char]0x1EB5)n s$([char]0x00E0)ng! H$([char]0x00E3)y quay l$([char]0x1EA1)i Antigravity IDE v$([char]0x00E0) ti$([char]0x1EBF)n h$([char]0x00E0)nh $([char]0x0111)$([char]0x0103)ng nh$([char]0x1EAD)p t$([char]0x00E0)i kho$([char]0x1EA3)n Google m$([char]0x1EDB)i.`n`n$([char]0x0110)$([char]0x0103)ng nh$([char]0x1EAD)p xong, m$([char]0x1EDF) l$([char]0x1EA1)i Hub n$([char]0x00E0)y v$([char]0x00E0) b$([char]0x1EA5)m 'L$([char]0x01B0)u Acc N$([char]0x00E0)y'.", "$([char]0x0110)ang $([char]0x0110)$([char]0x0103)ng Nh$([char]0x1EAD)p", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

Load-Accounts-UI

$window.ShowDialog() | Out-Null
