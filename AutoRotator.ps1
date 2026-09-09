# ==============================================================================
# ANTIGRAVITY AUTO-ROTATOR ENGINE (EARLY ROTATION AT 10-12% & FAST SCAN)
# ==============================================================================
param (
    [switch]$RunOnce,
    [switch]$Daemon,
    [switch]$Reconcile,
    [ValidateRange(10,3600)][int]$IntervalSeconds = 25,
    [ValidateRange(0,0.95)][double]$MinQuotaThreshold = 0.12,
    [ValidateRange(0,0.95)][double]$MinWeeklyThreshold = 0.08
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

if (-not ("WinCred" -as [type])) {
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
}

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

$stateFile = Join-Path $baseDir 'rotation-state.json'
$script:GoogleClientId = $env:ANTIGRAVITY_GOOGLE_CLIENT_ID
$script:GoogleClientSecret = $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET
if (-not $script:GoogleClientId -or -not $script:GoogleClientSecret) {
    $localConfig = Join-Path $baseDir 'oauth.local.clixml'
    if (Test-Path -LiteralPath $localConfig) {
        try {
            $config = Import-Clixml -LiteralPath $localConfig
            $script:GoogleClientId = $config.UserName
            $script:GoogleClientSecret = $config.GetNetworkCredential().Password
        } catch { Write-Warning 'Local OAuth configuration cannot be decrypted by this Windows user.' }
    }
}
. (Join-Path $baseDir 'RuntimeBridge.ps1')
. (Join-Path $baseDir 'RotationCore.ps1')
$script:LastSwitchTime = [datetime]::MinValue

if ($Reconcile) {
    Repair-RotationState
} elseif ($RunOnce) {
    Invoke-AutoRotationCheck
} elseif ($Daemon) {
    $daemonMutex = [Threading.Mutex]::new($false, 'Local\AntigravityAutoHub.Daemon')
    $daemonLocked = $false
    try {
        try { $daemonLocked = $daemonMutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $daemonLocked = $true }
        if (-not $daemonLocked) { return }
        Write-RotatorLog "Daemon started; interval ${IntervalSeconds}s after each completed scan."
        while ($true) {
            try { Invoke-AutoRotationCheck }
            catch { Write-RotatorLog 'Scan failed; retrying on next interval.' }
            Start-Sleep -Seconds $IntervalSeconds
        }
    } finally {
        if ($daemonLocked) { $daemonMutex.ReleaseMutex() }
        $daemonMutex.Dispose()
    }
}
