# Use a client compatible with the account's refresh token. Never pass secrets on the command line.
$ErrorActionPreference = 'Stop'
$clientId = Read-Host 'Google OAuth client ID'
$clientSecret = Read-Host 'Google OAuth client secret' -AsSecureString
if (-not $clientId -or $clientSecret.Length -eq 0) { throw 'OAuth client configuration is required.' }
$credential = [pscredential]::new($clientId, $clientSecret)
$credential | Export-Clixml -LiteralPath (Join-Path $PSScriptRoot 'oauth.local.clixml')
Write-Host 'Saved with Windows DPAPI for this Windows user. Restart Hub and daemon to load it.'
