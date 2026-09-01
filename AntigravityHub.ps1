# ==============================================================================
# ANTIGRAVITY MULTI-ACCOUNT HUB - FONT FIXED & LIVE AUTO-ROTATION
# ==============================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms, Microsoft.VisualBasic

$baseDir = "D:\AntigravityAccounts"
$accDir = Join-Path $baseDir "accounts"
$activeFile = Join-Path $baseDir "current_active.txt"
$geminiTokenPath = "C:\Users\datdt\.gemini\jetski-standalone-oauth-token"
$rotatorScript = Join-Path $baseDir "AutoRotator.ps1"

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

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Antigravity Auto-Account Hub"
        Height="650" Width="820"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        FontFamily="Segoe UI, Arial, sans-serif">

    <Window.Resources>
        <Style TargetType="Button" x:Key="ModernBtn">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#45475A"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Button" x:Key="PrimaryBtn" BasedOn="{StaticResource ModernBtn}">
            <Setter Property="Background" Value="#89B4FA"/>
            <Setter Property="Foreground" Value="#11111B"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#B4BEFE"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Button" x:Key="SuccessBtn" BasedOn="{StaticResource ModernBtn}">
            <Setter Property="Background" Value="#A6E3A1"/>
            <Setter Property="Foreground" Value="#11111B"/>
            <Setter Property="Padding" Value="12,6"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#94E2D5"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Button" x:Key="DangerBtn" BasedOn="{StaticResource ModernBtn}">
            <Setter Property="Background" Value="#F38BA8"/>
            <Setter Property="Foreground" Value="#11111B"/>
            <Setter Property="Padding" Value="8,6"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#EBA0AC"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Button" x:Key="TitleBtn">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Width" Value="36"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#313244"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Button" x:Key="CloseBtn" BasedOn="{StaticResource TitleBtn}">
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#E78284"/>
                    <Setter Property="Foreground" Value="#11111B"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Border Background="#181825"
            CornerRadius="14"
            BorderBrush="#313244"
            BorderThickness="1.5">
        <Border.Effect>
            <DropShadowEffect BlurRadius="25" Color="#000000" Opacity="0.5" ShadowDepth="8"/>
        </Border.Effect>

        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="50"/>  <!-- Titlebar -->
                <RowDefinition Height="95"/>  <!-- Status Banner & Top Toolbar -->
                <RowDefinition Height="*"/>   <!-- Account List -->
                <RowDefinition Height="45"/>  <!-- Footer -->
            </Grid.RowDefinitions>

            <!-- 1. Title Bar -->
            <Border Grid.Row="0" Background="#11111B" CornerRadius="14,14,0,0" x:Name="TitleBar">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
                        <TextBlock Text="â¡" FontSize="16" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBlock Text="Antigravity Auto-Rotation Hub"
                                   Foreground="#CDD6F4"
                                   FontSize="14"
                                   FontWeight="Bold"
                                   VerticalAlignment="Center"/>
                        <Border Background="#1E382B" CornerRadius="4" Padding="8,2" Margin="12,0,0,0" VerticalAlignment="Center">
                            <TextBlock Text="AUTO-PILOT KICH HOAT" Foreground="#A6E3A1" FontSize="11" FontWeight="Bold"/>
                        </Border>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Orientation="Horizontal" Margin="0,0,10,0" VerticalAlignment="Center">
                        <Button x:Name="BtnMinimize" Style="{StaticResource TitleBtn}" Content="â€”"/>
                        <Button x:Name="BtnClose" Style="{StaticResource CloseBtn}" Content="âœ•"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- 2. Header / Actions -->
            <Border Grid.Row="1" Background="#1E1E2E" BorderBrush="#313244" BorderThickness="0,0,0,1" Padding="20,12">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Trang thai He thong: " Foreground="#A6ADC8" FontSize="13" VerticalAlignment="Center"/>
                            <Border x:Name="BadgeDaemon" Background="#1E382B" CornerRadius="4" Padding="8,2" Margin="4,0,0,0" VerticalAlignment="Center">
                                <TextBlock x:Name="TxtDaemonStatus" Text="â— Tu dong dieu phoi ngam (60s)" Foreground="#A6E3A1" FontSize="12" FontWeight="Bold"/>
                            </Border>
                        </StackPanel>
                        <TextBlock Text="He thong tu dong theo doi Quota 5H va tu chuyen tai khoan khi can quota."
                                   Foreground="#6C7086" FontSize="11" Margin="0,5,0,0"/>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="BtnRefresh" Style="{StaticResource ModernBtn}" Content="đŸ”„ Quet Quota" Margin="0,0,8,0"/>
                        <Button x:Name="BtnSaveCurrent" Style="{StaticResource ModernBtn}" Content="đŸ’¾ Luu Acc Nay" Margin="0,0,8,0"/>
                        <Button x:Name="BtnAddAccount" Style="{StaticResource PrimaryBtn}" Content="â• Them Tai Khoan"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- 3. Account List ScrollView -->
            <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="20,15">
                <StackPanel x:Name="AccountsContainer">
                    <!-- Dynamic Cards -->
                </StackPanel>
            </ScrollViewer>

            <!-- 4. Footer -->
            <Border Grid.Row="3" Background="#11111B" CornerRadius="0,0,14,14" Padding="20,0">
                <Grid VerticalAlignment="Center">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Text="Thu muc luu tru: D:\AntigravityAccounts" Foreground="#585B70" FontSize="11" VerticalAlignment="Center"/>
                    <Button x:Name="BtnOpenFolder" Grid.Column="1" Style="{StaticResource TitleBtn}" Width="Auto" Height="Auto" Padding="8,4" Content="đŸ“‚ Mo thu muc" Foreground="#89B4FA" FontSize="11"/>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
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
        $empty.Text = "Chua co tai khoan nao duoc them vao he thong.`nHay bam 'â• Them Tai Khoan' o tren de bat dau."
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
        $email = if ($acc.Email) { $acc.Email } else { "Dang xac thuc..." }

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
        $icon.Text = "đŸ‘¤"
        $icon.FontSize = 15
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
            $bText.Text = "DANG KET NOI"
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
        $qLabel.Text = "Gemini 5H Quota:"
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
            $btnSwitch.Content = "â¡ Chon Thu Cong"
            $btnSwitch.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
            $btnSwitch.Add_Click({
                Switch-ActiveAccount -targetAccountName $currName | Out-Null
                Load-Accounts-UI
            }.GetNewClosure())
            $actions.Children.Add($btnSwitch) | Out-Null
        }

        $btnDel = New-Object System.Windows.Controls.Button
        $btnDel.Style = $window.FindResource("DangerBtn")
        $btnDel.Content = "đŸ—‘ï¸"
        $btnDel.Padding = New-Object System.Windows.Thickness(8, 6, 8, 6)
        $btnDel.ToolTip = "Xoa tai khoan khoi kho xoay"
        $btnDel.Add_Click({
            $ans = [System.Windows.MessageBox]::Show("Ban co chac muon xoa tai khoan '$currName' khoi he thong?", "Xac Nhan", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
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
        [System.Windows.MessageBox]::Show("Khong tim thay token dang nhap hien tai trong Antigravity IDE.`nHay dam bao ban da dang nhap Google tren IDE.", "Thong bao", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $defaultName = "Acc_" + ((Get-ChildItem -Path $accDir -Filter "*.json" -ErrorAction SilentlyContinue).Count + 1)
    $inputName = [Microsoft.VisualBasic.Interaction]::InputBox("Nhap ten goi nho cho tai khoan Google dang dang nhap (vi du: Acc_Chinh, Google_2, Gmail_Phu):", "Luu Tai Khoan Vao Kho", $defaultName)

    if (-not [string]::IsNullOrWhiteSpace($inputName)) {
        $safeName = $inputName.Trim() -replace '[^a-zA-Z0-9_\-]', '_'
        $targetFile = Join-Path $accDir "$safeName.json"
        Copy-Item $geminiTokenPath $targetFile -Force
        Set-Content -Path $activeFile -Value $safeName -Encoding ASCII
        Load-Accounts-UI
        [System.Windows.MessageBox]::Show("Da luu tai khoan '$safeName' vao kho xoay tua thanh cong!", "Thanh Cong", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Event: Add Account (Logout & Sign In new)
$btnAddAccount.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show("Cac buoc them tai khoan moi:`n`n1. He thong se tam cat tai khoan cu.`n2. Antigravity IDE se yeu cau ban dang nhap tai khoan Google moi.`n3. Dang nhap xong, mo lai Hub va bam 'Luu Acc Nay'.`n`nBan muon them tai khoan moi ngay bay gio?", "Them Tai Khoan", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
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
        [System.Windows.MessageBox]::Show("San sang! Hay quay lai Antigravity IDE va tien hanh Dang nhap tai khoan Google moi.`n`nDang nhap xong, mo lai Hub nay va bam 'Luu Acc Nay'.", "Dang Dang Nhap", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Initial Load
Load-Accounts-UI

$window.ShowDialog() | Out-Null
