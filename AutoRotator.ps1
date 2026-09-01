# ==============================================================================
# ANTIGRAVITY AUTO-ROTATOR ENGINE (DAEMON & QUOTA TRACKER)
# ==============================================================================
param (
    [switch]$RunOnce,
    [switch]$Daemon,
    [int]$IntervalSeconds = 60,
    [double]$MinQuotaThreshold = 0.10 # 10%
)

$baseDir = "D:\AntigravityAccounts"
$accDir = Join-Path $baseDir "accounts"
$activeFile = Join-Path $baseDir "current_active.txt"
$logFile = Join-Path $baseDir "rotator.log"
$geminiTokenPath = "C:\Users\datdt\.gemini\jetski-standalone-oauth-token"

if (-not (Test-Path $accDir)) {
    New-Item -ItemType Directory -Path $accDir -Force | Out-Null
}

# OAuth Client Credentials (XOR decoded)
$cidBytes = @(107, 106, 109, 107, 106, 106, 108, 106, 108, 106, 111, 99, 107, 119, 46, 55, 50, 41, 41, 51, 52, 104, 50, 104, 107, 54, 57, 40, 63, 104, 105, 111, 44, 46, 53, 54, 53, 48, 50, 110, 61, 110, 106, 105, 63, 42, 116, 59, 42, 42, 41, 116, 61, 53, 53, 61, 54, 63, 47, 41, 63, 40, 57, 53, 52, 46, 63, 52, 46, 116, 57, 53, 55)
$secBytes = @(29, 21, 25, 9, 10, 2, 119, 17, 111, 98, 28, 13, 8, 110, 98, 108, 22, 62, 22, 16, 107, 55, 22, 24, 98, 41, 2, 25, 110, 32, 108, 43, 30, 27, 60)
$script:GoogleClientId = [System.Text.Encoding]::ASCII.GetString(($cidBytes | ForEach-Object { [byte]($_ -bxor 0x5A) }))
$script:GoogleClientSecret = [System.Text.Encoding]::ASCII.GetString(($secBytes | ForEach-Object { [byte]($_ -bxor 0x5A) }))

function Write-RotatorLog {
    param ([string]$msg)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$ts] $msg"
    Write-Host $entry
    try {
        Add-Content -Path $logFile -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

# Function to fetch / refresh quota for a given token file
function Get-AccountQuotaInfo {
    param ([string]$tokenFilePath)
    
    if (-not (Test-Path $tokenFilePath)) { return $null }

    try {
        $tokenRaw = Get-Content $tokenFilePath -Raw | ConvertFrom-Json
        $refreshToken = $tokenRaw.token.refresh_token
        if (-not $refreshToken) { $refreshToken = $tokenRaw.refresh_token }
        if (-not $refreshToken) { return $null }

        # 1. Refresh Access Token
        $tokenResp = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body @{
            client_id = $script:GoogleClientId
            client_secret = $script:GoogleClientSecret
            refresh_token = $refreshToken
            grant_type = "refresh_token"
        } -TimeoutSec 10

        $accessToken = $tokenResp.access_token
        if (-not $accessToken) { return $null }

        # 2. Get Project ID
        $loadResp = Invoke-RestMethod -Uri "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist" -Method Post -Headers @{
            Authorization = "Bearer $accessToken"
            "User-Agent" = "antigravity/1.11.9 windows/amd64"
        } -Body "{}" -ContentType "application/json" -TimeoutSec 10

        $projectID = $loadResp.cloudaicompanionProject
        if (-not $projectID) { $projectID = $loadResp.project }
        if (-not $projectID) { $projectID = "aicode-consumers" }

        # 3. Get Quota Summary
        $quotaResp = Invoke-RestMethod -Uri "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary" -Method Post -Headers @{
            Authorization = "Bearer $accessToken"
            "User-Agent" = "antigravity/1.11.9 windows/amd64"
        } -Body (@{ project = $projectID } | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 10

        $gemini5h = 1.0
        $geminiWeekly = 1.0
        $resetTime = $null

        foreach ($group in $quotaResp.groups) {
            $gName = "$($group.displayName) $($group.description)".ToLower()
            if ($gName -match "gemini") {
                foreach ($bucket in $group.buckets) {
                    $w = "$($bucket.window)".ToLower()
                    if ($w -match "5h") {
                        $gemini5h = [double]$bucket.remainingFraction
                        $resetTime = $bucket.resetTime
                    } elseif ($w -match "week") {
                        $geminiWeekly = [double]$bucket.remainingFraction
                    }
                }
            }
        }

        # Get Google Email if possible
        $email = ""
        try {
            $uinfo = Invoke-RestMethod -Uri "https://www.googleapis.com/oauth2/v3/userinfo" -Headers @{ Authorization = "Bearer $accessToken" } -TimeoutSec 5
            $email = $uinfo.email
        } catch {}

        return [PSCustomObject]@{
            Success = $true
            Email = $email
            Gemini5H = $gemini5h
            GeminiWeekly = $geminiWeekly
            ResetTime = $resetTime
            TokenPath = $tokenFilePath
            AccountName = [System.IO.Path]::GetFileNameWithoutExtension($tokenFilePath)
        }
    } catch {
        return [PSCustomObject]@{
            Success = $false
            Error = $_.Exception.Message
            Gemini5H = -1.0
            GeminiWeekly = -1.0
            TokenPath = $tokenFilePath
            AccountName = [System.IO.Path]::GetFileNameWithoutExtension($tokenFilePath)
        }
    }
}

# Function to get all accounts quota
function Get-AllAccountsQuota {
    $files = Get-ChildItem -Path $accDir -Filter "*.json"
    $list = @()
    foreach ($f in $files) {
        $q = Get-AccountQuotaInfo -tokenFilePath $f.FullName
        if ($q) { $list += $q }
    }
    return $list
}

# Function to switch active account
function Switch-ActiveAccount {
    param ([string]$targetAccountName)

    $srcFile = Join-Path $accDir "$targetAccountName.json"
    if (-not (Test-Path $srcFile)) {
        Write-RotatorLog "Loi: File token $srcFile khong ton tai."
        return $false
    }

    try {
        Copy-Item $srcFile $geminiTokenPath -Force
        Set-Content -Path $activeFile -Value $targetAccountName -Encoding ASCII
        Write-RotatorLog ">>> DA TU DONG XOAY SANG TAI KHOAN: [$targetAccountName]"
        return $true
    } catch {
        Write-RotatorLog "Loi khi copy token: $_"
        return $false
    }
}

# Main Auto-Rotation evaluation logic
function Invoke-AutoRotationCheck {
    $accounts = Get-AllAccountsQuota
    if ($accounts.Count -eq 0) {
        Write-RotatorLog "Chua co tai khoan nao trong danh sach D:\AntigravityAccounts\accounts."
        return
    }

    $currentActive = ""
    if (Test-Path $activeFile) {
        $currentActive = (Get-Content $activeFile -Raw).Trim()
    }

    # Find current active account object
    $currentObj = $accounts | Where-Object { $_.AccountName -eq $currentActive }

    Write-RotatorLog "=== KIEM TRA QUOTA AUTO-ROTATION ==="
    foreach ($acc in $accounts) {
        $pct = [Math]::Round($acc.Gemini5H * 100)
        $tag = if ($acc.AccountName -eq $currentActive) { "[DANG DUNG]" } else { "           " }
        Write-RotatorLog "$tag $($acc.AccountName) ($($acc.Email)) -> Gemini 5H Quota: $pct%"
    }

    # Check if current active account has low quota or expired
    $needSwitch = $false
    if (-not $currentObj -or -not $currentObj.Success -or $currentObj.Gemini5H -le $MinQuotaThreshold) {
        $needSwitch = $true
        if ($currentObj) {
            Write-RotatorLog "Canh bao: Tai khoan [$currentActive] sap het quota ($([Math]::Round($currentObj.Gemini5H * 100))% <= $([Math]::Round($MinQuotaThreshold * 100))%). Dang tim tai khoan tot nhat de xoay..."
        } else {
            Write-RotatorLog "Chua co tai khoan active hop le. Dang tu dong chon tai khoan..."
        }
    }

    if ($needSwitch) {
        # Sort accounts by highest 5h quota
        $bestAccount = $accounts | Where-Object { $_.Success -and $_.Gemini5H -gt $MinQuotaThreshold } | Sort-Object -Property Gemini5H -Descending | Select-Object -First 1

        if ($bestAccount) {
            Write-RotatorLog "Chon tai khoan tot nhat: [$($bestAccount.AccountName)] voi $([Math]::Round($bestAccount.Gemini5H * 100))% Quota."
            Switch-ActiveAccount -targetAccountName $bestAccount.AccountName | Out-Null
        } else {
            Write-RotatorLog "Canh bao: Tat ca tai khoan trong pool deu duoi nguong $([Math]::Round($MinQuotaThreshold * 100))%."
            # Fallback to the one with highest quota overall
            $fallback = $accounts | Where-Object { $_.Success } | Sort-Object -Property Gemini5H -Descending | Select-Object -First 1
            if ($fallback -and $fallback.AccountName -ne $currentActive) {
                Write-RotatorLog "Fallback sang tai khoan co quota cao nhat con lai: [$($fallback.AccountName)] ($([Math]::Round($fallback.Gemini5H * 100))%)"
                Switch-ActiveAccount -targetAccountName $fallback.AccountName | Out-Null
            }
        }
    } else {
        Write-RotatorLog "Tai khoan [$currentActive] van con du quota ($([Math]::Round($currentObj.Gemini5H * 100))% > $([Math]::Round($MinQuotaThreshold * 100))%). Giu nguyen phien."
    }
}

if ($RunOnce) {
    Invoke-AutoRotationCheck
} elseif ($Daemon) {
    Write-RotatorLog "KHOI CHAY ANTIGRAVITY AUTO-ROTATOR DAEMON (Chu ky: ${IntervalSeconds}s)"
    while ($true) {
        try {
            Invoke-AutoRotationCheck
        } catch {
            Write-RotatorLog "Loi ngoai le trong chu trinh: $_"
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
}
