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
    $modelKeys=@($Account.ModelQuotas | ForEach-Object {Get-ModelSelectionKey $_.Name})
    foreach($planner in @('Neon','Argon','Carbon')){
        $name="Orchestrator ($planner)"
        if($modelKeys -notcontains (Get-ModelSelectionKey $name)){$lines+="${name}: $(Get-HubText ModelUnknown)"}
    }
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
    $threshold=if(Get-Command Get-HubConfig -ErrorAction SilentlyContinue){[double](Get-HubConfig).MinQuotaPercent / 100.0}else{.20}
    $ready=$known -and $Account.Gemini5H -gt $threshold -and $Account.GeminiWeekly -gt .10 -and $argonOk
    $modelQuota=$null
    if($SelectedModel){
        $modelQuota=Get-SelectedModelQuota $Account $SelectedModel
        $ready=$modelQuota.Known -and $modelQuota.Remaining -gt $threshold
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
        NeonRing=(Get-HubModelRing $Account 'Neon')
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
        CanSwitch=$(if($SelectedModel){$ready -and -not $active -and -not $verify}else{$known -and -not $active -and -not $verify -and $Account.Gemini5H -gt .20 -and $Account.GeminiWeekly -gt .08 -and $argonSwitchOk})
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
    $window.FindName('PageSubtitle').Text=if($Snapshot.SelectedModel){((Get-HubText RotationModel) -f $Snapshot.SelectedModel) -replace '20%',"$($cfg.MinQuotaPercent)%"}else{Get-HubText AccountsSubtitle}
    $window.FindName('HintReady').Text=if($Snapshot.SelectedModel){(Get-HubText SelectedModelReady) -replace '20%',"$($cfg.MinQuotaPercent)%"}else{Get-HubText LegacyReady}
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

function Set-HubTheme {
    param([string]$Theme = 'Light')
    $isAmoled = ($Theme -eq 'Amoled')
    $script:HubCurrentTheme = if ($isAmoled) { 'Amoled' } else { 'Light' }
    $palette = if ($isAmoled) {
        @{
            BgWindow='#000000'; BgSurface='#0A0A0A'; BgSurfaceAlt='#121212'; BgSurfaceHover='#1A1A1A'
            BgActiveRow='#052E2B'; BgSelectedRow='#0F172A'; BgFocusCell='#08332E'
            BgPillBar='#141414'; BgPillActive='#262626'; BgInput='#0A0A0A'
            BgNavActive='#08332E'; FgNavActive='#2DD4BF'
            BorderLine='#1F1F1F'; BorderControl='#2E2E2E'; BorderOuter='#262626'; GridDivider='#171717'
            RingTrack='#222222'; ScrollThumb='#333333'
            FgPrimary='#F8FAFC'; FgSecondary='#CBD5E1'; FgHeader='#94A3B8'; FgMuted='#94A3B8'; FgSubtle='#64748B'
            Accent='#14B8A6'; AccentHover='#0D9488'
            BgStatusActive='#042420'; BorderStatusActive='#065F46'; FgStatusPrimary='#6EE7B7'; FgStatusSecondary='#34D399'
            BgPlanDefault='#1A1A1A'; BorderPlanDefault='#2E2E2E'; FgPlanDefault='#CBD5E1'
            BgPlanPro='#0C2D48'; BorderPlanPro='#0369A1'; FgPlanPro='#38BDF8'
            BgPlanUltra='#2A1B02'; BorderPlanUltra='#B45309'; FgPlanUltra='#FBBF24'
        }
    } else {
        @{
            BgWindow='#F1F5F9'; BgSurface='#FFFFFF'; BgSurfaceAlt='#F8FAFC'; BgSurfaceHover='#F8FAFC'
            BgActiveRow='#F0FDFA'; BgSelectedRow='#EFF6FF'; BgFocusCell='#CCFBF1'
            BgPillBar='#F1F5F9'; BgPillActive='#FFFFFF'; BgInput='#FFFFFF'
            BgNavActive='#F0FDFA'; FgNavActive='#0F766E'
            BorderLine='#E2E8F0'; BorderControl='#CBD5E1'; BorderOuter='#CBD5E1'; GridDivider='#F1F5F9'
            RingTrack='#E2E8F0'; ScrollThumb='#CBD5E1'
            FgPrimary='#0F172A'; FgSecondary='#334155'; FgHeader='#475569'; FgMuted='#64748B'; FgSubtle='#94A3B8'
            Accent='#0F766E'; AccentHover='#0D9488'
            BgStatusActive='#ECFDF5'; BorderStatusActive='#A7F3D0'; FgStatusPrimary='#065F46'; FgStatusSecondary='#047857'
            BgPlanDefault='#F1F5F9'; BorderPlanDefault='#CBD5E1'; FgPlanDefault='#334155'
            BgPlanPro='#EFF6FF'; BorderPlanPro='#93C5FD'; FgPlanPro='#1D4ED8'
            BgPlanUltra='#FEF3C7'; BorderPlanUltra='#F59E0B'; FgPlanUltra='#B45309'
        }
    }
    foreach ($k in $palette.Keys) {
        if ($window.Resources.Contains($k)) {
            $window.Resources[$k] = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($palette[$k]))
        }
    }
    $btnTheme = $window.FindName('BtnToggleTheme')
    if ($btnTheme) {
        $btnTheme.Content = if ($isAmoled) { [string][char]0xE706 } else { [string][char]0xE708 }
    }
}

function Update-HubSettingsUi {
    $cfg=if(Get-Command Get-HubConfig -ErrorAction SilentlyContinue){Get-HubConfig}else{[pscustomobject]@{AutoRotationEnabled=$true;MinQuotaPercent=20;CooldownSeconds=120;EnableNotifications=$true;Theme='Light'}}
    $theme = if ($cfg.PSObject.Properties['Theme'] -and $cfg.Theme -eq 'Amoled') { 'Amoled' } else { 'Light' }
    Set-HubTheme $theme
    $enabled=[bool]$cfg.AutoRotationEnabled
    $btnToggle=$window.FindName('BtnToggleRotation')
    if($btnToggle){$btnToggle.Content=if($enabled){Get-HubText BtnPauseRotation}else{Get-HubText BtnResumeRotation}}
    $area=$window.FindName('StatusArea');$dot=$window.FindName('StatusDot')
    if($area -and $dot){
        if($enabled){
            $area.Background = if($theme -eq 'Amoled'){'#042420'}else{'#ECFDF5'}
            $area.BorderBrush = if($theme -eq 'Amoled'){'#065F46'}else{'#A7F3D0'}
            $dot.Fill='#10B981'
        } else {
            $area.Background = if($theme -eq 'Amoled'){'#2A1B02'}else{'#FFFBEB'}
            $area.BorderBrush = if($theme -eq 'Amoled'){'#92400E'}else{'#FDE68A'}
            $dot.Fill='#D97706'
        }
    }
    $pt=$window.FindName('TxtPolicyThreshold');if($pt){$pt.Text="Model < $($cfg.MinQuotaPercent)%"}
    $pg=$window.FindName('TxtPolicyTarget');if($pg){$pg.Text="Acc > $($cfg.MinQuotaPercent)%"}
    $chkAuto=$window.FindName('ChkAutoRotate');if($chkAuto){$chkAuto.IsChecked=$enabled}
    $cliEnabled=if($cfg.PSObject.Properties['CliRotationEnabled']){[bool]$cfg.CliRotationEnabled}else{$true}
    $chkCli=$window.FindName('ChkCliRotate');if($chkCli){$chkCli.IsChecked=$cliEnabled}
    $chkNotif=$window.FindName('ChkNotifications');if($chkNotif){$chkNotif.IsChecked=[bool]$cfg.EnableNotifications}
    $cboThresh=$window.FindName('CboThreshold')
    if($cboThresh){foreach($item in $cboThresh.Items){if([int]$item.Tag -eq [int]$cfg.MinQuotaPercent){$cboThresh.SelectedItem=$item;break}}}
    $cboCool=$window.FindName('CboCooldown')
    if($cboCool){foreach($item in $cboCool.Items){if([int]$item.Tag -eq [int]$cfg.CooldownSeconds){$cboCool.SelectedItem=$item;break}}}
    $cboTheme=$window.FindName('CboTheme')
    if($cboTheme){foreach($item in $cboTheme.Items){if([string]$item.Tag -eq $theme){$cboTheme.SelectedItem=$item;break}}}
    if($script:HubTrayToggleItem){$script:HubTrayToggleItem.Text=if($enabled){Get-HubText BtnPauseRotation}else{Get-HubText BtnResumeRotation}}
}

function Show-HubDetailsDialog {
    param($Account)
    $isDark=($script:HubCurrentTheme -eq 'Amoled')
    $bgWin=if($isDark){'#000000'}else{'#F1F5F9'}
    $bgCard=if($isDark){'#0A0A0A'}else{'#FFFFFF'}
    $bdrCard=if($isDark){'#1F1F1F'}else{'#E2E8F0'}
    $fgPri=if($isDark){'#F8FAFC'}else{'#0F172A'}
    $fgMut=if($isDark){'#94A3B8'}else{'#64748B'}
    $fgAcc=if($isDark){'#2DD4BF'}else{'#0F766E'}
    $fgWarn=if($isDark){'#FBBF24'}else{'#B45309'}
    $dialog=[Windows.Window]::new()
    $dialog.Title=Get-HubText DetailsTitle;$dialog.Width=740;$dialog.Height=620
    $dialog.Owner=$window;$dialog.WindowStartupLocation='CenterOwner';$dialog.Background=$bgWin
    $scroll=[Windows.Controls.ScrollViewer]::new();$scroll.VerticalScrollBarVisibility='Auto';$scroll.Padding=[Windows.Thickness]::new(20)
    $root=[Windows.Controls.StackPanel]::new()
    $hdr=[Windows.Controls.Border]::new();$hdr.Background=$bgCard;$hdr.BorderBrush=$bdrCard;$hdr.BorderThickness=[Windows.Thickness]::new(1);$hdr.CornerRadius=[Windows.CornerRadius]::new(10);$hdr.Padding=[Windows.Thickness]::new(16,14,16,14);$hdr.Margin=[Windows.Thickness]::new(0,0,0,14)
    $hdrStack=[Windows.Controls.StackPanel]::new()
    $title=[Windows.Controls.TextBlock]::new();$title.Text="$($Account.AccountName)  [$($Account.PlanText)]";$title.FontSize=18;$title.FontWeight='Bold';$title.Foreground=$fgPri
    $emailTxt=[Windows.Controls.TextBlock]::new();$emailTxt.Text=$Account.Email;$emailTxt.FontSize=12.5;$emailTxt.Foreground=$fgMut;$emailTxt.Margin=[Windows.Thickness]::new(0,2,0,4)
    $hintTxt=[Windows.Controls.TextBlock]::new();$hintTxt.Text=Get-HubText DetailsHint;$hintTxt.FontSize=11.5;$hintTxt.Foreground=$fgMut;$hintTxt.TextWrapping='Wrap'
    $null=$hdrStack.Children.Add($title);$null=$hdrStack.Children.Add($emailTxt);$null=$hdrStack.Children.Add($hintTxt)
    $hdr.Child=$hdrStack;$null=$root.Children.Add($hdr)

    $grpCard=[Windows.Controls.Border]::new();$grpCard.Background=$bgCard;$grpCard.BorderBrush=$bdrCard;$grpCard.BorderThickness=[Windows.Thickness]::new(1);$grpCard.CornerRadius=[Windows.CornerRadius]::new(10);$grpCard.Padding=[Windows.Thickness]::new(16,14,16,14);$grpCard.Margin=[Windows.Thickness]::new(0,0,0,14)
    $grpStack=[Windows.Controls.StackPanel]::new()
    $grpHdr=[Windows.Controls.TextBlock]::new();$grpHdr.Text=Get-HubText GroupQuotas;$grpHdr.FontSize=11;$grpHdr.FontWeight='Bold';$grpHdr.Foreground=$fgAcc;$grpHdr.Margin=[Windows.Thickness]::new(0,0,0,10)
    $null=$grpStack.Children.Add($grpHdr)
    $groups=@($Account.QuotaGroups)
    if(-not $groups.Count){
        $emptyG=[Windows.Controls.TextBlock]::new();$emptyG.Text=Get-HubText DetailsNoGroups;$emptyG.Foreground=$fgMut;$null=$grpStack.Children.Add($emptyG)
    } else {
        foreach($g in $groups){
            $pct=if($g.Remaining -ge 0){[math]::Round($g.Remaining*100,1)}else{-1}
            $row=[Windows.Controls.Grid]::new();$row.Margin=[Windows.Thickness]::new(0,0,0,8)
            $c1=[Windows.Controls.ColumnDefinition]::new();$c1.Width='*'
            $c2=[Windows.Controls.ColumnDefinition]::new();$c2.Width='Auto'
            $null=$row.ColumnDefinitions.Add($c1);$null=$row.ColumnDefinitions.Add($c2)
            $left=[Windows.Controls.StackPanel]::new()
            $nm=[Windows.Controls.TextBlock]::new();$nm.Text="$($g.Name) ($($g.Window))";$nm.FontWeight='SemiBold';$nm.Foreground=$fgPri
            $rs=[Windows.Controls.TextBlock]::new();$rs.Text=(Format-HubQuotaReset $g.ResetAt);$rs.FontSize=11.5;$rs.Foreground=$fgMut
            $null=$left.Children.Add($nm);$null=$left.Children.Add($rs)
            $val=[Windows.Controls.TextBlock]::new();$val.Text=if($pct -ge 0){"$pct%"}else{Get-HubText ModelUnknown};$val.FontWeight='Bold';$val.FontSize=14;$val.Foreground=if($pct -gt 20){$fgAcc}elseif($pct -ge 0){$fgWarn}else{$fgMut};$val.VerticalAlignment='Center'
            [Windows.Controls.Grid]::SetColumn($val,1);$null=$row.Children.Add($left);$null=$row.Children.Add($val)
            $null=$grpStack.Children.Add($row)
        }
    }
    $grpCard.Child=$grpStack;$null=$root.Children.Add($grpCard)

    $mdlCard=[Windows.Controls.Border]::new();$mdlCard.Background=$bgCard;$mdlCard.BorderBrush=$bdrCard;$mdlCard.BorderThickness=[Windows.Thickness]::new(1);$mdlCard.CornerRadius=[Windows.CornerRadius]::new(10);$mdlCard.Padding=[Windows.Thickness]::new(16,14,16,14)
    $mdlStack=[Windows.Controls.StackPanel]::new()
    $mdlHdr=[Windows.Controls.TextBlock]::new();$mdlHdr.Text=Get-HubText AllModels;$mdlHdr.FontSize=11;$mdlHdr.FontWeight='Bold';$mdlHdr.Foreground=$fgAcc;$mdlHdr.Margin=[Windows.Thickness]::new(0,0,0,10)
    $null=$mdlStack.Children.Add($mdlHdr)
    $models=@($Account.ModelQuotas | Sort-Object Name)
    if(-not $models.Count){
        $emptyM=[Windows.Controls.TextBlock]::new();$emptyM.Text=Get-HubText DetailsNoModels;$emptyM.Foreground=$fgMut;$null=$mdlStack.Children.Add($emptyM)
    } else {
        foreach($m in $models){
            $pct=if($m.Status -eq 'Available'){[math]::Round($m.Remaining*100,1)}else{-1}
            $row=[Windows.Controls.Grid]::new();$row.Margin=[Windows.Thickness]::new(0,0,0,7)
            $c1=[Windows.Controls.ColumnDefinition]::new();$c1.Width='*'
            $c2=[Windows.Controls.ColumnDefinition]::new();$c2.Width='Auto'
            $null=$row.ColumnDefinitions.Add($c1);$null=$row.ColumnDefinitions.Add($c2)
            $left=[Windows.Controls.StackPanel]::new()
            $nm=[Windows.Controls.TextBlock]::new();$nm.Text=$m.Name;$nm.FontWeight='Medium';$nm.Foreground=$fgPri
            $rs=[Windows.Controls.TextBlock]::new();$rs.Text=(Format-HubQuotaReset $m.ResetAt);$rs.FontSize=11;$rs.Foreground=$fgMut
            $null=$left.Children.Add($nm);$null=$left.Children.Add($rs)
            $valTxt=if($m.Status -eq 'Available'){"$pct%"}elseif($m.Status -eq 'Disabled'){Get-HubText ModelDisabled}else{Get-HubText ModelUnknown}
            $val=[Windows.Controls.TextBlock]::new();$val.Text=$valTxt;$val.FontWeight='SemiBold';$val.FontSize=12.5;$val.Foreground=if($pct -gt 20){$fgAcc}elseif($pct -ge 0){$fgWarn}else{$fgMut};$val.VerticalAlignment='Center'
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
            $window.FindName('TxtDaemonStatus').Text=Get-HubText Switching
            $switched=Switch-ActiveAccount -targetAccountName $Account.AccountName -Manual -Notify
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
            $chkCli=$window.FindName('ChkCliRotate');if($chkCli){$cfg.CliRotationEnabled=[bool]$chkCli.IsChecked}
            $cfg.EnableNotifications=[bool]$window.FindName('ChkNotifications').IsChecked
            $th=$window.FindName('CboThreshold').SelectedItem;if($th){$cfg.MinQuotaPercent=[int]$th.Tag}
            $cd=$window.FindName('CboCooldown').SelectedItem;if($cd){$cfg.CooldownSeconds=[int]$cd.Tag}
            $tm=$window.FindName('CboTheme').SelectedItem;if($tm){$cfg.Theme=[string]$tm.Tag}
            Save-HubConfig $cfg
            Update-HubSettingsUi
            $ts=$window.FindName('TxtSettingsSaved');if($ts){$ts.Text=Get-HubText SettingsSaved}
            Load-Accounts-UI
        })
    }
    $btnTheme=$window.FindName('BtnToggleTheme')
    if($btnTheme){
        $btnTheme.Add_Click({
            if($Preview){
                $next = if($script:HubCurrentTheme -eq 'Amoled'){'Light'}else{'Amoled'}
                Set-HubTheme $next
                return
            }
            $cfg=Get-HubConfig
            $cur = if($cfg.PSObject.Properties['Theme'] -and $cfg.Theme -eq 'Amoled'){'Amoled'}else{'Light'}
            $cfg.Theme = if($cur -eq 'Amoled'){'Light'}else{'Amoled'}
            Save-HubConfig $cfg
            Update-HubSettingsUi
        })
    }
    $btnChkUpd=$window.FindName('BtnCheckUpdate');$btnAppUpd=$window.FindName('BtnApplyUpdate');$txtUpd=$window.FindName('TxtUpdateStatus')
    if($btnChkUpd -and $btnAppUpd -and $txtUpd){
        $script:HubRepoUrl='https://github.com/datdtpl-maker/Antigravity-Auto-Hub.git'
        $script:HubRepoApi='https://api.github.com/repos/datdtpl-maker/Antigravity-Auto-Hub/commits/main'
        $script:HubRepoZip='https://github.com/datdtpl-maker/Antigravity-Auto-Hub/archive/refs/heads/main.zip'
        $script:PendingUpdateSha=''
        $btnChkUpd.Add_Click({
            $txtU=$window.FindName('TxtUpdateStatus');$btnA=$window.FindName('BtnApplyUpdate')
            try {
                if($txtU){$txtU.Text=Get-HubText UpdateChecking}
                if($btnA){$btnA.Visibility='Collapsed'}
                $script:PendingUpdateSha=''
                $prevEap=$ErrorActionPreference;$ErrorActionPreference='Continue'
                try {
                    $hasGit=(Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $baseDir '.git'))
                    if($hasGit){
                        $env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='never'
                        $curRemote=(git -C $baseDir remote get-url origin 2>$null)
                        if(-not $curRemote){$null=git -C $baseDir remote add origin $script:HubRepoUrl 2>&1}
                        elseif($curRemote.Trim() -ne $script:HubRepoUrl){$null=git -C $baseDir remote set-url origin $script:HubRepoUrl 2>&1}
                        $null=git -C $baseDir fetch origin main 2>&1
                        if($LASTEXITCODE -ne 0){throw 'fetch failed'}
                        $behind=[int](git -C $baseDir rev-list --count 'HEAD..origin/main' 2>$null)
                        if($behind -gt 0){
                            $msg=(Get-HubText UpdateAvailable) -f $behind
                            if($txtU){$txtU.Text=$msg}
                            if($btnA){$btnA.Visibility='Visible'}
                            if(Get-Command Send-ToastNotification -ErrorAction SilentlyContinue){Send-ToastNotification -Message $msg}
                        } else {
                            if($txtU){$txtU.Text=Get-HubText UpdateLatest}
                        }
                    } else {
                        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
                        $resp=Invoke-RestMethod -Uri $script:HubRepoApi -Headers @{'User-Agent'='Antigravity-Auto-Hub'} -TimeoutSec 10 -ErrorAction Stop
                        $remoteSha=[string]$resp.sha
                        if(-not $remoteSha){throw 'no sha'}
                        $verFile=Join-Path $baseDir '.hub-version'
                        $localSha=if(Test-Path -LiteralPath $verFile){(Get-Content -LiteralPath $verFile -Raw -ErrorAction SilentlyContinue).Trim()}else{''}
                        if($localSha -ne $remoteSha){
                            $script:PendingUpdateSha=$remoteSha
                            $msg=(Get-HubText UpdateAvailable) -f 1
                            if($txtU){$txtU.Text=$msg}
                            if($btnA){$btnA.Visibility='Visible'}
                            if(Get-Command Send-ToastNotification -ErrorAction SilentlyContinue){Send-ToastNotification -Message $msg}
                        } else {
                            if($txtU){$txtU.Text=Get-HubText UpdateLatest}
                        }
                    }
                } finally { $ErrorActionPreference=$prevEap }
            } catch { if($txtU){$txtU.Text=Get-HubText UpdateError} }
        })
        $btnAppUpd.Add_Click({
            $txtU=$window.FindName('TxtUpdateStatus');$btnA=$window.FindName('BtnApplyUpdate')
            try {
                $prevEap=$ErrorActionPreference;$ErrorActionPreference='Continue'
                try {
                    $hasGit=(Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $baseDir '.git'))
                    if($hasGit){
                        $env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='never'
                        $curRemote=(git -C $baseDir remote get-url origin 2>$null)
                        if(-not $curRemote){$null=git -C $baseDir remote add origin $script:HubRepoUrl 2>&1}
                        elseif($curRemote.Trim() -ne $script:HubRepoUrl){$null=git -C $baseDir remote set-url origin $script:HubRepoUrl 2>&1}
                        $null=git -C $baseDir fetch origin main 2>&1
                        if($LASTEXITCODE -ne 0){throw 'fetch failed'}
                        $null=git -C $baseDir pull --ff-only origin main 2>&1
                        if($LASTEXITCODE -ne 0){
                            $null=git -C $baseDir reset --hard origin/main 2>&1
                            if($LASTEXITCODE -ne 0){throw 'reset failed'}
                        }
                        $headSha=(git -C $baseDir rev-parse HEAD 2>$null)
                        if($headSha){Set-Content -LiteralPath (Join-Path $baseDir '.hub-version') -Value $headSha.Trim() -Encoding ASCII -ErrorAction SilentlyContinue}
                    } else {
                        Add-Type -AssemblyName System.IO.Compression.FileSystem
                        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
                        $tmpRoot=Join-Path ([IO.Path]::GetTempPath()) ('agh-upd-' + [guid]::NewGuid().ToString('N'))
                        $zipPath=Join-Path $tmpRoot 'main.zip'
                        $extDir=Join-Path $tmpRoot 'extract'
                        New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
                        try {
                            Invoke-WebRequest -Uri $script:HubRepoZip -OutFile $zipPath -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                            [IO.Compression.ZipFile]::ExtractToDirectory($zipPath,$extDir)
                            $srcDir=Get-ChildItem -LiteralPath $extDir -Directory | Select-Object -First 1
                            if(-not $srcDir){throw 'empty archive'}
                            $skip=@('accounts','work','backups','.git','hub-config.json','oauth.local.clixml','rotation-state.json','current_active.txt','rotator.log','.hub-version')
                            foreach($entry in (Get-ChildItem -LiteralPath $srcDir.FullName -Force)){
                                if($entry.Name -in $skip){continue}
                                $dest=Join-Path $baseDir $entry.Name
                                if($entry.PSIsContainer){Copy-Item -LiteralPath $entry.FullName -Destination $baseDir -Recurse -Force}
                                else{Copy-Item -LiteralPath $entry.FullName -Destination $dest -Force}
                            }
                            if($script:PendingUpdateSha){Set-Content -LiteralPath (Join-Path $baseDir '.hub-version') -Value $script:PendingUpdateSha -Encoding ASCII -ErrorAction SilentlyContinue}
                        } finally {
                            Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                } finally { $ErrorActionPreference=$prevEap }
                if($txtU){$txtU.Text=Get-HubText UpdateSuccess}
                if($btnA){$btnA.Visibility='Collapsed'}
                if(Get-Command Send-ToastNotification -ErrorAction SilentlyContinue){Send-ToastNotification -Message (Get-HubText UpdateSuccess)}
                try {
                    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
                        Where-Object { $_.CommandLine -match 'AutoRotator\.ps1' } |
                        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                    $vbsDaemon=Join-Path $baseDir 'launch-rotator-daemon.vbs'
                    if(Test-Path -LiteralPath $vbsDaemon){Start-Process 'wscript.exe' -ArgumentList "`"$vbsDaemon`"" -WorkingDirectory $baseDir}
                    $vbsHub=Join-Path $baseDir 'launch-switcher.vbs'
                    if(Test-Path -LiteralPath $vbsHub){
                        Start-Process 'wscript.exe' -ArgumentList "`"$vbsHub`"" -WorkingDirectory $baseDir
                        $script:HubForceExit=$true
                        $window.Close()
                    }
                } catch { }
            } catch { if($txtU){$txtU.Text=Get-HubText UpdateError} }
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
            foreach($family in @('Flash','Neon','Argon','Hydrogen','Carbon','Opus','Sonnet','GptOss')){
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
