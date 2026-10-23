$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'AntigravityHub.ps1') -Preview -NoShow
function Assert($Value,$Name){if(-not $Value){throw $Name};Write-Host "PASS: $Name"}
function Layout([int]$Width=1220,[int]$Height=800){
    Update-HubLayout $Height
    $window.Content.Measure([Windows.Size]::new($Width,$Height))
    $window.Content.Arrange([Windows.Rect]::new(0,0,$Width,$Height))
    $window.Content.UpdateLayout()
    $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $window.Content.UpdateLayout()
}
$fixture=Join-Path $repo ('work\dashboard-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
    Assert ($window.FindName('StatTotal').Text -eq '6' -and $window.FindName('StatReady').Text -eq '4' -and $window.FindName('StatAttention').Text -eq '2') 'Dashboard totals cover the entire account pool'
    Assert ($accountsContainer.Items[0].IsActive -and $accountsContainer.Items.Count -eq 6) 'Verified active identity is pinned first'
    Assert ($accountsContainer.Items[0].ArgonText -eq '64%' -and $accountsContainer.Items[0].ArgonValue -eq 64) 'Dashboard projects Gemini 4 Argon quota percentage'
    $unknown=$script:HubAccounts | Where-Object StateKey -eq Unknown
    Assert ($unknown.FiveText -eq 'N/A' -and $unknown.ArgonText -eq 'N/A' -and -not $unknown.CanSwitch) 'Unknown quota stays unavailable, never displayed as exhausted'
    $argonLow=ConvertTo-HubAccount ([pscustomobject]@{AccountName='argon.low';Email='argon.low@example.test';Success=$true;Gemini5H=.95;GeminiWeekly=.90;ArgonWeekly=.05;TokenPath='';VerificationUrl=$null;ErrorCode=''}) ''
    Assert ($argonLow.StateKey -eq 'Low' -and $argonLow.ArgonText -eq '5%' -and -not $argonLow.CanSwitch) 'Low Gemini 4 Argon quota marks account as needing attention and blocks manual switch'
    $argonDisabled=ConvertTo-HubAccount ([pscustomobject]@{AccountName='argon.disabled';Success=$true;Gemini5H=.9;GeminiWeekly=.9;ArgonWeekly=-1;ArgonStatus='Disabled'}) ''
    Assert ($argonDisabled.ArgonText -eq (Get-HubText ArgonDisabled) -and $argonDisabled.ArgonBarVisibility -eq 'Hidden' -and $argonDisabled.ArgonHint -eq (Get-HubText ArgonDisabledHint)) 'Disabled Argon has an explicit label and explanation instead of a zero quota bar'
    $window.FindName('FilterReady').IsChecked=$true
    Assert ($accountsContainer.Items.Count -eq 4 -and $window.FindName('StatTotal').Text -eq '6') 'Ready filter does not alter pool totals'
    $window.FindName('SearchAccounts').Text='PRODUCT'
    Assert ($accountsContainer.Items.Count -eq 1 -and $accountsContainer.Items[0].AccountName -eq 'product.lab') 'Search matches account names without case sensitivity'
    $window.FindName('SearchAccounts').Text='['
    Assert ($accountsContainer.Items.Count -eq 0 -and $window.FindName('EmptyAccounts').Visibility -eq 'Visible') 'Search treats metacharacters literally and shows a no-results state'
    $window.FindName('SearchAccounts').Text=''
    $window.FindName('FilterAttention').IsChecked=$true
    Assert ($accountsContainer.Items.Count -eq 2) 'Attention filter includes low and unavailable quota'
    $window.FindName('FilterAll').IsChecked=$true
    $accountsContainer.Items.SortDescriptions.Add([ComponentModel.SortDescription]::new('FiveValue',[ComponentModel.ListSortDirection]::Descending))
    Update-HubAccountView
    Assert ($accountsContainer.Items.SortDescriptions.Count -eq 1 -and $accountsContainer.Items[0].FiveValue -eq 98) 'Column sorting survives data refresh'
    $window.FindName('NavHistory').IsChecked=$true
    Assert ($window.FindName('HistoryPage').Visibility -eq 'Visible' -and $window.FindName('AccountsPage').Visibility -eq 'Collapsed') 'History navigation opens the event table'
    Assert ($window.FindName('HistoryGrid').Items.Count -eq 4 -and $window.FindName('StatRotations').Text -eq '2') 'Rotation counter counts only verified events'
    $events=@(ConvertFrom-HubLog @('[2026-10-13 01:02:03] Switch deferred: https://private.invalid/?access_token=SECRET_SENTINEL','[invalid] Verified IDE account: [bad].','[2026-10-13 01:02:04] unknown SECRET_SENTINEL','[2026-10-13 01:02:05] Account [fixture] prepared for next IDE launch (not yet verified).'))
    Assert ($events.Count -eq 2 -and ($events | ConvertTo-Json) -notmatch 'SECRET_SENTINEL|private.invalid') 'History skips unknown messages and never displays raw provider details'
    $window.FindName('NavAccounts').IsChecked=$true
    Layout
    function Find-Buttons($Parent){
        for($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent);$i++){
            $child=[Windows.Media.VisualTreeHelper]::GetChild($Parent,$i)
            if($child -is [Windows.Controls.Button] -and $child.Tag){$child}
            Find-Buttons $child
        }
    }
    $buttons=@(Find-Buttons $accountsContainer)
    $script:CapturedAction=$null
    function Invoke-HubAccountAction {param($Action,$Account) $script:CapturedAction=@($Action,$Account.AccountName)}
    $button=$buttons | Where-Object {$_.Tag -eq 'Switch' -and $_.IsEnabled} | Select-Object -First 1
    Assert ([bool]$button) 'Account actions are rendered as native buttons'
    $button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent,$button))
    Assert ($script:CapturedAction[0] -eq 'Switch' -and $script:CapturedAction[1] -eq $button.DataContext.AccountName) 'Routed account action targets the clicked row'
    Layout 1040 640
    $refresh=$window.FindName('BtnRefresh')
    $search=$window.FindName('SearchAccounts')
    $point=$refresh.TranslatePoint([Windows.Point]::new(0,0),$window.Content)
    Assert ($point.X+$refresh.ActualWidth -le 1040 -and $point.Y+$refresh.ActualHeight -le 640 -and $search.ActualWidth -ge 200) 'Compact desktop layout keeps the search and refresh controls reachable'
    $last=$accountsContainer.Items[$accountsContainer.Items.Count-1]
    $accountsContainer.ScrollIntoView($last)
    Layout 1040 640
    Assert ($null -ne $accountsContainer.ItemContainerGenerator.ContainerFromItem($last)) 'Virtualized account list can scroll to the last account'
    $verify=ConvertTo-HubAccount ([pscustomobject]@{AccountName='verify';Email='verify@example.test';Success=$false;ErrorCode='AccountVerificationRequired';VerificationUrl='https://accounts.google.com/signin/continue?fixture=1'}) ''
    Assert ($verify.VerifyVisibility -eq 'Visible' -and $verify.SwitchVisibility -eq 'Collapsed' -and -not $verify.CanSwitch) 'Verification-required account offers verification instead of switching'

    # Exercise the real background runspace pipeline with an isolated engine fixture.
    Copy-Item (Join-Path $repo 'Dashboard.ps1'),(Join-Path $repo 'DashboardText.vi.json') -Destination $fixture
    @'
function Get-AllAccountsQuota { Start-Sleep -Milliseconds 600; [pscustomobject]@{AccountName='worker.fixture';Email='worker@example.test';Success=$true;Gemini5H=.8;GeminiWeekly=.9;ArgonWeekly=.75;TokenPath='';VerificationUrl=$null;ErrorCode=''} }
function Get-RuntimeIdentity { [pscustomobject]@{Email='worker@example.test';Idle=$true} }
function Read-RotationState { $null }
function Get-CimInstance { param($ClassName,$Filter,$ErrorAction) }
function Repair-RotationState { $true }
'@ | Set-Content -LiteralPath (Join-Path $fixture 'AutoRotator.ps1') -Encoding ASCII
    $Preview=$false;$baseDir=$fixture;$logFile=Join-Path $fixture 'rotator.log'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Load-Accounts-UI
    Assert ($clock.ElapsedMilliseconds -lt 500 -and -not $btnRefresh.IsEnabled) 'Quota refresh starts asynchronously and disables repeat requests'
    Load-Accounts-UI -Reconcile
    Assert ($script:HubRefreshQueued -and $script:HubRepairQueued) 'Refresh requested during a scan is queued, not lost'
    $deadline=(Get-Date).AddSeconds(15)
    while($script:HubWorker -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 50;Complete-HubRefresh}
    Assert (-not $script:HubWorker -and $accountsContainer.Items.Count -eq 1 -and $accountsContainer.Items[0].AccountName -eq 'worker.fixture' -and $accountsContainer.Items[0].ArgonText -eq '75%' -and $btnRefresh.IsEnabled) 'Background result updates the dashboard and releases its worker'
    'function Get-AllAccountsQuota { throw "fixture failure" }' | Set-Content -LiteralPath (Join-Path $fixture 'AutoRotator.ps1') -Encoding ASCII
    Load-Accounts-UI
    $deadline=(Get-Date).AddSeconds(10)
    while($script:HubWorker -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 50;Complete-HubRefresh}
    Assert ($window.FindName('TxtUpdated').Text -eq (Get-HubText ScanError) -and $accountsContainer.Items.Count -eq 1 -and $btnRefresh.IsEnabled) 'Failed scan preserves previous data and shows a stale-data message'
    '[2026-10-13 10:00:00] Verified IDE account: [fixture].' | Set-Content -LiteralPath $logFile -Encoding UTF8
    Update-HubHistory -Force
    Assert ($window.FindName('HistoryGrid').Items.Count -eq 1 -and $window.FindName('StatRotations').Text -eq '1') 'History reads real log events without quota network calls'
    Remove-Item -LiteralPath $logFile
    Update-HubHistory -Force
    Assert ($window.FindName('HistoryGrid').Items.Count -eq 0 -and $window.FindName('EmptyHistory').Visibility -eq 'Visible') 'Missing log displays a valid empty history'
    $script:HubAccounts=@();Update-HubAccountView
    Assert ($window.FindName('EmptyAccounts').Visibility -eq 'Visible' -and $window.FindName('EmptyTitle').Text -eq (Get-HubText NoAccounts)) 'Empty account pool explains how to get started'
} finally {
    $window.Close()
    $resolved=[IO.Path]::GetFullPath($fixture)
    if($resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $repo 'work'))+'\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^dashboard-test-[a-f0-9]{32}$') {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
