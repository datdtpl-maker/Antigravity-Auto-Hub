param([switch]$AllowSwitch, [switch]$LibraryOnly)
$ErrorActionPreference='Stop'
# stdout belongs exclusively to newline-delimited JSON-RPC. No GUI or daemon starts.
try { . (Join-Path $PSScriptRoot 'AutoRotator.ps1') 3>$null 4>$null 5>$null 6>$null }
catch { [Console]::Error.WriteLine('Cannot initialize Antigravity Hub. Check Windows/OAuth configuration.'); exit 1 }
$script:McpAllowSwitch=[bool]$AllowSwitch
$script:McpInitialized=$false
$script:McpInitializeReceived=$false

function Get-McpTools {
    $none=@{type='object';properties=@{};additionalProperties=$false}
    @(
        @{name='antigravity_status';description='Read local Antigravity Desktop identity and rotation state. Does not expose tokens.';inputSchema=$none;annotations=@{readOnlyHint=$true;openWorldHint=$false}}
        @{name='antigravity_accounts';description='Read quota for local saved Google accounts. Network requests to Google; no account switching.';inputSchema=$none;annotations=@{readOnlyHint=$true;openWorldHint=$true}}
    )
    if ($script:McpAllowSwitch) {
        @(
            @{name='antigravity_rotate_if_needed';description='Check quota and rotate local Antigravity Desktop only when low, idle and draft-free. May restart its language server. Does not rotate credentials of an independent MCP/provider.';inputSchema=$none;annotations=@{readOnlyHint=$false;destructiveHint=$true;idempotentHint=$false;openWorldHint=$true}}
            @{name='antigravity_switch_account';description='Switch local Antigravity Desktop to a saved account. May restart its language server; existing safety checks still apply. Requires account name from antigravity_accounts.';inputSchema=@{type='object';properties=@{account=@{type='string';minLength=1;maxLength=200;pattern='^[a-zA-Z0-9_.@-]+$'}};required=@('account');additionalProperties=$false};annotations=@{readOnlyHint=$false;destructiveHint=$true;idempotentHint=$false;openWorldHint=$true}}
            @{name='antigravity_reconcile';description='Reconcile a paused rotation only when runtime identity matches stored credentials. Updates Hub state; does not restart the IDE.';inputSchema=$none;annotations=@{readOnlyHint=$false;destructiveHint=$false;idempotentHint=$true;openWorldHint=$true}}
        )
    }
}

function Get-McpStatus {
    $runtime=$null; $runtimeError=$null
    try { $runtime=Get-RuntimeIdentity } catch { $runtimeError=Get-RuntimeFailureMessage $_ }
    $state=Read-RotationState
    # Explicit projection: never serialize runtime objects (they contain CSRF).
    @{
        scope='local_antigravity_desktop'; switchEnabled=$script:McpAllowSwitch
        connected=[bool]$runtime; email=$(if($runtime){$runtime.Email}else{$null})
        idle=$(if($runtime){[bool]$runtime.Idle}else{$null}); runtimeError=$runtimeError
        rotation=$(if($state){@{status=$state.Status;account=$state.Account;email=$state.Email;updatedAt=$state.UpdatedAt}}else{$null})
    }
}

function Invoke-McpTool {
    param([string]$Name, $Arguments)
    if ($null -eq $Arguments) { $Arguments=[pscustomobject]@{} }
    if ($Arguments -isnot [pscustomobject]) { throw 'Invalid arguments' }
    $keys=@($Arguments.PSObject.Properties | ForEach-Object { $_.Name })
    $known=@(Get-McpTools | ForEach-Object { $_.name })
    if ($Name -notin $known) { throw 'Unknown or disabled tool' }
    if ($Name -eq 'antigravity_switch_account') {
        if ($keys.Count -ne 1 -or $keys[0] -ne 'account' -or $Arguments.account -isnot [string] -or
            $Arguments.account.Length -gt 200 -or $Arguments.account -notmatch '^[a-zA-Z0-9_.@-]+$' -or
            $Arguments.account -in @('.','..')) { throw 'Invalid account' }
    } elseif ($keys.Count) { throw 'Unexpected arguments' }
    switch ($Name) {
        'antigravity_status' { return Get-McpStatus }
        'antigravity_accounts' {
            $accounts=@(Get-AllAccountsQuota | ForEach-Object {
                @{account=$_.AccountName;email=$_.Email;quotaAvailable=[bool]$_.Success
                  remaining5h=$(if($_.Success){$_.Gemini5H}else{$null})
                  remainingWeekly=$(if($_.Success){$_.GeminiWeekly}else{$null})}
            })
            return @{accounts=$accounts}
        }
        'antigravity_switch_account' {
            $accepted=Switch-ActiveAccount -targetAccountName $Arguments.account 3>$null 4>$null 5>$null 6>$null
            return @{operationAccepted=[bool]$accepted;status=(Get-McpStatus)}
        }
        'antigravity_rotate_if_needed' {
            Invoke-AutoRotationCheck 3>$null 4>$null 5>$null 6>$null | Out-Null
            # A completed check may deliberately do nothing. Do not claim a switch.
            return @{checkCompleted=$true;status=(Get-McpStatus)}
        }
        'antigravity_reconcile' {
            $accepted=Repair-RotationState 3>$null 4>$null 5>$null 6>$null
            return @{reconciled=[bool]$accepted;status=(Get-McpStatus)}
        }
    }
}

function New-McpError {
    param($Id,[int]$Code,[string]$Message)
    @{jsonrpc='2.0';id=$Id;error=@{code=$Code;message=$Message}}
}

function Invoke-McpMessage {
    param([string]$Line)
    try { $request=ConvertFrom-Json -InputObject $Line -ErrorAction Stop }
    catch { return New-McpError $null -32700 'Parse error' }
    if ($request -isnot [pscustomobject] -or $request.jsonrpc -cne '2.0' -or $request.method -isnot [string]) {
        return New-McpError $null -32600 'Invalid request'
    }
    $hasId=$request.PSObject.Properties.Name -contains 'id'
    if (-not $hasId) {
        if ($request.method -ceq 'notifications/initialized' -and $script:McpInitializeReceived) { $script:McpInitialized=$true }
        return # Never execute tools from a notification.
    }
    $id=$request.id
    if ($null -eq $id -or ($id -isnot [string] -and $id -isnot [int] -and $id -isnot [long])) {
        return New-McpError $null -32600 'Invalid request id'
    }
    if ($null -ne $request.params -and $request.params -isnot [pscustomobject]) { return New-McpError $id -32602 'Invalid params' }
    switch -CaseSensitive ($request.method) {
        'initialize' {
            if ($script:McpInitializeReceived) { return New-McpError $id -32600 'Already initialized' }
            if ($request.params.protocolVersion -isnot [string] -or $request.params.clientInfo -isnot [pscustomobject] -or $request.params.capabilities -isnot [pscustomobject]) {
                return New-McpError $id -32602 'Invalid initialization params'
            }
            $version=$request.params.protocolVersion
            if ($version -notin @('2024-11-05','2025-03-26','2025-06-18','2025-11-25')) { $version='2025-11-25' }
            $script:McpInitializeReceived=$true
            return @{jsonrpc='2.0';id=$id;result=@{protocolVersion=$version;capabilities=@{tools=@{listChanged=$false}};serverInfo=@{name='antigravity-auto-hub';version='1.0.0'};instructions='Controls local Windows Antigravity Desktop only. No token export. Independent MCP providers require their own credential adapter. Switching may restart the language server; wait for idle and no drafts.'}}
        }
        'ping' { return @{jsonrpc='2.0';id=$id;result=@{}} }
        default {
            if (-not $script:McpInitialized) { return New-McpError $id -32002 'Initialize the session first' }
            if ($request.method -ceq 'tools/list') {
                return @{jsonrpc='2.0';id=$id;result=@{tools=@(Get-McpTools)}}
            }
            if ($request.method -cne 'tools/call') { return New-McpError $id -32601 'Method not found' }
            if ($request.params.name -isnot [string]) { return New-McpError $id -32602 'Missing tool name' }
            try {
                $value=Invoke-McpTool $request.params.name $request.params.arguments
                $failed=($value.ContainsKey('operationAccepted') -and -not $value.operationAccepted) -or
                    ($value.ContainsKey('reconciled') -and -not $value.reconciled)
                $result=@{content=@(@{type='text';text=($value | ConvertTo-Json -Depth 15 -Compress)});isError=[bool]$failed}
            } catch {
                # Do not serialize exception messages: downstream errors can contain credentials.
                $result=@{content=@(@{type='text';text='Tool unavailable, invalid arguments, or operation failed. Check local Hub configuration and rotator.log.'});isError=$true}
            }
            return @{jsonrpc='2.0';id=$id;result=$result}
        }
    }
}

if (-not $LibraryOnly) {
    # Read redirected UTF-8 directly; Console encoding/codepage can prepend or
    # misread the first BOM on Windows. Responses always use UTF-8 without BOM.
    $inputReader=[IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false), $true)
    $outputWriter=[IO.StreamWriter]::new([Console]::OpenStandardOutput(), [Text.UTF8Encoding]::new($false))
    $outputWriter.AutoFlush=$true
    $firstLine=$true
    while ($null -ne ($line=$inputReader.ReadLine())) {
        if ($firstLine) { $line=$line.TrimStart([char]0xFEFF); $firstLine=$false }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            if ($line.Length -gt 65536) { $response=New-McpError $null -32600 'Request too large' }
            else { $response=Invoke-McpMessage $line }
            if ($null -ne $response) { $outputWriter.WriteLine(($response | ConvertTo-Json -Depth 20 -Compress)) }
        } catch { $outputWriter.WriteLine('{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}') }
    }
}
