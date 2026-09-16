$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'AntigravityMcp.ps1') -LibraryOnly
$script:Checks=0
function Assert($condition,[string]$name) {
    if (-not $condition) { throw "FAIL: $name" }
    $script:Checks++; Write-Host "PASS: $name"
}
function Message($method,$parameters=@{},$id=1) {
    Invoke-McpMessage (@{jsonrpc='2.0';id=$id;method=$method;params=$parameters} | ConvertTo-Json -Depth 8 -Compress)
}
Assert ((Invoke-McpMessage '{bad').error.code -eq -32700) 'Malformed JSON returns parse error'
Assert ((Invoke-McpMessage '[]').error.code -eq -32600) 'Batch request rejected'
Assert ((Message 'tools/list').error.code -eq -32002) 'Tools unavailable before initialization'
$hello=Message 'initialize' @{protocolVersion='2025-06-18';capabilities=@{};clientInfo=@{name='tests';version='1'}}
Assert ($hello.result.protocolVersion -eq '2025-06-18') 'MCP version negotiation'
$notification=Invoke-McpMessage '{"jsonrpc":"2.0","method":"notifications/initialized"}'
Assert ($null -eq $notification -and $script:McpInitialized) 'Initialized notification produces no output'
$listing=Message 'tools/list'
Assert (@($listing.result.tools).Count -eq 2) 'Default server exposes read-only tools'
Assert ((Message 'ping').result.Count -eq 0) 'Ping supported'
Assert ((Message 'unsupported').error.code -eq -32601) 'Unknown RPC rejected'

$script:SwitchCalls=0
function Get-RuntimeIdentity { [pscustomobject]@{Email='fixture@example.test';Idle=$true;Runtimes=@(@{Csrf='SECRET_SENTINEL'})} }
function Read-RotationState { [pscustomobject]@{Status='Verified';Account='fixture';Email='fixture@example.test';UpdatedAt='2026-09-16';Private='SECRET_SENTINEL'} }
function Get-AllAccountsQuota { @([pscustomobject]@{AccountName='fixture';Email='fixture@example.test';Success=$false;Gemini5H=-1;GeminiWeekly=-1;TokenPath='SECRET_SENTINEL';Error='SECRET_SENTINEL'}) }
function Switch-ActiveAccount { param($targetAccountName) $script:SwitchCalls++; Write-Host 'not protocol'; $script:SwitchResult }
function Invoke-AutoRotationCheck { Write-Host 'not protocol' }
function Repair-RotationState { $false }
$status=Message 'tools/call' @{name='antigravity_status';arguments=@{}}
$text=$status | ConvertTo-Json -Depth 12
Assert (-not $text.Contains('SECRET_SENTINEL') -and $text.Contains('fixture@example.test')) 'Status uses allowlist projection without CSRF'
$accounts=Message 'tools/call' @{name='antigravity_accounts';arguments=@{}}
$data=$accounts.result.content[0].text | ConvertFrom-Json
Assert ($null -eq $data.accounts[0].remaining5h -and -not ($accounts | ConvertTo-Json -Depth 12).Contains('SECRET_SENTINEL')) 'Unknown quota stays null, token paths omitted'
$blocked=Message 'tools/call' @{name='antigravity_switch_account';arguments=@{account='fixture'}}
Assert ($blocked.result.isError -and $script:SwitchCalls -eq 0) 'Read-only gate enforced on tool execution'
$script:McpAllowSwitch=$true
Assert (@((Message 'tools/list').result.tools).Count -eq 5) 'Explicit switch permission exposes mutation tools'
foreach ($args in @(@{account='../escape'},@{account='fixture';force=$true},@{account=123},@{})) {
    $result=Message 'tools/call' @{name='antigravity_switch_account';arguments=$args}
    Assert ($result.result.isError -and $script:SwitchCalls -eq 0) 'Invalid mutation arguments rejected'
}
$notification=Invoke-McpMessage '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"antigravity_switch_account","arguments":{"account":"fixture"}}}'
Assert ($null -eq $notification -and $script:SwitchCalls -eq 0) 'Mutation notifications never execute'
$script:SwitchResult=$false
$rejected=Message 'tools/call' @{name='antigravity_switch_account';arguments=@{account='fixture'}}
Assert ($rejected.result.isError -and $script:SwitchCalls -eq 1) 'Deferred switch returns tool error'
$script:SwitchResult=$true
$accepted=Message 'tools/call' @{name='antigravity_switch_account';arguments=@{account='fixture'}}
Assert (-not $accepted.result.isError -and $script:SwitchCalls -eq 2) 'Switch delegates to existing engine'
$check=Message 'tools/call' @{name='antigravity_rotate_if_needed';arguments=@{}}
Assert (($check.result.content[0].text | ConvertFrom-Json).checkCompleted -and -not $check.result.content[0].text.Contains('switched')) 'Quota check does not claim a switch'
function Get-AllAccountsQuota { throw 'SECRET_SENTINEL' }
$failure=Message 'tools/call' @{name='antigravity_accounts';arguments=@{}}
Assert ($failure.result.isError -and -not ($failure | ConvertTo-Json -Depth 12).Contains('SECRET_SENTINEL')) 'Downstream exceptions redacted'

# Real stdio subprocess from a fresh folder with spaces, no account files/config.
$stage=Join-Path $repo ('work\mcp smoke ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($file in @('AntigravityMcp.ps1','AutoRotator.ps1','RotationCore.ps1','RuntimeBridge.ps1','Configure-Mcp.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $stage
}
$psi=[Diagnostics.ProcessStartInfo]::new()
$psi.FileName='powershell.exe'
$psi.Arguments='-NoLogo -NoProfile -NonInteractive -File "' + (Join-Path $stage 'AntigravityMcp.ps1') + '"'
$psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
$psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
$psi.EnvironmentVariables.Remove('ANTIGRAVITY_GOOGLE_CLIENT_ID')
$psi.EnvironmentVariables.Remove('ANTIGRAVITY_GOOGLE_CLIENT_SECRET')
$process=[Diagnostics.Process]::Start($psi)
$outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
$lines=@(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}'
    '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"antigravity_accounts","arguments":{}}}'
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"antigravity_switch_account","arguments":{"account":"fixture"}}}'
)
# Exercise the Windows UTF-8 BOM case explicitly, independent of the host codepage.
$inputWriter=[IO.StreamWriter]::new($process.StandardInput.BaseStream, [Text.UTF8Encoding]::new($true))
foreach ($line in $lines) { $inputWriter.WriteLine($line) }
$inputWriter.Close()
if (-not $process.WaitForExit(20000)) { $process.Kill(); throw 'MCP smoke timed out' }
$stdout=$outTask.GetAwaiter().GetResult(); $stderr=$errTask.GetAwaiter().GetResult()
Assert ($process.ExitCode -eq 0 -and -not $stderr) 'Fresh-clone server exits cleanly at EOF'
$responses=@($stdout -split '\r?\n' | Where-Object { $_ } | ForEach-Object { ConvertFrom-Json $_ })
Assert ($responses.Count -eq 4 -and $responses[0].result.protocolVersion -eq '2025-11-25' -and @($responses | Where-Object {$_.jsonrpc -ne '2.0'}).Count -eq 0) 'UTF-8 BOM input initializes; stdout contains only JSON-RPC'
Assert (@($responses[1].result.tools).Count -eq 2 -and $responses[3].result.isError) 'Real subprocess enforces read-only default'
Assert (@(($responses[2].result.content[0].text | ConvertFrom-Json).accounts).Count -eq 0) 'Fresh clone empty pool works without OAuth secrets'
$config=(& powershell.exe -NoProfile -File (Join-Path $stage 'Configure-Mcp.ps1') -AllowSwitch) | Out-String | ConvertFrom-Json
$server=$config.mcpServers.'antigravity-auto-hub'
Assert ($server.args -contains (Join-Path $stage 'AntigravityMcp.ps1') -and $server.args -contains '-AllowSwitch') 'Generated config uses actual clone path with spaces'
Write-Host "MCP: $script:Checks checks passed"
