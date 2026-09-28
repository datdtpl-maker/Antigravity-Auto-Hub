# Isolated official login helper. Never expose its output, CSRF or OAuth response.
if (-not ('AntigravityAccountLogin' -as [type])) {
Add-Type -IgnoreWarnings -WarningAction SilentlyContinue @'
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

public sealed class AntigravityAccountLogin : IDisposable {
    private readonly object gate = new object();
    private readonly string csrf = Guid.NewGuid().ToString();
    private HttpWebRequest request;
    private Task loginTask;
    private bool disposed;
    private string authUrl;
    private int port;
    private string failure;
    private bool succeeded;
    private bool started;
    private string responseJson;
    public Process Process { get; private set; }
    public string AuthUrl { get { lock (gate) return authUrl; } }
    public int Port { get { lock (gate) return port; } }
    public string Failure { get { lock (gate) return failure; } }
    public bool Succeeded { get { lock (gate) return succeeded; } }
    public bool RequestStarted { get { lock (gate) return request != null; } }
    public string ResponseJson { get { lock (gate) return responseJson; } }

    public static string ExtractAuthUrl(string line) {
        if (String.IsNullOrEmpty(line)) return null;
        foreach (Match m in Regex.Matches(line, @"https://[^\s<>""']+")) {
            Uri uri;
            if (Uri.TryCreate(m.Value, UriKind.Absolute, out uri) && uri.Scheme == "https" &&
                uri.Host == "accounts.google.com" && uri.IsDefaultPort && uri.UserInfo == "" &&
                (uri.AbsolutePath == "/o/oauth2/auth" || uri.AbsolutePath == "/o/oauth2/v2/auth") &&
                !String.IsNullOrEmpty(uri.Query)) return uri.AbsoluteUri;
        }
        return null;
    }

    public static ProcessStartInfo CreateStartInfo(string executable, string directory, string csrf) {
        var psi = new ProcessStartInfo(executable);
        psi.Arguments = "--standalone --subclient_type=hub --override_ide_name=antigravity" +
            " --api_server_url=https://generativelanguage.googleapis.com" +
            " --cloud_code_endpoint=https://daily-cloudcode-pa.googleapis.com" +
            " --gemini_dir=\"" + directory + "\" --app_data_dir=app --csrf_token=" + csrf;
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        psi.RedirectStandardError = true; psi.RedirectStandardOutput = true; psi.RedirectStandardInput = true;
        // Ask the official helper to print the URL; the Hub opens it once.
        psi.EnvironmentVariables["ANTIGRAVITY_VSCODE_HOST"] = "1";
        return psi;
    }

    public static bool IsVerificationUrl(string value) {
        Uri uri;
        return Uri.TryCreate(value, UriKind.Absolute, out uri) && uri.Scheme == "https" &&
            uri.Host == "accounts.google.com" && uri.IsDefaultPort && uri.UserInfo == "" &&
            uri.AbsolutePath == "/signin/continue";
    }

    private void OnOutput(object sender, DataReceivedEventArgs e) {
        if (e.Data == null) return;
        lock (gate) {
            if (disposed) return;
            var found = ExtractAuthUrl(e.Data);
            if (request != null && found != null && authUrl == null) authUrl = found;
            var m = Regex.Match(e.Data, @"listening on \w+ port at (\d+) for HTTPS\b");
            int value;
            if (m.Success && Int32.TryParse(m.Groups[1].Value, out value) && value > 0 && value <= 65535)
                port = value;
        }
    }

    public AntigravityAccountLogin(string executable, string directory) {
        Process = new Process(); Process.StartInfo = CreateStartInfo(executable, directory, csrf);
        Process.OutputDataReceived += OnOutput; Process.ErrorDataReceived += OnOutput;
        try {
            if (!Process.Start()) throw new InvalidOperationException("LoginHelperStartFailed");
            started = true;
            Process.BeginOutputReadLine(); Process.BeginErrorReadLine(); Process.StandardInput.Close();
        } catch { Dispose(); throw new InvalidOperationException("LoginHelperStartFailed"); }
    }

    // Caller verifies this listener belongs to Process.Id before invoking.
    public void BeginLogin() {
        lock (gate) {
            if (disposed || request != null || port == 0) return;
            request = (HttpWebRequest)WebRequest.Create("https://127.0.0.1:" + port +
                "/exa.language_server_pb.LanguageServerService/Login");
            request.Proxy = null; request.AllowAutoRedirect = false;
            request.Method = "POST"; request.ContentType = "application/json";
            request.Headers["x-codeium-csrf-token"] = csrf;
            request.Timeout = 300000; request.ReadWriteTimeout = 300000;
            request.ServerCertificateValidationCallback = (a,b,c,d) => true;
            var pending = request;
            loginTask = Task.Run(() => {
                try {
                    var body = Encoding.UTF8.GetBytes("{}"); pending.ContentLength = body.Length;
                    using (var stream = pending.GetRequestStream()) stream.Write(body, 0, body.Length);
                    using (var response = pending.GetResponse()) {
                        using (var reader = new StreamReader(response.GetResponseStream())) {
                            var buffer = new char[4096]; var result = new StringBuilder(); int read;
                            while ((read = reader.Read(buffer, 0, buffer.Length)) > 0) {
                                if (result.Length + read > 1048576) throw new IOException("LoginResponseTooLarge");
                                result.Append(buffer, 0, read);
                            }
                            lock (gate) { if (!disposed) { responseJson = result.ToString(); succeeded = true; } }
                        }
                    }
                } catch {
                    lock (gate) { if (!disposed) failure = "LoginRequestFailed"; }
                }
            });
        }
    }

    public string ReadUserStatus() {
        return ReadAuthRpc("GetUserStatus");
    }

    public string ReadAuthStatus() {
        return ReadAuthRpc("GetAuthStatus");
    }

    private string ReadAuthRpc(string method) {
        lock (gate) { if (disposed || !succeeded) throw new InvalidOperationException("LoginNotComplete"); }
        var read = (HttpWebRequest)WebRequest.Create("https://127.0.0.1:" + Port +
            "/exa.language_server_pb.LanguageServerService/" + method);
        read.Proxy = null; read.AllowAutoRedirect = false; read.Method = "POST";
        read.ContentType = "application/json"; read.Headers["x-codeium-csrf-token"] = csrf;
        read.Timeout = 5000; read.ReadWriteTimeout = 5000;
        read.ServerCertificateValidationCallback = (a,b,c,d) => true;
        var bytes = Encoding.UTF8.GetBytes("{}"); read.ContentLength = bytes.Length;
        using(var stream = read.GetRequestStream()) stream.Write(bytes,0,bytes.Length);
        using(var response = read.GetResponse())
        using(var reader = new StreamReader(response.GetResponseStream())) {
            var buffer = new char[4096]; var result = new StringBuilder(); int count;
            while ((count = reader.Read(buffer,0,buffer.Length)) > 0) {
                if(result.Length + count > 1048576) throw new IOException("LoginResponseTooLarge");
                result.Append(buffer,0,count);
            }
            return result.ToString();
        }
    }

    public void Dispose() {
        lock (gate) { disposed = true; responseJson = null; if (request != null) request.Abort(); }
        if (started && !Process.HasExited) {
            Process.Kill();
            if (!Process.WaitForExit(5000)) throw new InvalidOperationException("LoginHelperStopFailed");
        }
        if (loginTask != null) loginTask.Wait(5000);
    }
}
'@
}

function Get-AccountLoginResult {
    param($Session)
    if (-not $Session.Succeeded) { return $null }
    try { $result=$Session.ResponseJson | ConvertFrom-Json -ErrorAction Stop } catch { throw 'LoginInvalidResponse' }
    $auth=$result.authResult
    if ($null -eq $auth) { $auth=$result.auth_result }
    # OAuth success does not imply Antigravity eligibility. Never save a rejected
    # account or let optional diagnostics obscure the provider's outcome.
    foreach ($failure in @(
        @('ineligible','ineligible','LoginIneligible'),
        @('verificationRequired','verification_required','LoginVerificationRequired'),
        @('tosViolation','tos_violation','LoginTermsRejected'),
        @('generalError','general_error','LoginProviderError'),
        @('projectRequired','project_required','LoginProjectRequired'),
        @('headlessAuthRequired','headless_auth_required','LoginInteractiveRequired'),
        @('licenseRequired','license_required','LoginLicenseRequired')
    )) {
        if ($null -ne $auth.($failure[0]) -or $null -ne $auth.($failure[1])) { throw $failure[2] }
    }
    $valid=$auth.hasValidAuth
    if ($null -eq $valid) { $valid=$auth.has_valid_auth }
    if ($valid -isnot [bool] -or -not $valid) { throw 'LoginAuthRejected' }
    return $auth
}

function Get-AccountLoginProgress {
    param($Session, [switch]$Recheck)
    # Only the isolated helper is polled; the main app's auth state is untouched.
    $response=if($Recheck){$Session.ReadAuthStatus()}else{$Session.ResponseJson}
    try { $body=$response | ConvertFrom-Json -ErrorAction Stop } catch { throw 'LoginInvalidResponse' }
    $auth=$body.authResult
    if($null -eq $auth){$auth=$body.auth_result}
    try {
        $null=Get-AccountLoginResult ([pscustomobject]@{Succeeded=$true;ResponseJson=$response})
        return [pscustomobject]@{Status='Ready';VerificationUrl=$null}
    } catch {
        $code=$_.Exception.Message
        if($code -notin @('LoginIneligible','LoginVerificationRequired')){throw}
        $details=if($null -ne $auth.ineligible){$auth.ineligible}elseif($null -ne $auth.verificationRequired){$auth.verificationRequired}else{$auth.verification_required}
        $url=$details.verificationUrl
        if(-not $url){$url=$details.verification_url}
        if(-not [AntigravityAccountLogin]::IsVerificationUrl($url)){throw $code}
        return [pscustomobject]@{Status='VerificationRequired';VerificationUrl=$url}
    }
}

function Get-AccountLoginTokenCandidates {
    param([string]$TempDirectory, [string]$FallbackPath)
    # Read only the helper's documented token filename, never arbitrary profile files.
    foreach ($path in @((Join-Path $TempDirectory 'jetski-standalone-oauth-token'),
                       (Join-Path $TempDirectory 'app\jetski-standalone-oauth-token'),$FallbackPath)) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            try { [IO.File]::ReadAllText($path) } catch {}
        }
    }
    $stored=Get-StoredCredential
    if ($stored) { $stored }
}

function Get-VerifiedAccountLoginToken {
    param([string[]]$Candidates, [string]$ExpectedEmail)
    if ($ExpectedEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'LoginIdentityMissing' }
    foreach ($raw in @($Candidates | Select-Object -Unique)) {
        try {
            $parsed=$raw | ConvertFrom-Json -ErrorAction Stop
            if (-not (Get-RefreshToken $parsed)) { continue }
            $token=Get-FreshToken $parsed
            $user=Invoke-RestMethod 'https://www.googleapis.com/oauth2/v3/userinfo' -Headers @{Authorization="Bearer $($token.token.access_token)"} -TimeoutSec 10 -ErrorAction Stop
            if ($user.email -ieq $ExpectedEmail) { return [pscustomobject]@{Email=$user.email;Token=$token} }
        } catch {}
    }
    return $null
}
function Update-AccountLoginSession {
    param($Session)
    if ($Session.Process.HasExited) { throw 'LoginHelperExited' }
    if ($Session.Failure) { throw 'LoginRequestFailed' }
    if ($Session.Port -and -not $Session.RequestStarted) {
        $listeners = @(Get-NetTCPConnection -LocalPort $Session.Port -State Listen -ErrorAction Stop)
        if (-not ($listeners | Where-Object { $_.OwningProcess -eq $Session.Process.Id -and $_.LocalAddress -in @('127.0.0.1','::1') })) {
            throw 'LoginListenerMismatch'
        }
        $Session.BeginLogin()
    }
}
