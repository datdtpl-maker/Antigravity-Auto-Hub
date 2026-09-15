# Rotation decisions use verified runtime identity, never quota deltas.
function Get-RefreshToken {
    param($Token)
    if ($Token.token.refresh_token) { return $Token.token.refresh_token }
    return $Token.refresh_token
}

function Get-FreshToken {
    param($Token)
    if (-not $script:GoogleClientId -or -not $script:GoogleClientSecret) { throw 'OAuth configuration missing.' }
    $refresh = Get-RefreshToken $Token
    if (-not $refresh) { throw 'Refresh token missing.' }
    $response = Invoke-RestMethod -Uri 'https://oauth2.googleapis.com/token' -Method Post -Body @{
        client_id=$script:GoogleClientId; client_secret=$script:GoogleClientSecret
        refresh_token=$refresh; grant_type='refresh_token'
    } -TimeoutSec 10 -ErrorAction Stop
    if (-not $response.access_token -or $response.expires_in -le 0) { throw 'Invalid token response.' }
    return [pscustomobject]@{
        auth_method = 'consumer'
        token = [pscustomobject]@{
            access_token=$response.access_token; token_type='Bearer'
            refresh_token=$(if ($response.refresh_token) { $response.refresh_token } else { $refresh })
            expiry=[datetime]::UtcNow.AddSeconds($response.expires_in).ToString('o')
        }
    }
}

function Convert-QuotaSummary {
    param($Response)
    $five = @(); $weekly = @()
    foreach ($group in $Response.groups) {
        if ("$($group.displayName) $($group.description)" -notmatch 'gemini') { continue }
        foreach ($bucket in $group.buckets) {
            if ($null -eq $bucket.remainingFraction) { continue }
            $fraction = 0.0
            if (-not [double]::TryParse([string]$bucket.remainingFraction,
                [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$fraction)) { continue }
            if ([double]::IsNaN($fraction) -or $fraction -lt 0 -or $fraction -gt 1) { continue }
            if ($bucket.window -match '^5h$') { $five += $fraction }
            elseif ($bucket.window -match '^(week|weekly|7d)$') { $weekly += $fraction }
        }
    }
    if (-not $five.Count -or -not $weekly.Count) { throw 'Quota windows unavailable; no rotation.' }
    [pscustomobject]@{ Gemini5H=($five | Measure-Object -Minimum).Minimum; GeminiWeekly=($weekly | Measure-Object -Minimum).Minimum }
}

function Get-AccountQuotaInfo {
    param([string]$tokenFilePath)
    $result = [ordered]@{
        Success=$false; Email=''; Gemini5H=-1.0; GeminiWeekly=-1.0
        TokenPath=$tokenFilePath; AccountName=[IO.Path]::GetFileNameWithoutExtension($tokenFilePath)
        Error='Quota unavailable'
    }
    try {
        $token = Get-FreshToken (Get-Content -LiteralPath $tokenFilePath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $headers = @{Authorization="Bearer $($token.token.access_token)"; 'User-Agent'='antigravity/2.12.2 windows/amd64'}
        $user = Invoke-RestMethod -Uri 'https://www.googleapis.com/oauth2/v3/userinfo' -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        if (-not $user.email) { throw 'Account email unavailable.' }
        $result.Email = $user.email
        $project = Invoke-RestMethod -Uri 'https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist' -Method Post -Headers $headers -Body '{}' -ContentType 'application/json' -TimeoutSec 10 -ErrorAction Stop
        $projectId = $project.cloudaicompanionProject
        if ($projectId -and $projectId -isnot [string]) { $projectId = $projectId.id }
        if (-not $projectId) { $projectId = $project.project }
        if (-not $projectId -or $projectId -isnot [string]) { throw 'Project ID unavailable.' }
        $response = Invoke-RestMethod -Uri 'https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary' -Method Post -Headers $headers -Body (@{project=$projectId} | ConvertTo-Json -Compress) -ContentType 'application/json' -TimeoutSec 10 -ErrorAction Stop
        $quota = Convert-QuotaSummary $response
        $result.Gemini5H=$quota.Gemini5H; $result.GeminiWeekly=$quota.GeminiWeekly
        $result.Success=$true; $result.Error=''
    } catch { } # Never log HTTP bodies, token content or OAuth error descriptions.
    [pscustomobject]$result
}

function Get-AllAccountsQuota {
    foreach ($file in (Get-ChildItem -LiteralPath $accDir -Filter '*.json')) {
        Get-AccountQuotaInfo $file.FullName
    }
}

function Get-CurrentActiveName {
    try {
        $runtime = Get-RuntimeIdentity
        if (-not $runtime) { return '' }
        # Only trust the last marker if the runtime confirms its stored email.
        $state = Read-RotationState
        if ($state.Status -eq 'Verified' -and $state.Email -eq $runtime.Email) { return $state.Account }
        foreach ($account in (Get-AllAccountsQuota)) {
            if ($account.Email -eq $runtime.Email) { return $account.AccountName }
        }
    } catch { }
    return ''
}

function Read-RotationState {
    if (Test-Path -LiteralPath $stateFile) {
        try { return Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { return [pscustomobject]@{Status='NeedsAttention'} }
    }
    return $null
}

function Write-AtomicText {
    param([string]$Path, [string]$Text)
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, $Text, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Set-RotationState {
    param([string]$Status, [string]$Account='', [string]$Email='')
    Write-AtomicText $stateFile (@{Status=$Status;Account=$Account;Email=$Email;UpdatedAt=[datetime]::UtcNow.ToString('o')} | ConvertTo-Json -Compress)
}

function Set-StoredCredential {
    param([string]$Content)
    if (-not [WinCred]::Write('gemini:antigravity', 'antigravity', $Content)) { throw 'Credential Manager write failed.' }
    if ([WinCred]::Read('gemini:antigravity') -cne $Content) { throw 'Credential read-back mismatch.' }
    $folder = Split-Path $geminiTokenPath
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    Write-AtomicText $geminiTokenPath $Content
}

function Get-StoredCredential { [WinCred]::Read('gemini:antigravity') }

function Get-CredentialEmail {
    param([string]$Content)
    $token=Get-FreshToken ($Content | ConvertFrom-Json)
    $user=Invoke-RestMethod 'https://www.googleapis.com/oauth2/v3/userinfo' -Headers @{Authorization="Bearer $($token.token.access_token)"} -TimeoutSec 10 -ErrorAction Stop
    if (-not $user.email) { throw 'Rollback credential identity unavailable.' }
    return $user.email
}

function Restore-StoredCredential {
    param([string]$Content)
    if (-not [WinCred]::Write('gemini:antigravity','antigravity',$Content)) { throw 'Rollback failed.' }
    if ([WinCred]::Read('gemini:antigravity') -cne $Content) { throw 'Rollback read-back mismatch.' }
}

function Switch-ActiveAccount {
    param([string]$targetAccountName, [string]$Reason='', [switch]$Notify)
    $ErrorActionPreference='Stop'
    $mutex = [Threading.Mutex]::new($false, 'Local\AntigravityAutoHub.Switch')
    $locked=$false; $written=$false; $oldCredential=$null; $oldFile=$null; $oldEmail=''
    try {
        try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
        if (-not $locked) { return $false }
        $state = Read-RotationState
        if ($state.Status -in @('Switching','NeedsAttention')) { throw 'Previous switch requires reconciliation.' }
        if ($state.UpdatedAt -and ([datetime]::UtcNow - [datetime]$state.UpdatedAt).TotalSeconds -lt 120) { return $false }
        if ($targetAccountName -notmatch '^[a-zA-Z0-9_.@-]+$' -or $targetAccountName -in @('.','..')) { throw 'Invalid account name.' }
        $source = Join-Path $accDir "$targetAccountName.json"
        $quota = Get-AccountQuotaInfo $source
        if (-not $quota.Success -or $quota.Gemini5H -le $MinQuotaThreshold -or $quota.GeminiWeekly -le $MinWeeklyThreshold) { throw 'Target quota unavailable or exhausted.' }
        $fresh = Get-FreshToken (Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json)
        $runtime = Get-RuntimeIdentity
        if ($runtime -and (-not $runtime.Idle)) {
            Write-RotatorLog 'IDE agent is running; rotation deferred until idle.'
            return $false
        }
        if ($runtime -and $runtime.Email -eq $quota.Email) { return $true }
        $savedWindows = @()
        if ($runtime) {
            $savedWindows = @(Get-RuntimeWindows $runtime.Runtimes[0])
            if (@($savedWindows | Where-Object { -not $_.Safe }).Count) { throw 'Unsaved draft or focused editor; rotation deferred.' }
        }
        if ($runtime) { $oldEmail=$runtime.Email }
        $oldCredential=Get-StoredCredential
        if (-not $oldCredential) { throw 'Missing rollback credential.' }
        if ($runtime -and (Get-CredentialEmail $oldCredential) -ne $oldEmail) { throw 'Stored credential does not match the runtime; reconcile before switching.' }
        if (Test-Path -LiteralPath $geminiTokenPath) { $oldFile=[IO.File]::ReadAllText($geminiTokenPath) }
        Set-RotationState 'Switching' $targetAccountName $quota.Email
        $written=$true
        Set-StoredCredential ($fresh | ConvertTo-Json -Depth 10 -Compress)
        if ($runtime) {
            foreach ($server in $runtime.Runtimes) { Restart-AntigravityRuntime $server }
            if (-not (Wait-AntigravityIdentity $quota.Email)) { throw 'New runtime identity not confirmed.' }
            Restore-RuntimeWindows $savedWindows
            Set-RotationState 'Verified' $targetAccountName $quota.Email
            Write-AtomicText $activeFile $targetAccountName
            Write-RotatorLog "Verified IDE account: [$targetAccountName]."
        } else {
            Set-RotationState 'Prepared' $targetAccountName $quota.Email
            Write-RotatorLog "Account [$targetAccountName] prepared for next IDE launch (not yet verified)."
        }
        $script:LastSwitchTime=Get-Date
        if ($Notify) {
            $message = if ($runtime) { "$([char]0x110)$([char]0xE3) x$([char]0xE1)c minh t$([char]0xE0)i kho$([char]0x1EA3)n IDE: [$targetAccountName]" }
                else { "$([char]0x110)$([char]0xE3) chu$([char]0x1EA9)n b$([char]0x1ECB) t$([char]0xE0)i kho$([char]0x1EA3)n cho l$([char]0x1EA7)n m$([char]0x1EDF) IDE ti$([char]0x1EBF)p theo: [$targetAccountName]" }
            Send-ToastNotification -Message $message
        }
        return $true
    } catch {
        if ($written) {
            $restored=$false
            try {
                Restore-StoredCredential $oldCredential
                if ($null -ne $oldFile) { Write-AtomicText $geminiTokenPath $oldFile }
                elseif (Test-Path -LiteralPath $geminiTokenPath) { [IO.File]::Delete($geminiTokenPath) }
                # Do not restart again: a new task may already have begun. Block further switches.
                $restored=$true
            } catch { }
            Set-RotationState 'NeedsAttention' '' $oldEmail
            Write-RotatorLog "Switch unverified. Stored credential restored: $restored. Automatic rotation paused."
        } else { Write-RotatorLog 'Switch deferred: check quota, runtime, OAuth configuration and rotation-state.json.' }
        if ($Notify) { Send-ToastNotification -Message "Ch$([char]0x1B0)a chuy$([char]0x1EC3)n $([char]0x111)$([char]0x1B0)$([char]0x1EE3)c t$([char]0xE0)i kho$([char]0x1EA3)n. Ki$([char]0x1EC3)m tra tr$([char]0x1EA1)ng th$([char]0xE1)i Hub / rotator.log." }
        return $false
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Invoke-AutoRotationCheck {
    $state = Read-RotationState
    if ($state.Status -in @('Switching','NeedsAttention')) {
        Write-RotatorLog 'Rotation paused: previous switch requires verification.'
        return
    }
    if ($state.UpdatedAt -and ([datetime]::UtcNow - [datetime]$state.UpdatedAt).TotalSeconds -lt 120) { return }
    try { $runtime=Get-RuntimeIdentity } catch { Write-RotatorLog (Get-RuntimeFailureMessage $_); return }
    if (-not $runtime) { Write-RotatorLog 'IDE is closed; monitoring only.'; return }
    $accounts = @(Get-AllAccountsQuota)
    $current = $accounts | Where-Object { $_.Email -eq $runtime.Email } | Select-Object -First 1
    if (-not $current -or -not $current.Success) { Write-RotatorLog 'Active quota unknown; no rotation.'; return }
    Write-RotatorLog "Active [$($current.AccountName)]: 5H=$([math]::Round($current.Gemini5H*100))%, week=$([math]::Round($current.GeminiWeekly*100))%."
    if ($current.Gemini5H -gt $MinQuotaThreshold -and $current.GeminiWeekly -gt $MinWeeklyThreshold) { return }
    if (-not $runtime.Idle) { Write-RotatorLog 'Low quota; waiting for running agents to finish.'; return }
    $best = $accounts | Where-Object {
        $_.Success -and $_.Email -ne $runtime.Email -and
        $_.Gemini5H -gt [math]::Max(.15,$MinQuotaThreshold) -and $_.GeminiWeekly -gt [math]::Max(.10,$MinWeeklyThreshold)
    } | Sort-Object -Property @{Expression='Gemini5H';Descending=$true}, @{Expression='GeminiWeekly';Descending=$true} | Select-Object -First 1
    if (-not $best) { Write-RotatorLog 'No healthy account available; waiting for quota reset.'; return }
    Switch-ActiveAccount $best.AccountName -Reason 'Low quota' -Notify | Out-Null
}

function Repair-RotationState {
    # Read-only identity comparison; never restart or write login credentials here.
    $mutex=[Threading.Mutex]::new($false, 'Local\AntigravityAutoHub.Switch')
    $locked=$false
    try {
        try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
        if (-not $locked) { return $false }
        $state=Read-RotationState
        if ($state.Status -notin @('Switching','NeedsAttention','Prepared')) { return $true }
        $runtime=Get-RuntimeIdentity
        if (-not $runtime) { return $false }
        $stored=Get-StoredCredential | ConvertFrom-Json
        $token=Get-FreshToken $stored
        $user=Invoke-RestMethod 'https://www.googleapis.com/oauth2/v3/userinfo' -Headers @{Authorization="Bearer $($token.token.access_token)"} -TimeoutSec 10 -ErrorAction Stop
        if ($user.email -ne $runtime.Email) { return $false }
        foreach ($file in (Get-ChildItem -LiteralPath $accDir -Filter '*.json')) {
            $saved=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ((Get-RefreshToken $saved) -eq (Get-RefreshToken $stored)) {
                Set-RotationState 'Verified' $file.BaseName $runtime.Email
                Write-AtomicText $activeFile $file.BaseName
                return $true
            }
        }
        return $false
    } catch { return $false }
    finally { if ($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
