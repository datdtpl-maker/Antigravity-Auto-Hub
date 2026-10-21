$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $repo ('work\installer clone '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$previousLocal=$env:LOCALAPPDATA
$previousId=$env:ANTIGRAVITY_GOOGLE_CLIENT_ID
$previousSecret=$env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET
function Assert($Value,$Name) { if(-not $Value){throw $Name}; Write-Host "PASS: $Name" }
try {
    foreach($file in @('Setup.ps1','OAuthSetup.ps1')) { Copy-Item -LiteralPath (Join-Path $repo $file) -Destination $fixture }
    $env:LOCALAPPDATA=Join-Path $fixture 'local app data'
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$null; $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$null
    $install=Join-Path $env:LOCALAPPDATA 'Programs\Antigravity'
    New-Item -ItemType Directory -Path (Join-Path $install 'resources\bin') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $install 'Antigravity.exe'),'fixture, never executed')
    [IO.File]::WriteAllText((Join-Path $install 'resources\bin\language_server.exe'),"123456789012-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.apps.googleusercontent.com`0GOCSPX-"+('A'*28))
    # Substitute only external system/network dependencies. Run the real installer
    # and OAuth bootstrap in a separate Windows PowerShell 5.1 process.
    [IO.File]::WriteAllText((Join-Path $fixture 'AutoRotator.ps1'),@'
$geminiTokenPath=Join-Path $PSScriptRoot 'missing-token'
function Assert-AntigravityVersion { param($Version,$ExecutablePath) }
function Get-StoredCredential {
    if(Test-Path (Join-Path $PSScriptRoot 'no-login')){return $null}
    return '{"token":{"refresh_token":"fixture-refresh"}}'
}
function Invoke-RestMethod {
    param($Uri,$Method,$Body,$TimeoutSec,$ErrorAction)
    if(Test-Path (Join-Path $PSScriptRoot 'offline')){throw 'FixtureNetworkError'}
    return @{access_token='fixture-access';expires_in=3600}
}
function New-Object {
    param([string]$TypeName,[object[]]$ArgumentList,[string]$ComObject)
    if($ComObject){throw 'UnexpectedShortcutCreation'}
    Microsoft.PowerShell.Utility\New-Object -TypeName $TypeName -ArgumentList $ArgumentList
}
function Start-Process { throw 'UnexpectedProcessStart' }
'@)
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'Setup.ps1') -ConfigureOnly 2>&1
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $fixture 'oauth.local.clixml'))) 'Real installer configures a fresh clone without manual OAuth entry'
    Assert (($output -join "`n") -match 'ConfigureOnly' -and ($output -join "`n") -notmatch 'fixture-access|fixture-refresh|GOCSPX-') 'Configure-only installer stops before shortcuts and never prints credentials'
    [IO.File]::WriteAllText((Join-Path $fixture 'no-login'),'fixture')
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'Setup.ps1') 2>&1
    Assert ($LASTEXITCODE -eq 1 -and ($output -join "`n") -match 'dang nhap Google tren MAY NAY' -and ($output -join "`n") -notmatch '\[3/5\]') 'Missing login stops real installer before shortcut or daemon creation'
    Remove-Item -LiteralPath (Join-Path $fixture 'no-login')
    [IO.File]::WriteAllText((Join-Path $fixture 'offline'),'fixture')
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'Setup.ps1') 2>&1
    Assert ($LASTEXITCODE -eq 1 -and ($output -join "`n") -match 'Kiem tra mang/proxy/firewall' -and ($output -join "`n") -notmatch '\[3/5\]') 'Network failure stops real installer with actionable message'
    Remove-Item -LiteralPath (Join-Path $install 'Antigravity.exe')
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixture 'Setup.ps1') 2>&1
    Assert ($LASTEXITCODE -eq 1 -and ($output -join "`n") -match 'Cai Antigravity, dang nhap Google') 'Missing Antigravity is explained before OAuth setup'
} finally {
    $env:LOCALAPPDATA=$previousLocal
    $env:ANTIGRAVITY_GOOGLE_CLIENT_ID=$previousId; $env:ANTIGRAVITY_GOOGLE_CLIENT_SECRET=$previousSecret
    $resolved=[IO.Path]::GetFullPath($fixture)
    $allowedRoot=[IO.Path]::GetFullPath((Join-Path $repo 'work'))+'\'
    if($resolved.StartsWith($allowedRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -match '^installer clone [a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
