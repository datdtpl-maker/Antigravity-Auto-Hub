# Presentation and read-only dashboard data. Rotation decisions stay in RotationCore.
$script:HubText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DashboardText.vi.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Get-HubText { param([string]$Key) return [string]$script:HubText.$Key }

function ConvertTo-HubAccount {
    param($Account,[string]$ActiveEmail)
    $known=[bool]$Account.Success
    $active=[bool]($ActiveEmail -and $Account.Email -ieq $ActiveEmail)
    $hasArgon=$known -and $null -ne $Account.ArgonWeekly -and [double]$Account.ArgonWeekly -ge 0
    $argonOk=(-not $hasArgon) -or ([double]$Account.ArgonWeekly -gt .10)
    $argonSwitchOk=(-not $hasArgon) -or ([double]$Account.ArgonWeekly -gt .08)
    $ready=$known -and $Account.Gemini5H -gt .20 -and $Account.GeminiWeekly -gt .10 -and $argonOk
    $key=if(-not $known){'Unknown'}elseif($ready){'Ready'}else{'Low'}
    $verify=[bool]($Account.VerificationUrl -and $Account.ErrorCode -eq 'AccountVerificationRequired')
    $status=if($active){'Active'}elseif($verify){'Verify'}else{$key}
    $five=if($known){[math]::Round($Account.Gemini5H*100,1)}else{0}
    $week=if($known){[math]::Round($Account.GeminiWeekly*100,1)}else{0}
    $argon=if($hasArgon){[math]::Round([double]$Account.ArgonWeekly*100,1)}else{0}
    $fiveText=if($known){'{0:0.#}%' -f $five}else{'N/A'}
    $weekText=if($known){'{0:0.#}%' -f $week}else{'N/A'}
    $argonText=if($hasArgon){'{0:0.#}%' -f $argon}elseif($known -and $Account.ArgonStatus -eq 'Disabled'){Get-HubText ArgonDisabled}else{'N/A'}
    $argonHint=if($known -and $Account.ArgonStatus -eq 'Disabled'){Get-HubText ArgonDisabledHint}elseif($hasArgon -and $Account.ArgonQuotaSource -eq 'ModelCatalog'){Get-HubText ArgonModelHint}elseif($hasArgon){Get-HubText ArgonSummaryHint}else{Get-HubText ArgonUnknownHint}
    [pscustomobject]@{
        AccountName=$Account.AccountName;Email=$Account.Email;TokenPath=$Account.TokenPath
        IsActive=$active;StateKey=$key;StatusText=(Get-HubText $status)
        StatusColor=$(if($active -or $ready){'#7EE2B8'}elseif($key -eq 'Low'){'#F2C97D'}else{'#B4BEC9'})
        FiveValue=[double]$five;WeekValue=[double]$week;ArgonValue=[double]$argon
        FiveText=$fiveText;WeekText=$weekText;ArgonText=$argonText
        ArgonHint=$argonHint;ArgonBarVisibility=$(if($hasArgon){'Visible'}else{'Hidden'})
        FiveColor=$(if($known -and $Account.Gemini5H -gt .20){'#7EE2B8'}else{'#F2C97D'})
        ArgonColor=$(if(-not $hasArgon){'#526171'}elseif([double]$Account.ArgonWeekly -gt .20){'#7EE2B8'}elseif([double]$Account.ArgonWeekly -gt .08){'#93B9EE'}else{'#F2C97D'})
        FiveAccessible=((Get-HubText FiveAccessible) -f $fiveText)
        WeekAccessible=((Get-HubText WeekAccessible) -f $weekText)
        ArgonAccessible=((Get-HubText ArgonAccessible) -f $argonText)
        CanSwitch=($known -and -not $active -and $Account.Gemini5H -gt .20 -and $Account.GeminiWeekly -gt .08 -and $argonSwitchOk)
        VerificationUrl=$Account.VerificationUrl
        VerifyVisibility=$(if($verify){'Visible'}else{'Collapsed'})
        SwitchVisibility=$(if($verify){'Collapsed'}else{'Visible'})
    }
}

function Select-HubAccounts {
    param([object[]]$Accounts,[string]$Search='',[string]$Filter='All')
    foreach($account in $Accounts) {
        if($Search -and ("$($account.AccountName) $($account.Email)").IndexOf($Search.Trim(),[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
        if($Filter -eq 'Ready' -and $account.StateKey -ne 'Ready'){continue}
        if($Filter -eq 'Attention' -and $account.StateKey -eq 'Ready'){continue}
        $account
    }
}

function ConvertFrom-HubLog {
    param([string[]]$Lines)
    $safeReasons=@{}
    if(Get-Command Get-SwitchFailureMessage -ErrorAction SilentlyContinue) {
        foreach($code in @('SwitchBusy','SwitchCooldown','SwitchAgentRunning','Unsaved draft or focused editor; rotation deferred.','An editor is active; switch deferred.','An agent became active; switch deferred.','Previous switch requires reconciliation.','Target quota unavailable or exhausted.','Stored credential does not match the runtime; reconcile before switching.','Debugger unavailable.','New runtime identity not confirmed.','Window changed or user is editing; cannot restore navigation.')) {
            $safeReason=Get-SwitchFailureMessage $code
            $safeReasons['Switch deferred: '+$safeReason]=$safeReason
        }
    }
    foreach($line in $Lines) {
        if($line -notmatch '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (.+)$'){continue}
        $stamp=[datetime]::MinValue
        if(-not [datetime]::TryParseExact($Matches[1],'yyyy-MM-dd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$stamp)){continue}
        $message=$Matches[2];$account='-';$kind='';$detail='';$color='#A6AFBA'
        # Project known events only, not arbitrary provider output or token-bearing text.
        if($message -match '^Verified IDE account: \[([a-zA-Z0-9_.@-]{1,200})\]\.$') {
            $account=$Matches[1];$kind='Confirmed';$detail='ConfirmedDetail';$color='#7EE2B8'
        } elseif($message -match '^Account \[([a-zA-Z0-9_.@-]{1,200})\] prepared for next IDE launch') {
            $account=$Matches[1];$kind='Prepared';$detail='PreparedDetail'
        } elseif($message.StartsWith('Switch deferred: ')) {
            $kind='Deferred';$detail='DeferredDetail';$color='#F2C97D'
        } elseif($message.StartsWith('Switch unverified.')) {
            $kind='Failed';$detail='FailedDetail';$color='#FFADB6'
        } elseif($message -eq 'Low quota; waiting for running agents to finish.') {
            $kind='Waiting';$detail='BusyDetail';$color='#F2C97D'
        } elseif($message -eq 'No healthy account available; waiting for quota reset.') {
            $kind='Waiting';$detail='PoolDetail';$color='#F2C97D'
        } elseif($message -eq 'Rotation paused: previous switch requires verification.') {
            $kind='Failed';$detail='PausedDetail';$color='#FFADB6'
        } elseif($message.StartsWith('Daemon started; interval ')) {
            $kind='Started';$detail='StartedDetail'
        } else {continue}
        $description=Get-HubText $detail
        if($kind -eq 'Deferred' -and $safeReasons.ContainsKey($message)){$description=$safeReasons[$message]}
        [pscustomobject]@{Timestamp=$stamp;TimeText=$stamp.ToString('dd/MM HH:mm:ss');Kind=$kind;Label=(Get-HubText $kind);Account=$account;Detail=$description;Color=$color}
    }
}

function Get-HubSnapshot {
    $accounts=@(Get-AllAccountsQuota)
    $identity=$null;$runtimeError=$null
    try{$identity=Get-RuntimeIdentity}catch{$runtimeError=Get-RuntimeFailureMessage $_}
    $daemon=@(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*AutoRotator.ps1*' -and $_.CommandLine -match '(?i)\s-Daemon(?:\s|$)' }).Count -gt 0
    [pscustomobject]@{Accounts=$accounts;Email=$(if($identity){$identity.Email}else{''});Connected=[bool]$identity;Idle=$(if($identity){$identity.Idle}else{$false});RuntimeError=$runtimeError;Daemon=$daemon;State=(Read-RotationState);At=(Get-Date)}
}

function Update-HubAccountView {
    $filter='All'
    foreach($name in @('FilterReady','FilterAttention')){if($window.FindName($name).IsChecked){$filter=[string]$window.FindName($name).Tag}}
    $rows=@(Select-HubAccounts $script:HubAccounts $window.FindName('SearchAccounts').Text $filter)
    $sorts=@($accountsContainer.Items.SortDescriptions)
    $accountsContainer.ItemsSource=$rows
    foreach($sort in $sorts){$accountsContainer.Items.SortDescriptions.Add($sort)}
    $window.FindName('TxtAccountCount').Text=(Get-HubText Count) -f $rows.Count,@($script:HubAccounts).Count
    $window.FindName('EmptyAccounts').Visibility=if($rows.Count){'Collapsed'}else{'Visible'}
    $window.FindName('EmptyTitle').Text=if(@($script:HubAccounts).Count){Get-HubText NoResults}else{Get-HubText NoAccounts}
    $window.FindName('EmptyDescription').Text=if(@($script:HubAccounts).Count){Get-HubText FilterHint}else{Get-HubText AddHint}
}

function Set-HubSnapshot {
    param($Snapshot)
    $script:HubAccounts=@($Snapshot.Accounts | ForEach-Object {ConvertTo-HubAccount $_ $Snapshot.Email} | Sort-Object @{Expression='IsActive';Descending=$true},AccountName)
    $window.FindName('StatTotal').Text=[string]$script:HubAccounts.Count
    $window.FindName('StatReady').Text=[string]@($script:HubAccounts | Where-Object StateKey -eq Ready).Count
    $window.FindName('StatAttention').Text=[string]@($script:HubAccounts | Where-Object StateKey -ne Ready).Count
    $status=if($Snapshot.State.Status -in @('Switching','NeedsAttention')){Get-HubText AttentionState}
        elseif($Snapshot.RuntimeError){$Snapshot.RuntimeError}
        elseif(-not $Snapshot.Connected){Get-HubText NoRuntime}
        elseif(-not $Snapshot.Daemon){Get-HubText NoDaemon}
        elseif(-not $Snapshot.Idle){Get-HubText Busy}else{Get-HubText Monitoring}
    $window.FindName('TxtDaemonStatus').Text=$status
    $window.FindName('TxtActiveAccount').Text=if($Snapshot.Email){(Get-HubText ActiveAccount) -f $Snapshot.Email}else{Get-HubText Unverified}
    $window.FindName('TxtUpdated').Text=(Get-HubText Updated) -f $Snapshot.At.ToString('HH:mm:ss')
    Update-HubAccountView
}

function Update-HubHistory {
    param([switch]$Force)
    try {
        if($Preview){$events=@($script:PreviewEvents)}else{
            $file=Get-Item -LiteralPath $logFile -ErrorAction SilentlyContinue
            $signature=if($file){"$($file.Length):$($file.LastWriteTimeUtc.Ticks)"}else{'missing'}
            if(-not $Force -and $signature -eq $script:HubLogSignature){return}
            $lines=if($file){@(Get-Content -LiteralPath $logFile -Encoding UTF8 -Tail 5000 -ErrorAction Stop)}else{@()}
            $events=@(ConvertFrom-HubLog $lines)
            $script:HubLogSignature=$signature
        }
        $window.FindName('StatRotations').Text=[string]@($events | Where-Object Kind -eq Confirmed).Count
        $shown=@($events | Sort-Object Timestamp -Descending | Select-Object -First 200)
        $window.FindName('HistoryGrid').ItemsSource=$shown
        $window.FindName('EmptyHistory').Visibility=if($shown.Count){'Collapsed'}else{'Visible'}
        $window.FindName('EmptyHistory').Text=Get-HubText NoHistory
        $window.FindName('TxtHistoryCount').Text=(Get-HubText HistoryCount) -f $shown.Count
    } catch {
        $script:HubLogSignature=$null
        $window.FindName('TxtHistoryCount').Text=Get-HubText HistoryError
    }
}

function Set-HubPage {
    param([string]$Page)
    $history=$Page -eq 'History'
    $window.FindName('AccountsPage').Visibility=if($history){'Collapsed'}else{'Visible'}
    $window.FindName('HistoryPage').Visibility=if($history){'Visible'}else{'Collapsed'}
    $window.FindName('PageTitle').Text=if($history){Get-HubText HistoryTitle}else{Get-HubText AccountsTitle}
    $window.FindName('PageSubtitle').Text=if($history){Get-HubText HistorySubtitle}else{Get-HubText AccountsSubtitle}
    if($history){Update-HubHistory -Force}
}

function Load-Accounts-UI {
    param([switch]$Reconcile)
    if($Preview){return}
    if($script:HubWorker -or $script:loginProtection){$script:HubRefreshQueued=$true;$script:HubRepairQueued=$script:HubRepairQueued -or $Reconcile;return}
    $Reconcile=$Reconcile -or $script:HubRepairQueued
    $script:HubRefreshQueued=$false;$script:HubRepairQueued=$false
    $btnRefresh.IsEnabled=$false;$btnRefresh.Content=Get-HubText Scanning
    # All network/CIM work lives in a separate runspace; WPF is touched only by the timer.
    $script:HubWorker=[powershell]::Create()
    $null=$script:HubWorker.AddScript({param($root,$repair)
        $ErrorActionPreference='Stop'
        . (Join-Path $root 'AutoRotator.ps1')
        . (Join-Path $root 'Dashboard.ps1')
        if($repair){Repair-RotationState | Out-Null}
        Get-HubSnapshot
    }).AddArgument($baseDir).AddArgument([bool]$Reconcile)
    try{$script:HubPending=$script:HubWorker.BeginInvoke()}
    catch{$script:HubWorker.Dispose();$script:HubWorker=$null;$btnRefresh.IsEnabled=$true;$btnRefresh.Content=Get-HubText Scan;$window.FindName('TxtUpdated').Text=Get-HubText ScanError}
}

function Complete-HubRefresh {
    if(-not $script:HubWorker -or -not $script:HubPending.IsCompleted){return}
    try {
        $result=@($script:HubWorker.EndInvoke($script:HubPending))
        if($result.Count -ne 1 -or $script:HubWorker.HadErrors){throw 'Snapshot failed'}
        Set-HubSnapshot $result[0]
    } catch {$window.FindName('TxtUpdated').Text=Get-HubText ScanError}
    finally {
        $script:HubWorker.Dispose();$script:HubWorker=$null;$script:HubPending=$null
        $btnRefresh.IsEnabled=$true;$btnRefresh.Content=Get-HubText Scan
        $script:HubLastRefresh=Get-Date
    }
    if($script:HubRefreshQueued){Load-Accounts-UI}
}

function Invoke-HubAccountAction {
    param([string]$Action,$Account)
    if($Preview -or -not $Account -or $script:loginProtection){return}
    switch($Action) {
        'Switch' {
            if(-not $Account.CanSwitch){return}
            # The existing engine rechecks quota, drafts, running tasks and identity.
            $window.FindName('TxtDaemonStatus').Text=Get-HubText Switching
            $switched=Switch-ActiveAccount -targetAccountName $Account.AccountName -Notify
            $window.FindName('TxtDaemonStatus').Text=if($switched){Get-HubText SwitchSuccess}else{$script:LastSwitchMessage}
            $window.FindName('TxtDaemonStatus').ToolTip=$window.FindName('TxtDaemonStatus').Text
            Load-Accounts-UI
            Update-HubHistory -Force
        }
        'Verify' {
            if(-not [AntigravityAccountLogin]::IsVerificationUrl($Account.VerificationUrl)){return}
            try{$browser=[Diagnostics.ProcessStartInfo]::new($Account.VerificationUrl);$browser.UseShellExecute=$true;[Diagnostics.Process]::Start($browser) | Out-Null}
            catch{Show-AccountLoginFailure 'LoginBrowserFailed'}
        }
        'Delete' {
            $answer=[Windows.MessageBox]::Show($window,((Get-HubText DeleteQuestion) -f $Account.AccountName),(Get-HubText DeleteTitle),[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question)
            if($answer -ne [Windows.MessageBoxResult]::Yes){return}
            try {
                Remove-Item -LiteralPath $Account.TokenPath -Force -ErrorAction Stop
                $script:HubAccounts=@($script:HubAccounts | Where-Object AccountName -ne $Account.AccountName)
                $window.FindName('StatTotal').Text=[string]$script:HubAccounts.Count
                $window.FindName('StatReady').Text=[string]@($script:HubAccounts | Where-Object StateKey -eq Ready).Count
                $window.FindName('StatAttention').Text=[string]@($script:HubAccounts | Where-Object StateKey -ne Ready).Count
                Update-HubAccountView
                Load-Accounts-UI
            } catch {[Windows.MessageBox]::Show($window,(Get-HubText DeleteError),(Get-HubText DeleteTitle)) | Out-Null}
        }
    }
}

function Update-HubLayout {
    param([double]$Height)
    $compact=$Height -lt 740
    $window.FindName('PageSubtitle').Visibility=if($compact){'Collapsed'}else{'Visible'}
    foreach($name in @('HintTotal','HintReady','HintAttention','HintRotations')) {
        $window.FindName($name).Visibility=if($compact){'Collapsed'}else{'Visible'}
    }
    $window.FindName('ContentArea').Margin=if($compact){[Windows.Thickness]::new(22,14,22,10)}else{[Windows.Thickness]::new(26,24,26,16)}
    $window.FindName('HeaderArea').Margin=if($compact){[Windows.Thickness]::new(0,0,0,10)}else{[Windows.Thickness]::new(0,0,0,18)}
    $window.FindName('StatsArea').Margin=if($compact){[Windows.Thickness]::new(0,0,-12,10)}else{[Windows.Thickness]::new(0,0,-12,18)}
    $window.FindName('StatusArea').Margin=if($compact){[Windows.Thickness]::new(0,0,0,10)}else{[Windows.Thickness]::new(0,0,0,18)}
}

function Initialize-HubDashboard {
    $script:HubAccounts=@();$script:HubLastRefresh=Get-Date
    $script:HubWorker=$null;$script:HubLogSignature=$null
    Update-HubLayout $window.Height
    $window.Add_SizeChanged({Update-HubLayout $window.ActualHeight})
    $window.FindName('NavAccounts').Add_Checked({Set-HubPage Accounts})
    $window.FindName('NavHistory').Add_Checked({Set-HubPage History})
    $window.FindName('SearchAccounts').Add_TextChanged({Update-HubAccountView})
    foreach($name in @('FilterAll','FilterReady','FilterAttention')){$window.FindName($name).Add_Checked({Update-HubAccountView})}
    $window.FindName('BtnRefreshHistory').Add_Click({Update-HubHistory -Force})
    $accountsContainer.AddHandler([Windows.Controls.Button]::ClickEvent,[Windows.RoutedEventHandler]{param($sender,$event)
        $button=$event.OriginalSource
        while($button -and $button -isnot [Windows.Controls.Button]) {
            if($button -isnot [Windows.Media.Visual]){return}
            $button=[Windows.Media.VisualTreeHelper]::GetParent($button)
        }
        if($button -is [Windows.Controls.Button]){Invoke-HubAccountAction ([string]$button.Tag) $button.DataContext;$event.Handled=$true}
    })
    if($Preview){
        $btnAddAccount.IsEnabled=$false;$btnSaveCurrent.IsEnabled=$false;$btnRefresh.IsEnabled=$false
        $script:PreviewEvents=@(ConvertFrom-HubLog @('[2026-10-13 09:42:16] Verified IDE account: [studio.team].','[2026-10-13 09:41:42] Low quota; waiting for running agents to finish.','[2026-10-13 08:18:03] Verified IDE account: [design.workspace].','[2026-10-13 07:30:00] Daemon started; interval 25s after each completed scan.'))
        $sample=@();$index=0
        foreach($name in @('studio.team','design.workspace','product.lab','research.team','personal','backup.account')){
            $five=@(.76,.98,.65,.12,.88,0)[$index];$week=@(.82,.94,.57,.43,.69,0)[$index];$argon=@(.64,.91,.52,.06,-1,0)[$index]
            $sample+=[pscustomobject]@{AccountName=$name;Email="$name@example.test";Success=($index -ne 5);Gemini5H=$five;GeminiWeekly=$week;ArgonWeekly=$argon;TokenPath='';VerificationUrl=$null;ErrorCode=''};$index++
        }
        Set-HubSnapshot ([pscustomobject]@{Accounts=$sample;Email='studio.team@example.test';Connected=$true;Idle=$true;Daemon=$true;State=$null;At=(Get-Date)})
        $window.FindName('PageSubtitle').Text=Get-HubText Preview
        $txtFooterPath.Text=Get-HubText Preview
    } else {
        # Show the real pool count immediately without waiting for network requests.
        $script:HubAccounts=@(Get-ChildItem -LiteralPath $accDir -Filter '*.json' -File | ForEach-Object {ConvertTo-HubAccount ([pscustomobject]@{AccountName=$_.BaseName;Email='';TokenPath=$_.FullName;Success=$false}) ''})
        $window.FindName('StatTotal').Text=[string]$script:HubAccounts.Count
        Update-HubAccountView
    }
    Update-HubHistory -Force
    $script:HubTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:HubTimer.Interval=[timespan]::FromMilliseconds(250)
    $script:HubLogTick=Get-Date
    $script:HubTimer.Add_Tick({
        Complete-HubRefresh
        if(((Get-Date)-$script:HubLogTick).TotalSeconds -ge 5){Update-HubHistory;$script:HubLogTick=Get-Date}
        if(-not $Preview -and -not $script:HubWorker -and -not $script:loginProtection -and ($script:HubRefreshQueued -or ((Get-Date)-$script:HubLastRefresh).TotalSeconds -ge 60)){Load-Accounts-UI}
    })
    $script:HubTimer.Start()
    $window.Add_Closed({
        $script:HubTimer.Stop()
        if($script:HubWorker){$script:HubWorker.Stop();$script:HubWorker.Dispose();$script:HubWorker=$null}
    })
    Load-Accounts-UI
}
