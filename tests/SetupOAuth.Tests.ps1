$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $repo ('work\setup clone '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$previousId=$env:ANTIGRAVITY_GOOGLE_CLIENT_ID
$previousSecret=$env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET
function Assert($Value,$Name) { if(-not $Value){throw $Name}; Write-Host "PASS: $Name" }
function Assert-Failure($Action,$Code) {
    $actual=$null
    try { & $Action | Out-Null } catch { $actual=$_.Exception.Message }
    Assert ($actual -eq $Code) "Setup reports $Code without provider details"
}
try {
    . (Join-Path $repo 'OAuthSetup.ps1')
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$null; $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$null
    $binary=Join-Path $fixture 'language_server.exe'
    $fallback=Join-Path $fixture 'jetski-standalone-oauth-token'
    $configPath=Join-Path $fixture 'oauth.local.clixml'
    # Synthetic strings only. Put one client across the reader's 1 MB boundary.
    $id1='123456789012-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.apps.googleusercontent.com'
    $id2='123456789012-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.apps.googleusercontent.com'
    $secret1='GOCSPX-'+('A'*28); $secret2='GOCSPX-'+('B'*28)
    [IO.File]::WriteAllText($binary,('x'*(1MB-30))+$id1+"`0"+$secret1+"`0"+$id2+"`0"+$secret2+"`0"+$id1)
    $found=Get-InstalledOAuthClients $binary
    Assert ($found.ClientIds.Count -eq 2 -and $found.Secrets.Count -eq 2 -and $id1 -in $found.ClientIds) 'Discover distinct complete clients across binary chunk boundaries'

    $script:stored='{"token":{"refresh_token":"fixture-refresh"}}'
    function Get-StoredCredential { $script:stored }
    $script:requestMode='success'; $script:requests=0
    function Invoke-RestMethod {
        param($Uri,$Method,$Body,$TimeoutSec,$ErrorAction)
        Assert ($Uri -eq 'https://oauth2.googleapis.com/token' -and $Method -eq 'Post') 'Send setup verification only to Google token endpoint'
        $script:requests++
        if($script:requestMode -eq 'offline'){throw 'fixture transport failure containing sensitive data'}
        if($script:requestMode -eq 'empty'){return @{expires_in=3600}}
        if($script:requestMode -eq 'success' -and $Body.client_id -ceq $id2 -and $Body.client_secret -ceq $secret2 -and $Body.refresh_token -eq 'fixture-refresh') {
            return @{access_token='fixture-access';expires_in=3600}
        }
        $errorRecord=[Management.Automation.ErrorRecord]::new([Exception]::new('fixture secret must never appear'),'ProviderError',[Management.Automation.ErrorCategory]::AuthenticationError,$null)
        $code=switch($script:requestMode){'rate-limit'{'rate_limit_exceeded'} 'expired'{'invalid_grant'} default{'invalid_client'}}
        $errorRecord.ErrorDetails=[Management.Automation.ErrorDetails]::new('{"error":"'+$code+'","error_description":"fixture sensitive detail"}')
        throw $errorRecord
    }
    $result=Initialize-HubOAuth $fixture $binary $fallback
    $saved=Import-Clixml -LiteralPath $configPath
    Assert ($result.Source -eq 'Installed' -and $saved.UserName -ceq $id2 -and $saved.GetNetworkCredential().Password -ceq $secret2) 'Fresh clone automatically persists only the client pair verified with local login'
    Assert (([IO.File]::ReadAllText($configPath)) -notmatch [regex]::Escape($secret2)) 'Saved client secret is DPAPI encrypted'
    $before=[IO.File]::ReadAllText($configPath)
    $script:requests=0
    $result=Initialize-HubOAuth $fixture $binary $fallback
    Assert ($result.Source -eq 'Local' -and $script:requests -eq 1 -and [IO.File]::ReadAllText($configPath) -ceq $before) 'Repeat setup verifies and preserves an existing valid configuration'

    $script:requestMode='offline'
    Assert-Failure {Initialize-HubOAuth $fixture $binary $fallback} 'SetupOAuthNetwork'
    Assert ([IO.File]::ReadAllText($configPath) -ceq $before) 'Network failure preserves existing configuration'
    $script:requestMode='rate-limit'
    Assert-Failure {Initialize-HubOAuth $fixture $binary $fallback} 'SetupOAuthRejected'
    $script:requestMode='empty'
    Assert-Failure {Initialize-HubOAuth $fixture $binary $fallback} 'SetupOAuthInvalidResponse'

    $script:requestMode='success'
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID='fixture-invalid-env'
    $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET='fixture-invalid-secret'
    Assert-Failure {Initialize-HubOAuth $fixture $binary $fallback} 'SetupOAuthEnvironmentInvalid'
    Assert ([IO.File]::ReadAllText($configPath) -ceq $before) 'Invalid environment override never overwrites working local configuration'
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$id2; $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$secret2
    $result=Initialize-HubOAuth $fixture $binary $fallback
    Assert ($result.Source -eq 'Environment') 'Verify and persist complete environment pair for future Startup processes'
    $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$null
    $result=Initialize-HubOAuth $fixture $binary $fallback
    Assert ($result.Source -eq 'Local') 'Incomplete environment does not mix credential sources'
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$null

    [IO.File]::WriteAllText($configPath,'unreadable copied DPAPI fixture')
    $result=Initialize-HubOAuth $fixture $binary $fallback
    Assert ($result.Source -eq 'Installed') 'Automatically replace unreadable configuration with locally verified pair'
    $script:stored='not-json'
    [IO.File]::WriteAllText($fallback,'{"refresh_token":"fixture-refresh"}')
    Assert ((Initialize-HubOAuth $fixture $binary $fallback).Source -eq 'Local') 'Use official token file when credential store has no usable token'
    [IO.File]::WriteAllText($fallback,'{}')
    Assert-Failure {Initialize-HubOAuth $fixture $binary $fallback} 'SetupOAuthLoginRequired'
    $script:stored='{"token":{"refresh_token":"fixture-refresh"}}'
    $script:requestMode='mismatch'
    $before=[IO.File]::ReadAllText($configPath)
    Assert-Failure {Initialize-HubOAuth $fixture $binary $fallback} 'SetupOAuthNoMatch'
    Assert ([IO.File]::ReadAllText($configPath) -ceq $before) 'Unverified client candidates never replace configuration'
    $script:requestMode='expired'
    Assert-Failure {Initialize-HubOAuth $fixture $binary $fallback} 'SetupOAuthNoMatch'
    Assert ([IO.File]::ReadAllText($configPath) -ceq $before) 'An invalid_grant response is never accepted as successful OAuth verification'
    [IO.File]::WriteAllText($binary,'unknown application layout')
    Assert-Failure {Get-InstalledOAuthClients $binary} 'SetupOAuthUnsupported'
    Assert-Failure {Get-InstalledOAuthClients (Join-Path $fixture 'missing.exe')} 'SetupAntigravityMissing'
    [IO.File]::WriteAllText($binary,((1..5|ForEach-Object {"123456789012-$('a'*31)$_"+'.apps.googleusercontent.com'}) -join "`0")+"`0"+$secret1)
    Assert-Failure {Get-InstalledOAuthClients $binary} 'SetupOAuthUnsupported'
    $message=Get-OAuthSetupFailureMessage 'unexpected sensitive message'
    Assert ($message -notmatch 'sensitive') 'Installer error output never repeats unknown exception details'
} finally {
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$previousId; $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$previousSecret
    $resolved=[IO.Path]::GetFullPath($fixture)
    $allowedRoot=[IO.Path]::GetFullPath((Join-Path $repo 'work'))+'\'
    if($resolved.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^setup clone [a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
