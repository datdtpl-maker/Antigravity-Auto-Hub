$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $repo ('work\oauth clone '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'RotationCore.ps1') -Destination $fixture
. (Join-Path $fixture 'RotationCore.ps1')
$baseDir=$fixture
$configPath=Join-Path $fixture 'oauth.local.clixml'
$previousId=$env:ANTIGRAVITY_GOOGLE_CLIENT_ID
$previousSecret=$env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET
function Assert($Value,$Name) { if(-not $Value){throw $Name}; Write-Host "PASS: $Name" }
function Reset-Config {
    $script:GoogleClientId=$null; $script:GoogleClientSecret=$null
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$null; $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$null
    $script:Requests=0; $script:SentClient=$null; $script:SentSecret=$null
}
# Never contact Google or use real account tokens in these tests.
function Invoke-RestMethod {
    param($Uri,$Method,$Body,$TimeoutSec,$ErrorAction)
    $script:Requests++
    $script:SentClient=$Body.client_id; $script:SentSecret=$Body.client_secret
    [pscustomobject]@{access_token='fixture-access';expires_in=3600}
}
$token=[pscustomobject]@{token=@{refresh_token='fixture-refresh'}}
try {
    Reset-Config
    $failure=$null
    try { $null=Get-FreshToken $token } catch { $failure=$_.Exception.Message }
    Assert ($failure -eq 'OAuth configuration missing.' -and $script:Requests -eq 0) 'Fresh clone does not borrow another installation OAuth configuration'

    [pscredential]::new('fixture-local-id',(ConvertTo-SecureString 'fixture-local-secret' -AsPlainText -Force)) | Export-Clixml -LiteralPath $configPath
    Reset-Config
    $fresh=Get-FreshToken $token
    Assert ($script:SentClient -eq 'fixture-local-id' -and $script:SentSecret -eq 'fixture-local-secret' -and $fresh.token.refresh_token -eq 'fixture-refresh') 'Refresh loads DPAPI configuration from clone path with spaces'

    Reset-Config
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID='fixture-env-id'
    $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET='fixture-env-secret'
    $null=Get-FreshToken $token
    Assert ($script:SentClient -eq 'fixture-env-id' -and $script:SentSecret -eq 'fixture-env-secret') 'Complete environment configuration takes precedence over local file'

    Reset-Config
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID='fixture-incomplete-env'
    $null=Get-FreshToken $token
    Assert ($script:SentClient -eq 'fixture-local-id' -and $script:SentSecret -eq 'fixture-local-secret') 'Partial environment uses the complete local credential pair'

    Reset-Config
    [IO.File]::WriteAllText($configPath,'invalid fixture XML')
    $failure=$null
    try { $null=Get-FreshToken $token } catch { $failure=$_.Exception.Message }
    Assert ($failure -eq 'OAuth configuration missing.' -and $script:Requests -eq 0) 'Unreadable local configuration fails before network access'

    Reset-Config
    $script:GoogleClientId='fixture-cached-id'; $script:GoogleClientSecret='fixture-cached-secret'
    $null=Get-FreshToken $token
    Assert ($script:SentClient -eq 'fixture-cached-id' -and $script:SentSecret -eq 'fixture-cached-secret') 'Existing process configuration remains usable without rereading file'
} finally {
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$previousId
    $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$previousSecret
    $resolved=[IO.Path]::GetFullPath($fixture)
    $allowedRoot=[IO.Path]::GetFullPath((Join-Path $repo 'work'))+'\'
    if($resolved.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^oauth clone [a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
