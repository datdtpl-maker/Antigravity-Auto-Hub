# ==============================================================================
# ANTIGRAVITY AUTO-ROTATOR ENGINE (WEEKLY QUOTA & TOAST NOTIFICATION SUPPORT)
# ==============================================================================
param (
    [switch]$RunOnce,
    [switch]$Daemon,
    [int]$IntervalSeconds = 60,
    [double]$MinQuotaThreshold = 0.10,
    [double]$MinWeeklyThreshold = 0.05
)

$baseDir = $PSScriptRoot
if (-not $baseDir) { $baseDir = (Get-Location).Path }
$accDir = Join-Path $baseDir "accounts"
$activeFile = Join-Path $baseDir "current_active.txt"
$logFile = Join-Path $baseDir "rotator.log"
$geminiTokenPath = Join-Path $env:USERPROFILE ".gemini\jetski-standalone-oauth-token"

if (-not (Test-Path $accDir)) {
    New-Item -ItemType Directory -Path $accDir -Force | Out-Null
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinCred {
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite([In] ref CREDENTIAL userCredential, [In] uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
    public static extern void CredFree(IntPtr buffer);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    public static string Read(string target) {
        IntPtr credPtr;
        if (CredRead(target, 1, 0, out credPtr)) {
            try {
                CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
                byte[] b = new byte[cred.CredentialBlobSize];
                Marshal.Copy(cred.CredentialBlob, b, 0, cred.CredentialBlobSize);
                return Encoding.UTF8.GetString(b);
            } finally {
                CredFree(credPtr);
            }
        }
        return null;
    }

    public static bool Write(string target, string userName, string secret) {
        byte[] b = Encoding.UTF8.GetBytes(secret);
        IntPtr ptr = Marshal.AllocHGlobal(b.Length);
        Marshal.Copy(b, 0, ptr, b.Length);

        CREDENTIAL cred = new CREDENTIAL();
        cred.Type = 1;
        cred.TargetName = target;
        cred.UserName = userName;
        cred.CredentialBlob = ptr;
        cred.CredentialBlobSize = b.Length;
        cred.Persist = 2;

        try {
            return CredWrite(ref cred, 0);
        } finally {
            Marshal.FreeHGlobal(ptr);
        }
    }

    public static bool Delete(string target) {
        return CredDelete(target, 1, 0);
    }
}
"@

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

function Send-ToastNotification {
    param (
        [string]$Title = "Antigravity Auto-Hub",
        [string]$Message = ""
    )
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $safeTitle = [System.Security.SecurityElement]::Escape($Title)
        $safeMsg = [System.Security.SecurityElement]::Escape($Message)

        $template = @"
<toast duration="short">
    <visual>
        <binding template="ToastGeneric">
            <text>$safeTitle</text>
            <text>$safeMsg</text>
        </binding>
    </visual>
</toast>
"@
        $xmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xmlDoc.LoadXml($template)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xmlDoc
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe")
        $notifier.Show($toast)
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $notify = New-Object System.Windows.Forms.NotifyIcon
            $notify.Icon = [System.Drawing.SystemIcons]::Information
            $notify.BalloonTipTitle = $Title
            $notify.BalloonTipText = $Message
            $notify.Visible = $true
            $notify.ShowBalloonTip(3000)
        } catch {}
    }
}

function Get-AccountQuotaInfo {
    param ([string]$tokenFilePath)
    
    if (-not (Test-Path $tokenFilePath)) { return $null }

    try {
        $tokenRaw = Get-Content $tokenFilePath -Raw | ConvertFrom-Json
        $refreshToken = $tokenRaw.token.refresh_token
        if (-not $refreshToken) { $refreshToken = $tokenRaw.refresh_token }
        if (-not $refreshToken) { return $null }

        $tokenResp = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body @{
            client_id = $script:GoogleClientId
            client_secret = $script:GoogleClientSecret
            refresh_token = $refreshToken
            grant_type = "refresh_token"
        } -TimeoutSec 10

        $accessToken = $tokenResp.access_token
        if (-not $accessToken) { return $null }

        $loadResp = Invoke-RestMethod -Uri "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist" -Method Post -Headers @{
            Authorization = "Bearer $accessToken"
            "User-Agent" = "antigravity/1.11.9 windows/amd64"
        } -Body "{}" -ContentType "application/json" -TimeoutSec 10

        $projectID = $loadResp.cloudaicompanionProject
        if (-not $projectID) { $projectID = $loadResp.project }
        if (-not $projectID) { $projectID = "aicode-consumers" }

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

function Get-AllAccountsQuota {
    $files = Get-ChildItem -Path $accDir -Filter "*.json"
    $list = @()
    foreach ($f in $files) {
        $q = Get-AccountQuotaInfo -tokenFilePath $f.FullName
        if ($q) { $list += $q }
    }
    return $list
}

function Switch-ActiveAccount {
    param (
        [string]$targetAccountName,
        [switch]$Notify
    )

    $srcFile = Join-Path $accDir "$targetAccountName.json"
    if (-not (Test-Path $srcFile)) {
        Write-RotatorLog "Loi: File token $srcFile khong ton tai."
        return $false
    }

    try {
        $tokenContent = [System.IO.File]::ReadAllText($srcFile, [System.Text.Encoding]::UTF8)
        
        [WinCred]::Write("gemini:antigravity", "antigravity", $tokenContent) | Out-Null
        [System.IO.File]::WriteAllText($geminiTokenPath, $tokenContent, [System.Text.Encoding]::UTF8)
        Set-Content -Path $activeFile -Value $targetAccountName -Encoding ASCII
        
        Write-RotatorLog ">>> DA TU DONG XOAY SANG TAI KHOAN: [$targetAccountName]"
        
        if ($Notify) {
            $qInfo = Get-AccountQuotaInfo -tokenFilePath $srcFile
            $pct5h = if ($qInfo) { [Math]::Round($qInfo.Gemini5H * 100) } else { 100 }
            $pctWeekly = if ($qInfo) { [Math]::Round($qInfo.GeminiWeekly * 100) } else { 100 }
            $toastTitle = "$([char]0x26A1) Antigravity Auto-Hub"
            $toastMsg = "$([char]0x0110)$([char]0x00E3) k$([char]0x1EBF)t n$([char]0x1ED1)i t$([char]0x00E0)i kho$([char]0x1EA3)n: $targetAccountName`n$([char]0x2022) Gemini 5H: $pct5h% | Tu$([char]0x1EA7)n: $pctWeekly%"
            Send-ToastNotification -Title $toastTitle -Message $toastMsg
        }
        
        return $true
    } catch {
        Write-RotatorLog "Loi khi chuyen doi tai khoan: $_"
        return $false
    }
}

function Invoke-AutoRotationCheck {
    $accounts = Get-AllAccountsQuota
    if ($accounts.Count -eq 0) {
        Write-RotatorLog "Chua co tai khoan nao trong danh sach $accDir."
        return
    }

    $currentActive = ""
    if (Test-Path $activeFile) {
        $currentActive = (Get-Content $activeFile -Raw).Trim()
    }

    $currentObj = $accounts | Where-Object { $_.AccountName -eq $currentActive }

    Write-RotatorLog "=== KIEM TRA QUOTA AUTO-ROTATION (5H & WEEKLY) ==="
    foreach ($acc in $accounts) {
        $pct5h = [Math]::Round($acc.Gemini5H * 100)
        $pctWeekly = [Math]::Round($acc.GeminiWeekly * 100)
        $tag = if ($acc.AccountName -eq $currentActive) { "[DANG DUNG]" } else { "           " }
        Write-RotatorLog "$tag $($acc.AccountName) ($($acc.Email)) -> 5H: $pct5h% | Tuan: $pctWeekly%"
    }

    # Kiem tra ca 2 dieu kien: Quota 5H <= 10% HOAC Quota Weekly <= 5%
    $needSwitch = $false
    if (-not $currentObj -or -not $currentObj.Success) {
        $needSwitch = $true
        Write-RotatorLog "Chua co tai khoan active hop le. Dang tu dong chon tai khoan..."
    } elseif ($currentObj.Gemini5H -le $MinQuotaThreshold) {
        $needSwitch = $true
        Write-RotatorLog "Canh bao: Tai khoan [$currentActive] sap het Quota 5H ($([Math]::Round($currentObj.Gemini5H * 100))% <= $([Math]::Round($MinQuotaThreshold * 100))%)."
    } elseif ($currentObj.GeminiWeekly -le $MinWeeklyThreshold) {
        $needSwitch = $true
        Write-RotatorLog "Canh bao: Tai khoan [$currentActive] sap het Quota Tuan ($([Math]::Round($currentObj.GeminiWeekly * 100))% <= $([Math]::Round($MinWeeklyThreshold * 100))%)."
    }

    if ($needSwitch) {
        # Tim tai khoan hop le: 5H > 10% VA Weekly > 5%
        $eligible = $accounts | Where-Object { 
            $_.Success -and 
            $_.Gemini5H -gt $MinQuotaThreshold -and 
            $_.GeminiWeekly -gt $MinWeeklyThreshold 
        }

        # Uu tien sap xep theo 5H giam dan, sau do den Weekly giam dan
        $bestAccount = $eligible | Sort-Object -Property @{ Expression = "Gemini5H"; Descending = $true }, @{ Expression = "GeminiWeekly"; Descending = $true } | Select-Object -First 1

        if ($bestAccount) {
            $p5 = [Math]::Round($bestAccount.Gemini5H * 100)
            $pw = [Math]::Round($bestAccount.GeminiWeekly * 100)
            Write-RotatorLog "Chon tai khoan tot nhat: [$($bestAccount.AccountName)] voi 5H: $p5% | Tuan: $pw%"
            Switch-ActiveAccount -targetAccountName $bestAccount.AccountName -Notify | Out-Null
        } else {
            Write-RotatorLog "Canh bao: Tat ca tai khoan deu can kiet quota. Dang tim fallback tot nhat..."
            $fallback = $accounts | Where-Object { $_.Success } | Sort-Object -Property @{ Expression = "Gemini5H"; Descending = $true } | Select-Object -First 1
            if ($fallback -and $fallback.AccountName -ne $currentActive) {
                Write-RotatorLog "Fallback sang tai khoan: [$($fallback.AccountName)]"
                Switch-ActiveAccount -targetAccountName $fallback.AccountName -Notify | Out-Null
            }
        }
    } else {
        $p5 = [Math]::Round($currentObj.Gemini5H * 100)
        $pw = [Math]::Round($currentObj.GeminiWeekly * 100)
        Write-RotatorLog "Tai khoan [$currentActive] con du quota (5H: $p5% > $([Math]::Round($MinQuotaThreshold * 100))% | Tuan: $pw% > $([Math]::Round($MinWeeklyThreshold * 100))%). Giu nguyen phien."
    }
}

if ($RunOnce) {
    Invoke-AutoRotationCheck
} elseif ($Daemon) {
    $currentPid = $PID
    $existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { 
        $_.ProcessId -ne $currentPid -and 
        $_.CommandLine -match "AutoRotator\.ps1" -and 
        $_.CommandLine -match "-Daemon" -and 
        $_.Name -eq "powershell.exe" 
    }
    if ($existing) {
        exit 0
    }
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
