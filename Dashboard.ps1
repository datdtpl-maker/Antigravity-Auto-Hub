# Presentation and read-only dashboard data. Rotation decisions stay in RotationCore.
$script:HubText=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'DashboardText.vi.json') -Raw -Encoding UTF8 | ConvertFrom-Json
function Get-HubText { param([string]$Key) return [string]$script:HubText.$Key }

function New-HubQuotaRing {
    param([double]$Fraction=-1,[string]$Hint='',[string]$Status='Unknown')
    $known=$Status -eq 'Available' -and $Fraction -ge 0 -and $Fraction -le 1 -and -not [double]::IsNaN($Fraction)
    $geometry='M 24,4'
    if($known -and $Fraction -ge 1){$geometry='M 24,4 A 20,20 0 1 1 24,44 A 20,20 0 1 1 24,4'}
    elseif($known -and $Fraction -gt 0){
        $angle=2*[math]::PI*$Fraction
        $endX=24+20*[math]::Sin($angle);$endY=24-20*[math]::Cos($angle)
        $geometry=[string]::Format([Globalization.CultureInfo]::InvariantCulture,'M 24,4 A 20,20 0 {0} 1 {1:0.####},{2:0.####}',[int]($Fraction -gt .5),$endX,$endY)
    }
    $text=if($known){'{0:0.#}%' -f ($Fraction*100)}else{[string][char]0x2014}
    [pscustomobject]@{Text=$text;Value=$(if($known){$Fraction*100}else{-1});Geometry=$geometry;Hint=$Hint;Accessible="$text. $Hint";Dash=$(if($known){'1,0'}else{'2,2'});Color=$(if(-not $known){'#64748B'}elseif($Fraction -le .10){'#B42318'}elseif($Fraction -le .20){'#9A6700'}else{'#087F73'})}
}

function Format-HubQuotaReset {
    param([string]$ResetAt)
    $parsed=[datetimeoffset]::MinValue
    if($ResetAt -and [datetimeoffset]::TryParse($ResetAt,[ref]$parsed)){
        $local=$parsed.ToLocalTime().ToString('dd/MM HH:mm')
        $diff=$parsed.ToUniversalTime() - [datetime]::UtcNow
        if($diff.TotalMinutes -le 0){ return (Get-HubText ResetSoon) }
        $cd=if($diff.TotalDays -ge 1){'{0}n {1}g' -f [int][math]::Floor($diff.TotalDays),$diff.Hours}elseif($diff.TotalHours -ge 1){'{0}g {1}p' -f [int][math]::Floor($diff.TotalHours),$diff.Minutes}else{'{0}p' -f [math]::Max(1,[int][math]::Floor($diff.TotalMinutes))}
        return ((Get-HubText ResetCountdown) -f $cd,$local)
    }
    return Get-HubText ResetUnknown
}

function Get-HubModelRing {
    param($Account,[string]$Family)
    $variants=@($Account.ModelQuotas | Where-Object Family -eq $Family)
    $enabled=@($variants | Where-Object Status -eq 'Available')
    $unknown=@($variants | Where-Object Status -eq 'Unknown')
    $status='Unknown';$fraction=-1.0
    if($variants.Count -gt 0 -and @($variants | Where-Object Status -ne 'Disabled').Count -eq 0){$status='Disabled'}
    elseif($enabled.Count -gt 0 -and $unknown.Count -eq 0){$status='Available';$fraction=[double]($enabled | Measure-Object Remaining -Minimum).Minimum}
    $lines=@((Get-HubText ModelRingHint))
    foreach($variant in $variants){
        $value=if($variant.Status -eq 'Available'){'{0:0.#}%' -f ($variant.Remaining*100)}elseif($variant.Status -eq 'Disabled'){Get-HubText ModelDisabled}else{Get-HubText ModelUnknown}
        $lines+="$($variant.Name): $value | $(Format-HubQuotaReset $variant.ResetAt)"
    }
    if(-not $variants.Count){$lines+=Get-HubText ModelMissing}
    if($Family -in @('Opus','Sonnet','GptOss')){$lines+=Get-HubText SharedQuotaHint}
    if($Family -eq 'Argon' -and -not $variants.Count -and $Account.Success -and $null -ne $Account.ArgonWeekly -and $Account.ArgonWeekly -ge 0){
        $fraction=[double]$Account.ArgonWeekly;$status='Available';$lines=@((Get-HubText ArgonSummaryHint))
    }
    New-HubQuotaRing $fraction ($lines -join "`n") $status
}

function Get-HubQuotaDetails {
    param($Account)
    $lines=@($Account.AccountName,$Account.Email,(Get-HubText DetailsHint),'', (Get-HubText GroupQuotas))
    foreach($group in $Account.QuotaGroups){
        $value=if($group.Remaining -ge 0){'{0:0.#}%' -f ($group.Remaining*100)}else{Get-HubText ModelUnknown}
        $lines+="$($group.Name) / $($group.Window): $value | $(Format-HubQuotaReset $group.ResetAt)"
    }
    $lines+='';$lines+=Get-HubText AllModels
    foreach($model in $Account.ModelQuotas){
        $value=if($model.Status -eq 'Available'){'{0:0.#}%' -f ($model.Remaining*100)}elseif($model.Status -eq 'Disabled'){Get-HubText ModelDisabled}else{Get-HubText ModelUnknown}
        $lines+="$($model.Name): $value | $(Format-HubQuotaReset $model.ResetAt)"
    }
    if(-not @($Account.ModelQuotas).Count){$lines+=Get-HubText ModelMissing}
    $lines+='';$lines+=((Get-HubText CheckedAt) -f $Account.CheckedAt)
    return $lines -join "`r`n"
}

function ConvertTo-HubAccount {
    param($Account,[string]$ActiveEmail,[string]$SelectedModel='')
    $known=[bool]$Account.Success
    $active=[bool]($ActiveEmail -and $Account.Email -ieq $ActiveEmail)
    $hasArgon=$known -and $null -ne $Account.ArgonWeekly -and [double]$Account.ArgonWeekly -ge 0
    $argonOk=(-not $hasArgon) -or ([double]$Account.ArgonWeekly -gt .10)
    $argonSwitchOk=(-not $hasArgon) -or ([double]$Account.ArgonWeekly -gt .08)
    $ready=$known -and $Account.Gemini5H -gt .20 -and $Account.GeminiWeekly -gt .10 -and $argonOk
    $modelQuota=$null
    if($SelectedModel){
        $modelQuota=Get-SelectedModelQuota $Account $SelectedModel
        $ready=$modelQuota.Known -and $modelQuota.Remaining -gt .20
    }
    $key=if(($SelectedModel -and -not $modelQuota.Known) -or -not $known){'Unknown'}elseif($ready){'Ready'}else{'Low'}
    $verify=[bool]($Account.VerificationUrl -and $Account.ErrorCode -eq 'AccountVerificationRequired')
    $status=if($active){'Active'}elseif($verify){'Verify'}else{$key}
    $five=if($known){[math]::Round($Account.Gemini5H*100,1)}else{0}
    $week=if($known){[math]::Round($Account.GeminiWeekly*100,1)}else{0}
    $argon=if($hasArgon){[math]::Round([double]$Account.ArgonWeekly*100,1)}else{0}
    $fiveText=if($known){'{0:0.#}%' -f $five}else{'N/A'}
    $weekText=if($known){'{0:0.#}%' -f $week}else{'N/A'}
    $argonText=if($hasArgon){'{0:0.#}%' -f $argon}elseif($known -and $Account.ArgonStatus -eq 'Disabled'){Get-HubText ArgonDisabled}else{'N/A'}
    $argonHint=if($known -and $Account.ArgonStatus -eq 'Disabled'){Get-HubText ArgonDisabledHint}elseif($hasArgon -and $Account.ArgonQuotaSource -eq 'ModelCatalog'){Get-HubText ArgonModelHint}elseif($hasArgon){Get-HubText ArgonSummaryHint}else{Get-HubText ArgonUnknownHint}
    $planText=if($Account.Plan -in @('Free','Pro','Ultra')){[string]$Account.Plan}else{Get-HubText PlanUnknown}
    $planHint=if($Account.PlanSource -eq 'PaidTier'){Get-HubText PlanPaidHint}elseif($Account.PlanSource -eq 'CurrentTier'){Get-HubText PlanCurrentHint}else{Get-HubText PlanUnknownHint}
    [pscustomobject]@{
        AccountName=$Account.AccountName;Email=$Account.Email;TokenPath=$Account.TokenPath
        PlanText=$planText;PlanHint=$planHint
        FiveRing=(New-HubQuotaRing $(if($known){$Account.Gemini5H}else{-1}) ((Get-HubText FiveAccessible) -f $fiveText) $(if($known){'Available'}else{'Unknown'}))
        WeekRing=(New-HubQuotaRing $(if($known){$Account.GeminiWeekly}else{-1}) ((Get-HubText WeekAccessible) -f $weekText) $(if($known){'Available'}else{'Unknown'}))
        FlashRing=(Get-HubModelRing $Account 'Flash');ArgonRing=(Get-HubModelRing $Account 'Argon')
        HydrogenRing=(Get-HubModelRing $Account 'Hydrogen');CarbonRing=(Get-HubModelRing $Account 'Carbon')
        OpusRing=(Get-HubModelRing $Account 'Opus');SonnetRing=(Get-HubModelRing $Account 'Sonnet')
        GptOssRing=(Get-HubModelRing $Account 'GptOss')
        QuotaGroups=$Account.QuotaGroups;ModelQuotas=$Account.ModelQuotas
        QuotaDetails=(Get-HubQuotaDetails $Account)
        IsActive=$active;StateKey=$key;StatusText=(Get-HubText $status)
        StatusColor=$(if($active -or $ready){'#087F73'}elseif($key -eq 'Low'){'#9A6700'}else{'#64748B'})
        FiveValue=[double]$five;WeekValue=[double]$week;ArgonValue=[double]$argon
        FiveText=$fiveText;WeekText=$weekText;ArgonText=$argonText
        ArgonHint=$argonHint;ArgonBarVisibility=$(if($hasArgon){'Visible'}else{'Hidden'})
        FiveColor=$(if($known -and $Account.Gemini5H -gt .20){'#7EE2B8'}else{'#F2C97D'})
        ArgonColor=$(if(-not $hasArgon){'#526171'}elseif([double]$Account.ArgonWeekly -gt .20){'#7EE2B8'}elseif([double]$Account.ArgonWeekly -gt .08){'#93B9EE'}else{'#F2C97D'})
        FiveAccessible=((Get-HubText FiveAccessible) -f $fiveText)
        WeekAccessible=((Get-HubText WeekAccessible) -f $weekText)
        ArgonAccessible=((Get-HubText ArgonAccessible) -f $argonText)
        CanSwitch=$(if($SelectedModel){$ready -and -not $active}else{$known -and -not $active -and $Account.Gemini5H -gt .20 -and $Account.GeminiWeekly -gt .08 -and $argonSwitchOk})
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
        $message=$Matches[2];$account='-';$kind='';$detail='';$color='#52647C'
        # Project known events only, not arbitrary provider output or token-bearing text.
        if($message -match '^Verified IDE account: \[([a-zA-Z0-9_.@-]{1,200})\]\.$') {
            $account=$Matches[1];$kind='Confirmed';$detail='ConfirmedDetail';$color='#087F73'
        } elseif($message -match '^Account \[([a-zA-Z0-9_.@-]{1,200})\] prepared for next IDE launch') {
            $account=$Matches[1];$kind='Prepared';$detail='PreparedDetail'
        } elseif($message.StartsWith('Switch deferred: ')) {
            $kind='Deferred';$detail='DeferredDetail';$color='#9A6700'
        } elseif($message.StartsWith('Switch unverified.')) {
            $kind='Failed';$detail='FailedDetail';$color='#B42318'
        } elseif($message -eq 'Low quota; waiting for running agents to finish.') {
            $kind='Waiting';$detail='BusyDetail';$color='#9A6700'
        } elseif($message -eq 'No healthy account available; waiting for quota reset.') {
            $kind='Waiting';$detail='PoolDetail';$color='#9A6700'
        } elseif($message -eq 'Selected model unknown or ambiguous; no rotation.') {
            $kind='Waiting';$detail='ModelRotationUnknown';$color='#9A6700'
        } elseif($message -eq 'Selected model quota unavailable; no rotation.') {
            $kind='Waiting';$detail='ModelQuotaUnknown';$color='#9A6700'
        } elseif($message -eq 'Rotation paused: previous switch requires verification.') {
            $kind='Failed';$detail='PausedDetail';$color='#B42318'
        } elseif($message.StartsWith('Daemon started; interval ')) {
            $kind='Started';$detail='StartedDetail'
        } else {continue}
        $description=Get-HubText $detail
        if($kind -eq 'Deferred' -and $safeReasons.ContainsKey($message)){$description=$safeReasons[$message]}
        [pscustomobject]@{Timestamp=$stamp;TimeText=$stamp.ToString('dd/MM HH:mm:ss');Kind=$kind;Label=(Get-HubText $kind);Account=$account;Detail=$description;Color=$color}
    }
}

function Get-HubSnapshot {
    $accounts=@(Get-AllAccountsQuota -IncludeModels)
    $identity=$null;$runtimeError=$null
    try{$identity=Get-RuntimeIdentity}catch{$runtimeError=Get-RuntimeFailureMessage $_}
    $selectedModel=''
    if($identity -and $identity.Runtimes){try{$selectedModel=Get-RuntimeSelectedModel $identity.Runtimes[0]}catch{}}
    $daemon=@(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*AutoRotator.ps1*' -and $_.CommandLine -match '(?i)\s-Daemon(?:\s|$)' }).Count -gt 0
    [pscustomobject]@{Accounts=$accounts;SelectedModel=$selectedModel;Email=$(if($identity){$identity.Email}else{''});Connected=[bool]$identity;Idle=$(if($identity){$identity.Idle}else{$false});RuntimeError=$runtimeError;Daemon=$daemon;State=(Read-RotationState);At=(Get-Date)}
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
    $script:HubAccounts=@($Snapshot.Accounts | ForEach-Object {ConvertTo-HubAccount $_ $Snapshot.Email $Snapshot.SelectedModel} | Sort-Object @{Expression='IsActive';Descending=$true},AccountName)
    $window.FindName('StatTotal').Text=[string]$script:HubAccounts.Count
    $window.FindName('StatReady').Text=[string]@($script:HubAccounts | Where-Object StateKey -eq Ready).Count
    $window.FindName('StatAttention').Text=[string]@($script:HubAccounts | Where-Object StateKey -ne Ready).Count
    $cfg=if(Get-Command Get-HubConfig -ErrorAction SilentlyContinue){Get-HubConfig}else{[pscustomobject]@{AutoRotationEnabled=$true;MinQuotaPercent=20;CooldownSeconds=120;EnableNotifications=$true}}
    $status=if(-not $cfg.AutoRotationEnabled){Get-HubText PausedState}
        elseif($Snapshot.State.Status -in @('Switching','NeedsAttention')){Get-HubText AttentionState}
        elseif($Snapshot.RuntimeError){$Snapshot.RuntimeError}
        elseif(-not $Snapshot.Connected){Get-HubText NoRuntime}
        elseif(-not $Snapshot.Daemon){Get-HubText NoDaemon}
        elseif(-not $Snapshot.SelectedModel -and -not $Preview){Get-HubText ModelRotationUnknown}
        elseif(-not $Snapshot.Idle){Get-HubText Busy}else{Get-HubText Monitoring}
    $window.FindName('PageSubtitle').Text=if($Snapshot.SelectedModel){(Get-HubText RotationModel) -f $Snapshot.SelectedModel}else{Get-HubText AccountsSubtitle}
    $window.FindName('HintReady').Text=if($Snapshot.SelectedModel){Get-HubText SelectedModelReady}else{Get-HubText LegacyReady}
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

function Update-HubSettingsUi {
    $cfg=if(Get-Command Get-HubConfig -ErrorAction SilentlyContinue){Get-HubConfig}else{[pscustomobject]@{AutoRotationEnabled=$true;MinQuotaPercent=20;CooldownSeconds=120;EnableNotifications=$true}}
    $enabled=[bool]$cfg.AutoRotationEnabled
    $btnToggle=$window.FindName('BtnToggleRotation')
    if($btnToggle){$btnToggle.Content=if($enabled){Get-HubText BtnPauseRotation}else{Get-HubText BtnResumeRotation}}
    $area=$window.FindName('StatusArea');$dot=$window.FindName('StatusDot')
    if($area -and $dot){
        if($enabled){$area.Background='#ECFDF5';$area.BorderBrush='#A7F3D0';$dot.Fill='#10B981'}
        else{$area.Background='#FFFBEB';$area.BorderBrush='#FDE68A';$dot.Fill='#D97706'}
    }
    $pt=$window.FindName('TxtPolicyThreshold');if($pt){$pt.Text="Model < $($cfg.MinQuotaPercent)%"}
    $pg=$window.FindName('TxtPolicyTarget');if($pg){$pg.Text="Acc > $($cfg.MinQuotaPercent)%"}
    $chkAuto=$window.FindName('ChkAutoRotate');if($chkAuto){$chkAuto.IsChecked=$enabled}
    $chkNotif=$window.FindName('ChkNotifications');if($chkNotif){$chkNotif.IsChecked=[bool]$cfg.EnableNotifications}
    $cboThresh=$window.FindName('CboThreshold')
    if($cboThresh){foreach($item in $cboThresh.Items){if([int]$item.Tag -eq [int]$cfg.MinQuotaPercent){$cboThresh.SelectedItem=$item;break}}}
    $cboCool=$window.FindName('CboCooldown')
    if($cboCool){foreach($item in $cboCool.Items){if([int]$item.Tag -eq [int]$cfg.CooldownSeconds){$cboCool.SelectedItem=$item;break}}}
    if($script:HubTrayToggleItem){$script:HubTrayToggleItem.Text=if($enabled){Get-HubText BtnPauseRotation}else{Get-HubText BtnResumeRotation}}
}

function Show-HubDetailsDialog {
    param($Account)
    $dialog=[Windows.Window]::new()
    $dialog.Title=Get-HubText DetailsTitle;$dialog.Width=740;$dialog.Height=620
    $dialog.Owner=$window;$dialog.WindowStartupLocation='CenterOwner';$dialog.Background='#F1F5F9'
    $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.VerticalScrollBarVisibility='Auto';$scroll.Padding=[Windows.Thickness]::new(20)
    $root=[Windows.Controls.StackPanel]::new()
    $hdr=[Windows.Controls.Border]::new();$hdr.Background='#FFFFFF';$hdr.BorderBrush='#E2E8F0';$hdr.BorderThickness=[Windows.Thickness]::new(1);$hdr.CornerRadius=[Windows.CornerRadius]::new(10);$hdr.Padding=[Windows.Thickness]::new(16,14,16,14);$hdr.Margin=[Windows.Thickness]::new(0,0,0,14)
    $hdrStack=[Windows.Controls.StackPanel]::new()
    $title=[Windows.Controls.TextBlock]::new();$title.Text="$($Account.AccountName)  [$($Account.PlanText)]";$title.FontSize=18;$title.FontWeight='Bold';$title.Foreground='#0F172A'
    $emailTxt=[Windows.Controls.TextBlock]::new();$emailTxt.Text=$Account.Email;$emailTxt.FontSize=12.5;$emailTxt.Foreground='#64748B';$emailTxt.Margin=[Windows.Thickness]::new(0,2,0,4)
    $hintTxt=[Windows.Controls.TextBlock]::new();$hintTxt.Text=Get-HubText DetailsHint;$hintTxt.FontSize=11.5;$hintTxt.Foreground='#64748B';$hintTxt.TextWrapping='Wrap'
    $null=$hdrStack.Children.Add($title);$null=$hdrStack.Children.Add($emailTxt);$null=$hdrStack.Children.Add($hintTxt)
    $hdr.Child=$hdrStack;$null=$root.Children.Add($hdr)

    $grpCard=[Windows.Controls.Border]::new();$grpCard.Background='#FFFFFF';$grpCard.BorderBrush='#E2E8F0';$grpCard.BorderThickness=[Windows.Thickness]::new(1);$grpCard.CornerRadius=[Windows.CornerRadius]::new(10);$grpCard.Padding=[Windows.Thickness]::new(16,14,16,14);$grpCard.Margin=[Windows.Thickness]::new(0,0,0,14)
    $grpStack=[Windows.Controls.StackPanel]::new()
    $grpHdr=[Windows.Controls.TextBlock]::new();$grpHdr.Text=Get-HubText GroupQuotas;$grpHdr.FontSize=11;$grpHdr.FontWeight='Bold';$grpHdr.Foreground='#0F766E';$grpHdr.Margin=[Windows.Thickness]::new(0,0,0,10)
    $null=$grpStack.Children.Add($grpHdr)
    $groups=@($Account.QuotaGroups)
    if(-not $groups.Count){
        $emptyG=[Windows.Controls.TextBlock]::new();$emptyG.Text=Get-HubText DetailsNoGroups;$emptyG.Foreground='#64748B';$null=$grpStack.Children.Add($emptyG)
    } else {
        foreach($g in $groups){
            $pct=if($g.Remaining -ge 0){[math]::Round($g.Remaining*100,1)}else{-1}
            $row=[Windows.Controls.Grid]::new();$row.Margin=[Windows.Thickness]::new(0,0,0,8)
            $c1=[Windows.Controls.ColumnDefinition]::new();$c1.Width='*'
            $c2=[Windows.Controls.ColumnDefinition]::new();$c2.Width='Auto'
            $null=$row.ColumnDefinitions.Add($c1);$null=$row.ColumnDefinitions.Add($c2)
            $left=[Windows.Controls.StackPanel]::new()
            $nm=[Windows.Controls.TextBlock]::new();$nm.Text="$($g.Name) ($($g.Window))";$nm.FontWeight='SemiBold';$nm.Foreground='#0F172A'
            $rs=[Windows.Controls.TextBlock]::new();$rs.Text=(Format-HubQuotaReset $g.ResetAt);$rs.FontSize=11.5;$rs.Foreground='#64748B'
            $null=$left.Children.Add($nm);$null=$left.Children.Add($rs)
            $val=[Windows.Controls.TextBlock]::new();$val.Text=if($pct -ge 0){"$pct%"}else{Get-HubText ModelUnknown};$val.FontWeight='Bold';$val.FontSize=14;$val.Foreground=if($pct -gt 20){'#0F766E'}elseif($pct -ge 0){'#B45309'}else{'#64748B'};$val.VerticalAlignment='Center'
            [Windows.Controls.Grid]::SetColumn($val,1);$null=$row.Children.Add($left);$null=$row.Children.Add($val)
            $null=$grpStack.Children.Add($row)
        }
    }
    $grpCard.Child=$grpStack;$null=$root.Children.Add($grpCard)

    $mdlCard=[Windows.Controls.Border]::new();$mdlCard.Background='#FFFFFF';$mdlCard.BorderBrush='#E2E8F0';$mdlCard.BorderThickness=[Windows.Thickness]::new(1);$mdlCard.CornerRadius=[Windows.CornerRadius]::new(10);$mdlCard.Padding=[Windows.Thickness]::new(16,14,16,14)
    $mdlStack=[Windows.Controls.StackPanel]::new()
    $mdlHdr=[Windows.Controls.TextBlock]::new();$mdlHdr.Text=Get-HubText AllModels;$mdlHdr.FontSize=11;$mdlHdr.FontWeight='Bold';$mdlHdr.Foreground='#0F766E';$mdlHdr.Margin=[Windows.Thickness]::new(0,0,0,10)
    $null=$mdlStack.Children.Add($mdlHdr)
    $models=@($Account.ModelQuotas | Sort-Object Name)
    if(-not $models.Count){
        $emptyM=[Windows.Controls.TextBlock]::new();$emptyM.Text=Get-HubText DetailsNoModels;$emptyM.Foreground='#64748B';$null=$mdlStack.Children.Add($emptyM)
    } else {
        foreach($m in $models){
            $pct=if($m.Status -eq 'Available'){[math]::Round($m.Remaining*100,1)}else{-1}
            $row=[Windows.Controls.Grid]::new();$row.Margin=[Windows.Thickness]::new(0,0,0,7)
            $c1=[Windows.Controls.ColumnDefinition]::new();$c1.Width='*'
            $c2=[Windows.Controls.ColumnDefinition]::new();$c2.Width='Auto'
            $null=$row.ColumnDefinitions.Add($c1);$null=$row.ColumnDefinitions.Add($c2)
            $left=[Windows.Controls.StackPanel]::new()
            $nm=[Windows.Controls.TextBlock]::new();$nm.Text=$m.Name;$nm.FontWeight='Medium';$nm.Foreground='#0F172A'
            $rs=[Windows.Controls.TextBlock]::new();$rs.Text=(Format-HubQuotaReset $m.ResetAt);$rs.FontSize=11;$rs.Foreground='#64748B'
            $null=$left.Children.Add($nm);$null=$left.Children.Add($rs)
            $valTxt=if($m.Status -eq 'Available'){"$pct%"}elseif($m.Status -eq 'Disabled'){Get-HubText ModelDisabled}else{Get-HubText ModelUnknown}
            $val=[Windows.Controls.TextBlock]::new();$val.Text=$valTxt;$val.FontWeight='SemiBold';$val.FontSize=12.5;$val.Foreground=if($pct -gt 20){'#0F766E'}elseif($pct -ge 0){'#B45309'}else{'#64748B'};$val.VerticalAlignment='Center'
            [Windows.Controls.Grid]::SetColumn($val,1);$null=$row.Children.Add($left);$null=$row.Children.Add($val)
            $null=$mdlStack.Children.Add($row)
        }
    }
    $mdlCard.Child=$mdlStack;$null=$root.Children.Add($mdlCard)
    $scroll.Content=$root;$dialog.Content=$scroll;$null=$dialog.ShowDialog()
}

function Set-HubPage {
    param([string]$Page)
    $accounts=$Page -eq 'Accounts'
    $history=$Page -eq 'History'
    $settings=$Page -eq 'Settings'
    $window.FindName('AccountsPage').Visibility=if($accounts){'Visible'}else{'Collapsed'}
    $window.FindName('HistoryPage').Visibility=if($history){'Visible'}else{'Collapsed'}
    $sw=$window.FindName('SettingsPage');if($sw){$sw.Visibility=if($settings){'Visible'}else{'Collapsed'}}
    $window.FindName('PageTitle').Text=if($history){Get-HubText HistoryTitle}elseif($settings){Get-HubText SettingsTitle}else{Get-HubText AccountsTitle}
    $window.FindName('PageSubtitle').Text=if($history){Get-HubText HistorySubtitle}elseif($settings){Get-HubText SettingsSubtitle}else{Get-HubText AccountsSubtitle}
    if($history){Update-HubHistory -Force}
    if($settings){Update-HubSettingsUi;$ts=$window.FindName('TxtSettingsSaved');if($ts){$ts.Text=''}}
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
        'Details' {
            Show-HubDetailsDialog $Account
        }
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
    $window.FindName('ContentArea').Margin=[Windows.Thickness]::new(20,16,20,10)
    $window.FindName('HeaderArea').Margin=[Windows.Thickness]::new(0,0,0,12)
    $window.FindName('StatsArea').Margin=[Windows.Thickness]::new(0,0,-12,12)
    $window.FindName('StatusArea').Margin=[Windows.Thickness]::new(0,0,0,12)
}

function Initialize-HubDashboard {
    $script:HubAccounts=@();$script:HubLastRefresh=Get-Date
    $script:HubWorker=$null;$script:HubLogSignature=$null
    Update-HubLayout $window.Height
    $window.Add_SizeChanged({Update-HubLayout $window.ActualHeight})
    $window.FindName('NavAccounts').Add_Checked({Set-HubPage Accounts})
    $window.FindName('NavHistory').Add_Checked({Set-HubPage History})
    $navSet=$window.FindName('NavSettings');if($navSet){$navSet.Add_Checked({Set-HubPage Settings})}
    $btnToggle=$window.FindName('BtnToggleRotation')
    if($btnToggle){
        $btnToggle.Add_Click({
            if($Preview){return}
            $cfg=Get-HubConfig
            $cfg.AutoRotationEnabled=-not $cfg.AutoRotationEnabled
            Save-HubConfig $cfg
            Update-HubSettingsUi
            Load-Accounts-UI
        })
    }
    $btnSaveSet=$window.FindName('BtnSaveSettings')
    if($btnSaveSet){
        $btnSaveSet.Add_Click({
            if($Preview){return}
            $cfg=Get-HubConfig
            $cfg.AutoRotationEnabled=[bool]$window.FindName('ChkAutoRotate').IsChecked
            $cfg.EnableNotifications=[bool]$window.FindName('ChkNotifications').IsChecked
            $th=$window.FindName('CboThreshold').SelectedItem;if($th){$cfg.MinQuotaPercent=[int]$th.Tag}
            $cd=$window.FindName('CboCooldown').SelectedItem;if($cd){$cfg.CooldownSeconds=[int]$cd.Tag}
            Save-HubConfig $cfg
            Update-HubSettingsUi
            $ts=$window.FindName('TxtSettingsSaved');if($ts){$ts.Text=Get-HubText SettingsSaved}
            Load-Accounts-UI
        })
    }
    $btnChkUpd=$window.FindName('BtnCheckUpdate');$btnAppUpd=$window.FindName('BtnApplyUpdate');$txtUpd=$window.FindName('TxtUpdateStatus')
    if($btnChkUpd -and $btnAppUpd -and $txtUpd){
        $btnChkUpd.Add_Click({
            $txtUpd.Text=Get-HubText UpdateChecking;$btnAppUpd.Visibility='Collapsed'
            try {
                $env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='never'
                $null=git -C $baseDir fetch origin main 2>&1
                if($LASTEXITCODE -ne 0){throw 'fetch failed'}
                $behind=[int](git -C $baseDir rev-list --count 'HEAD..origin/main' 2>$null)
                if($behind -gt 0){
                    $txtUpd.Text=(Get-HubText UpdateAvailable) -f $behind
                    $btnAppUpd.Visibility='Visible'
                } else {
                    $txtUpd.Text=Get-HubText UpdateLatest
                }
            } catch { $txtUpd.Text=Get-HubText UpdateError }
        })
        $btnAppUpd.Add_Click({
            try {
                $env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='never'
                $null=git -C $baseDir pull --ff-only origin main 2>&1
                if($LASTEXITCODE -ne 0){throw 'pull failed'}
                $txtUpd.Text=Get-HubText UpdateSuccess;$btnAppUpd.Visibility='Collapsed'
            } catch { $txtUpd.Text=Get-HubText UpdateError }
        })
    }
    Update-HubSettingsUi
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
            $models=@()
            foreach($family in @('Flash','Argon','Hydrogen','Carbon','Opus','Sonnet','GptOss')){
                $remaining=if($index -eq 5 -or $family -eq 'Carbon'){-1}elseif($family -eq 'Argon'){$argon}else{$five}
                $models+=[pscustomobject]@{Name="$family (Medium)";Family=$family;Remaining=$remaining;Status=$(if($remaining -ge 0){'Available'}elseif($index -eq 5){'Unknown'}else{'Disabled'});ResetAt='2026-11-18T00:00:00Z'}
            }
            $sample+=[pscustomobject]@{AccountName=$name;Email="$name@example.test";Success=($index -ne 5);Gemini5H=$five;GeminiWeekly=$week;ArgonWeekly=$argon;ModelQuotas=$models;Plan=$(if($index -eq 5){'Unknown'}else{'Pro'});PlanSource=$(if($index -eq 5){''}else{'PaidTier'});CheckedAt='2026-11-11T01:30:00Z';TokenPath='';VerificationUrl=$null;ErrorCode=''};$index++
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
        $selection=$window.FindName('RefreshInterval').SelectedItem
        $interval=if($selection){[int]$selection.Tag}else{30}
        if(-not $Preview -and -not $script:HubWorker -and -not $script:loginProtection -and ($script:HubRefreshQueued -or ($interval -gt 0 -and ((Get-Date)-$script:HubLastRefresh).TotalSeconds -ge $interval))){Load-Accounts-UI}
    })
    $script:HubTimer.Start()
    $window.Add_Closed({
        $script:HubTimer.Stop()
        if($script:HubWorker){$script:HubWorker.Stop();$script:HubWorker.Dispose();$script:HubWorker=$null}
    })
    Load-Accounts-UI
}
