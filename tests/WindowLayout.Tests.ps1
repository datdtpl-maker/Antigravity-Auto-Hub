$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'AntigravityHub.ps1') -Preview -NoShow
function Assert($Value,$Name){if(-not $Value){throw $Name};Write-Host "PASS: $Name"}
function Find-Visual($Parent,$Type){
    for($index=0;$index -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent);$index++){
        $child=[Windows.Media.VisualTreeHelper]::GetChild($Parent,$index)
        if($child -is $Type){$child}
        Find-Visual $child $Type
    }
}
try {
    $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.Opacity=0
    $window.Show()
    $window.WindowState='Maximized'
    $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $window.UpdateLayout()
    $headers=@(Find-Visual $accountsContainer ([Windows.Controls.Primitives.DataGridColumnHeader]) | Where-Object {$_.Column -and $_.Column.SortMemberPath -match 'Ring.Value'})
    Assert ($headers.Count -eq 8) 'All quota column headers are realized'
    $area=[Windows.Forms.Screen]::FromHandle([Windows.Interop.WindowInteropHelper]::new($window).Handle).WorkingArea
    foreach($name in @('TxtFooterPath','BtnOpenFolder','TxtAccountCount')){
        $element=$window.FindName($name)
        $bottom=$element.PointToScreen([Windows.Point]::new(0,$element.ActualHeight))
        Write-Host ("BOUNDS: {0} bottom={1} workBottom={2}" -f $name,$bottom.Y,$area.Bottom)
        Assert ($bottom.Y -le $area.Bottom+1) 'Maximized footer and sidebar stay above the taskbar'
    }
    foreach($header in $headers){
        Assert ($header.HorizontalContentAlignment -eq 'Center') 'Quota heading is centered over its ring column'
        $center=$header.Content.TranslatePoint([Windows.Point]::new($header.Content.ActualWidth/2,0),$header).X
        Assert ([math]::Abs($center-$header.ActualWidth/2) -le 2) 'Rendered quota label matches the center of its column'
    }
    foreach($case in @(
        @(0,0,1920,1080,0,0,1920,1032),
        @(-2560,0,0,1440,-2560,60,0,1440),
        @(1920,-1080,3840,0,1980,-1080,3840,0),
        @(0,0,2880,1620,0,0,2880,1548)
    )){
        $monitor=[HubWindowBounds+Rect]::new();$work=[HubWindowBounds+Rect]::new()
        $monitor.Left=$case[0];$monitor.Top=$case[1];$monitor.Right=$case[2];$monitor.Bottom=$case[3]
        $work.Left=$case[4];$work.Top=$case[5];$work.Right=$case[6];$work.Bottom=$case[7]
        $limits=[HubWindowBounds]::Constrain([HubWindowBounds+MinMaxInfo]::new(),$monitor,$work)
        Assert ($limits.MaxPosition.X -eq $work.Left-$monitor.Left -and $limits.MaxPosition.Y -eq $work.Top-$monitor.Top -and $limits.MaxSize.X -eq $work.Right-$work.Left -and $limits.MaxSize.Y -eq $work.Bottom-$work.Top) 'Work-area bounds support secondary monitors, taskbar edges and scaled pixel dimensions'
    }
    $window.WindowState='Normal';$window.Width=1180;$window.Height=640
    $original=@($script:HubAccounts)
    $script:HubAccounts=@(for($index=0;$index -lt 40;$index++){$row=$original[0].PSObject.Copy();$row.AccountName="fixture.$index";$row})
    Update-HubAccountView
    $window.UpdateLayout()
    $scroll=Find-Visual $accountsContainer ([Windows.Controls.ScrollViewer]) | Select-Object -First 1
    Assert ($scroll.ScrollableHeight -gt 0) 'Long account table has a real scrollable viewport'
    $scroll.ScrollToEnd()
    $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $window.UpdateLayout()
    $last=$accountsContainer.Items[$accountsContainer.Items.Count-1]
    $row=$accountsContainer.ItemContainerGenerator.ContainerFromItem($last)
    Assert ($null -ne $row -and $scroll.VerticalOffset -gt 0) 'Scrolling reaches the final account'
    $rowBottom=$row.TranslatePoint([Windows.Point]::new(0,$row.ActualHeight),$accountsContainer).Y
    Assert ($rowBottom -le $accountsContainer.ActualHeight+1) 'Last account row is fully visible at scroll end'
} finally {$window.Close()}
