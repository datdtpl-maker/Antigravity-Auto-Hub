# Local Antigravity 2.x language-server bridge. Never exports CSRF or token data.
if (-not ('AntigravityLocalRpc' -as [type])) {
    # .NET 8 marks HttpWebRequest obsolete; retain its per-request certificate callback
    # for Windows PowerShell 5.1 compatibility without changing global TLS validation.
    Add-Type -IgnoreWarnings -WarningAction SilentlyContinue @"
using System;
using System.IO;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Text.RegularExpressions;
public static class AntigravityLocalRpc {
    public static string Cdp(string address, string message) {
        var uri = new Uri(address);
        if (uri.Scheme != "ws" || uri.Host != "127.0.0.1" || !uri.AbsolutePath.StartsWith("/devtools/page/"))
            throw new ArgumentException("Expected local page debugger");
        using (var timeout = new CancellationTokenSource(5000))
        using (var socket = new ClientWebSocket()) {
            socket.Options.Proxy = null;
            socket.ConnectAsync(uri, timeout.Token).GetAwaiter().GetResult();
            byte[] payload = Encoding.UTF8.GetBytes(message);
            socket.SendAsync(new ArraySegment<byte>(payload), WebSocketMessageType.Text, true, timeout.Token).GetAwaiter().GetResult();
            var buffer = new byte[8192];
            while (true) {
                using (var data = new MemoryStream()) {
                    WebSocketReceiveResult part;
                    do {
                        part = socket.ReceiveAsync(new ArraySegment<byte>(buffer), timeout.Token).GetAwaiter().GetResult();
                        if (part.MessageType == WebSocketMessageType.Close) throw new IOException("Debugger closed");
                        data.Write(buffer, 0, part.Count);
                        if (data.Length > 1048576) throw new IOException("Debugger response too large");
                    } while (!part.EndOfMessage);
                    var result = Encoding.UTF8.GetString(data.ToArray());
                    if (Regex.IsMatch(result, "\"id\"\\s*:\\s*1\\s*[,}]")) return result;
                }
            }
        }
    }
    public static string Post(int port, string csrf, string method) {
        // The method and loopback origin are fixed; no arbitrary destinations.
        if (method != "GetUserStatus" && method != "GetAllCascadeTrajectories")
            throw new ArgumentException("Unsupported read-only method");
        var request = (HttpWebRequest)WebRequest.Create("https://127.0.0.1:" + port +
            "/exa.language_server_pb.LanguageServerService/" + method);
        request.Proxy = null;
        request.AllowAutoRedirect = false;
        request.Method = "POST";
        request.ContentType = "application/json";
        request.Headers["x-codeium-csrf-token"] = csrf;
        request.Timeout = 5000;
        request.ReadWriteTimeout = 5000;
        // Only this loopback request accepts the application's self-signed certificate.
        request.ServerCertificateValidationCallback = (sender, cert, chain, errors) => true;
        byte[] body = Encoding.UTF8.GetBytes("{}");
        request.ContentLength = body.Length;
        using (var stream = request.GetRequestStream()) stream.Write(body, 0, body.Length);
        using (var response = request.GetResponse())
        using (var reader = new StreamReader(response.GetResponseStream())) return reader.ReadToEnd();
    }
}
"@
}

function Get-AntigravityRuntime {
    $parents = @(Get-CimInstance Win32_Process -Filter "Name = 'Antigravity.exe'" -ErrorAction Stop)
    $servers = @(Get-CimInstance Win32_Process -Filter "Name = 'language_server.exe'" -ErrorAction Stop)
    $results = @()
    foreach ($server in $servers) {
        $parent = $parents | Where-Object { $_.ProcessId -eq $server.ParentProcessId } | Select-Object -First 1
        if (-not $parent -or -not $parent.ExecutablePath) { continue }
        $expected = Join-Path (Split-Path $parent.ExecutablePath) 'resources\bin\language_server.exe'
        if ($server.ExecutablePath -ne $expected -or $server.CommandLine -notmatch '--standalone') { continue }
        if ((Get-Item -LiteralPath $parent.ExecutablePath).VersionInfo.ProductVersion -notlike '2.12.2*') {
            throw 'This Antigravity version has not been validated for supervised restart.'
        }
        $csrfMatch = [regex]::Match($server.CommandLine, '--csrf_token(?:=|\s+)"?([^\s"]+)')
        if (-not $csrfMatch.Success) { throw 'Runtime CSRF unavailable; rotation deferred.' }
        $ports = @(Get-NetTCPConnection -OwningProcess $server.ProcessId -State Listen -ErrorAction Stop |
            Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0', '::') } |
            Select-Object -ExpandProperty LocalPort -Unique)
        $found = $false
        foreach ($port in $ports) {
            try {
                $status = [AntigravityLocalRpc]::Post($port, $csrfMatch.Groups[1].Value, 'GetUserStatus') | ConvertFrom-Json
                if (-not $status.userStatus.email) { continue }
                $results += [pscustomobject]@{
                    ProcessId = $server.ProcessId; ParentProcessId = $parent.ProcessId
                    CreationDate = $server.CreationDate; ExecutablePath = $expected
                    Port = $port; Csrf = $csrfMatch.Groups[1].Value; Email = $status.userStatus.email
                }
                $found = $true
                break
            } catch { }
        }
        if (-not $found) { throw 'Cannot verify language-server identity; rotation deferred.' }
    }
    if ($parents.Count -and -not $results.Count) { throw 'Antigravity is starting or unsupported; rotation deferred.' }
    return $results
}

function Test-RuntimeIdle {
    param($Runtime)
    $response = [AntigravityLocalRpc]::Post($Runtime.Port, $Runtime.Csrf, 'GetAllCascadeTrajectories') | ConvertFrom-Json
    # An empty proto map is omitted. An unexpected response must fail closed.
    if ($response.PSObject.Properties.Name -contains 'trajectorySummaries') {
        foreach ($summary in $response.trajectorySummaries.PSObject.Properties.Value) {
            if ($summary.status -ne 'CASCADE_RUN_STATUS_IDLE') { return $false }
        }
    } elseif (($response | ConvertTo-Json -Compress) -ne '{}') { return $false }
    return $true
}

function Get-RuntimeIdentity {
    $runtimes = @(Get-AntigravityRuntime)
    if (-not $runtimes.Count) { return $null }
    if ($runtimes.Count -ne 1) { throw 'Multiple desktop runtimes detected; rotation deferred.' }
    $emails = @($runtimes.Email | Select-Object -Unique)
    if ($emails.Count -ne 1) { throw 'Multiple IDE identities detected; rotation deferred.' }
    $idle = $true
    foreach ($runtime in $runtimes) { if (-not (Test-RuntimeIdle $runtime)) { $idle = $false } }
    [pscustomobject]@{ Email = $emails[0]; Idle = $idle; Runtimes = $runtimes }
}

function Restart-AntigravityRuntime {
    param($Runtime)
    # Revalidate PID identity and activity immediately before the scoped restart.
    $current = Get-CimInstance Win32_Process -Filter "ProcessId = $($Runtime.ProcessId)" -ErrorAction Stop
    if (-not $current -or $current.CreationDate -ne $Runtime.CreationDate -or
        $current.ParentProcessId -ne $Runtime.ParentProcessId -or $current.ExecutablePath -ne $Runtime.ExecutablePath) {
        throw 'Runtime changed during switch.'
    }
    if (-not (Test-RuntimeIdle $Runtime)) { throw 'An agent became active; switch deferred.' }
    $windows = @(Get-RuntimeWindows $Runtime)
    if (@($windows | Where-Object { -not $_.Safe }).Count) { throw 'An editor is active; switch deferred.' }
    # Antigravity 2.12.2 supervises this child and reconnects its windows itself.
    Stop-Process -Id $Runtime.ProcessId -ErrorAction Stop
}

function Get-RuntimeWindows {
    param($Runtime)
    $portFile = Join-Path $env:APPDATA 'Antigravity\DevToolsActivePort'
    $debugPort = 0
    if (-not (Test-Path -LiteralPath $portFile) -or
        -not [int]::TryParse((Get-Content -LiteralPath $portFile -First 1), [ref]$debugPort)) { throw 'Debugger unavailable.' }
    $owner = @(Get-NetTCPConnection -LocalPort $debugPort -State Listen -ErrorAction Stop)
    if (-not ($owner | Where-Object { $_.OwningProcess -eq $Runtime.ParentProcessId -and $_.LocalAddress -eq '127.0.0.1' })) {
        throw 'Debugger is not owned by the IDE.'
    }
    $pages = @(Invoke-RestMethod "http://127.0.0.1:$debugPort/json/list" -TimeoutSec 5 -ErrorAction Stop |
        ForEach-Object { $_ } | Where-Object { $_.type -eq 'page' })
    if (-not $pages.Count) { throw 'No desktop window to preserve.' }
    foreach ($page in $pages) {
        $uri = [uri]$page.url
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne $Runtime.Port) { throw 'Unrecognized IDE page.' }
        $ws = [uri]$page.webSocketDebuggerUrl
        if ($ws.Port -ne $debugPort) { throw 'Unexpected debugger endpoint.' }
        # Do not capture draft content. Only a boolean leaves the renderer.
        $expression = @'
(() => {
  const a = document.activeElement;
  if (a && (a.matches('input,textarea,[contenteditable="true"]') || a.closest('[contenteditable="true"]'))) return false;
  return !Array.from(document.querySelectorAll('textarea,input:not([type="hidden"]),[contenteditable="true"]'))
    .some(e => (e.value || e.textContent || '').trim().length > 0);
})()
'@
        $response = [AntigravityLocalRpc]::Cdp($ws.AbsoluteUri, (@{id=1;method='Runtime.evaluate';params=@{expression=$expression;returnByValue=$true}} | ConvertTo-Json -Depth 5 -Compress)) | ConvertFrom-Json
        [pscustomobject]@{ Id=$page.id; WebSocket=$ws.AbsoluteUri; PathAndQuery=$uri.PathAndQuery; Safe=($response.result.result.value -eq $true -and -not $response.error) }
    }
}

function Restore-RuntimeWindows {
    param($SavedWindows)
    $runtimes = @(Get-AntigravityRuntime)
    if ($runtimes.Count -ne 1) { throw 'New runtime unavailable.' }
    $current = @(Get-RuntimeWindows $runtimes[0])
    foreach ($saved in $SavedWindows) {
        $page = $current | Where-Object { $_.Id -eq $saved.Id } | Select-Object -First 1
        if (-not $page -or -not $page.Safe) { throw 'Window changed or user is editing; cannot restore navigation.' }
        $url = "https://127.0.0.1:$($runtimes[0].Port)$($saved.PathAndQuery)"
        $reply = [AntigravityLocalRpc]::Cdp($page.WebSocket, (@{id=1;method='Page.navigate';params=@{url=$url}} | ConvertTo-Json -Compress)) | ConvertFrom-Json
        if ($reply.error -or $reply.result.errorText) { throw 'Window restore failed.' }
    }
}

function Wait-AntigravityIdentity {
    param([string]$Email, [int]$TimeoutSeconds = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        try {
            $runtime = @(Get-AntigravityRuntime)
            if ($runtime.Count -and @($runtime | Where-Object { $_.Email -ne $Email }).Count -eq 0) { return $true }
        } catch { }
    } while ((Get-Date) -lt $deadline)
    return $false
}
