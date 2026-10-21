$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'OAuthSetup.ps1')
function Assert($Value,$Name) { if(-not $Value){throw $Name}; Write-Host "PASS: $Name" }
# Windows PowerShell 5.1 can leave ErrorDetails empty on an HTTP error.
# Model its WebException.Response rather than supplying ErrorDetails ourselves.
Add-Type @'
using System;
using System.IO;
using System.Net;
using System.Text;
using System.Net.Sockets;
using System.Threading.Tasks;
public sealed class SetupFixtureResponse : WebResponse {
    public int StatusCode { get; set; }
    public string Body;
    public override Stream GetResponseStream() { return new MemoryStream(Encoding.UTF8.GetBytes(Body)); }
}
public sealed class SetupLoopbackServer : IDisposable {
    private readonly TcpListener listener;
    private readonly Task worker;
    public int Port { get; private set; }
    public SetupLoopbackServer(int status, string body) {
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start(); Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        worker = Task.Run(() => {
            using (var client = listener.AcceptTcpClient()) {
                client.ReceiveTimeout = 5000; client.SendTimeout = 5000;
                using (var stream = client.GetStream()) {
                    var header = new StringBuilder(); int ch;
                    while ((ch = stream.ReadByte()) != -1) {
                        header.Append((char)ch);
                        if (header.Length > 16384) throw new IOException("FixtureHeaderTooLarge");
                        if (header.ToString().EndsWith("\r\n\r\n")) break;
                    }
                    if (header.ToString().IndexOf("Expect: 100-continue", StringComparison.OrdinalIgnoreCase) >= 0) {
                        var interim = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n");
                        stream.Write(interim, 0, interim.Length);
                    }
                    var length = System.Text.RegularExpressions.Regex.Match(header.ToString(), @"(?i)Content-Length:\s*(\d+)");
                    if (length.Success) {
                        int remaining = Int32.Parse(length.Groups[1].Value);
                        if (remaining > 16384) throw new IOException("FixtureBodyTooLarge");
                        while (remaining-- > 0) { if (stream.ReadByte() < 0) throw new IOException("FixtureBodyTruncated"); }
                    }
                    // A test-only fixed response. No account credentials are used.
                    var payload = Encoding.UTF8.GetBytes(body);
                    var prefix = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + " Fixture\r\nContent-Type: application/json\r\nContent-Length: " + payload.Length + "\r\nConnection: close\r\n\r\n");
                    stream.Write(prefix, 0, prefix.Length); stream.Write(payload, 0, payload.Length);
                }
            }
        });
    }
    public void Dispose() { listener.Stop(); if (!worker.Wait(6000)) throw new IOException("FixtureTimeout"); }
}
'@
$script:body='{"error":"invalid_client","error_description":"fixture private detail"}'
$script:status=401
$script:transport=[Net.WebExceptionStatus]::ProtocolError
$script:loopback=$null
function Invoke-RestMethod {
    param($Uri,$Method,$Body,$TimeoutSec,$ErrorAction)
    if ($script:loopback) {
        return Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri "http://127.0.0.1:$($script:loopback.Port)/token" -Method Post -Body 'fixture=only' -TimeoutSec 5 -ErrorAction Stop
    }
    $response=[SetupFixtureResponse]::new()
    $response.StatusCode=$script:status
    $response.Body=$script:body
    if ($script:transport -ne [Net.WebExceptionStatus]::ProtocolError) { $response=$null }
    throw [Net.WebException]::new('fixture private exception',[Exception]::new('fixture private inner'),$script:transport,$response)
}
$credential=[pscredential]::new('fixture-id',(ConvertTo-SecureString 'fixture-secret' -AsPlainText -Force))
$result=$null; $failure=$null
try { $result=Test-SetupOAuthCredential $credential 'fixture-refresh' } catch { $failure=$_.Exception.Message }
Assert ($null -eq $failure -and $result -eq $false) 'HTTP invalid_client without ErrorDetails advances candidate discovery instead of reporting network failure'
foreach ($code in @('invalid_grant','unauthorized_client')) {
    $script:body='{"error":"'+$code+'"}'; $script:status=400
    Assert (-not (Test-SetupOAuthCredential $credential 'fixture-refresh')) "Stream-only $code is rejected without being classified as network failure"
}
foreach ($case in @(
    @(401,'not-json','SetupOAuthRejected'),
    @(403,'<html>proxy private details</html>','SetupOAuthRejected'),
    @(401,('x'*65537),'SetupOAuthRejected'),
    @(407,'{"error":"invalid_client"}','SetupOAuthProxy'),
    @(429,'{"error":"invalid_client"}','SetupOAuthRateLimited'),
    @(503,'{"error":"invalid_client"}','SetupOAuthServer')
)) {
    $script:status=$case[0]; $script:body=$case[1]; $failure=$null
    try { $null=Test-SetupOAuthCredential $credential 'fixture-refresh' } catch { $failure=$_.Exception.Message }
    Assert ($failure -eq $case[2]) "HTTP $($case[0]) gets safe classification without accepting a candidate"
}
foreach ($case in @(
    @('NameResolutionFailure','SetupOAuthDns'),@('ProxyNameResolutionFailure','SetupOAuthProxy'),
    @('TrustFailure','SetupOAuthTls'),@('SecureChannelFailure','SetupOAuthTls'),
    @('Timeout','SetupOAuthTimeout'),@('ConnectFailure','SetupOAuthNetwork')
)) {
    $script:transport=[Net.WebExceptionStatus]$case[0]; $failure=$null
    try { $null=Test-SetupOAuthCredential $credential 'fixture-refresh' } catch { $failure=$_.Exception.Message }
    Assert ($failure -eq $case[1]) "Transport $($case[0]) has an explicit safe failure code"
    Assert ((Get-OAuthSetupFailureMessage $failure) -notmatch 'fixture private|fixture-secret') 'Actionable message never exposes provider or credential text'
}
# Exercise genuine Windows PowerShell HTTP exceptions over loopback, no internet.
try {
    $script:loopback=[SetupLoopbackServer]::new(401,'{"error":"invalid_client","error_description":"private fixture detail"}')
    Assert (-not (Test-SetupOAuthCredential $credential 'fixture-refresh')) 'Real PowerShell HTTP 401 response is recognized as a rejected candidate'
} finally { if($script:loopback){$script:loopback.Dispose();$script:loopback=$null} }
try {
    $script:loopback=[SetupLoopbackServer]::new(200,'{"access_token":"fixture-access","expires_in":3600}')
    Assert (Test-SetupOAuthCredential $credential 'fixture-refresh') 'Next candidate can succeed after a real PowerShell HTTP rejection'
} finally { if($script:loopback){$script:loopback.Dispose();$script:loopback=$null} }
