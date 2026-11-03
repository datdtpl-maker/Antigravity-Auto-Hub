$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'RotationCore.ps1')
function Assert($Value,$Name){if(-not $Value){throw $Name};Write-Host "PASS: $Name"}
$free=@{id='free-tier'}
Assert ((Convert-AccountPlan @{currentTier=$free}).Name -eq 'Free') 'Explicit free service tier is recognized'
$response=@{currentTier=$free;paidTier=@{id='g1-pro-tier'}}
$p=Convert-AccountPlan $response
Assert ($p.Name -eq 'Pro' -and $p.Source -eq 'PaidTier') 'Paid Pro overrides free service tier'
$response.paidTier.id='g1-ultra-tier'
Assert ((Convert-AccountPlan $response).Name -eq 'Ultra') 'Ultra entitlement is recognized'
$response.paidTier.id='future-tier';$response.paidTier.name='Google AI Pro'
Assert ((Convert-AccountPlan $response).Name -eq 'Unknown') 'Unknown paid tier is not downgraded to Free or guessed from its name'
Assert ((Convert-AccountPlan @{currentTier=$free;paidTier=@{}}).Name -eq 'Unknown') 'Incomplete paid entitlement is unknown'
Assert ((Convert-AccountPlan @{allowedTiers=@(@{id='g1-ultra-tier'});upgradeSubscriptionText='Google AI Ultra'}).Name -eq 'Unknown') 'Upgrade offers are not subscriptions'
Assert ((Convert-AccountPlan $null).Name -eq 'Unknown') 'Missing API data is unknown'
$response.paidTier=$null
Assert ((Convert-AccountPlan $response).Name -eq 'Free') 'Next scan re-evaluates a removed paid entitlement'

# Real account pipeline with only credentials, disk reads and network mocked.
function Get-FreshToken {param($Token) [pscustomobject]@{token=@{access_token='fixture'}}}
function Get-Content {param($LiteralPath,[switch]$Raw,$Encoding) '{}'}
$script:paid='g1-pro-tier';$script:quotaFails=$false;$script:authFails=$false
function Invoke-RestMethod {
    param($Uri,$Method,$Headers,$Body,$ContentType,$TimeoutSec,$ErrorAction)
    if($script:authFails){throw 'fixture authentication failure'}
    if($Uri -match '/userinfo$'){return @{email='fixture@example.test'}}
    if($Uri -match ':loadCodeAssist$'){return @{currentTier=@{id='free-tier'};paidTier=@{id=$script:paid};cloudaicompanionProject='fixture-project'}}
    if($Uri -match ':retrieveUserQuotaSummary$'){
        if($script:quotaFails){throw 'fixture quota failure'}
        return @{groups=@(@{displayName='Gemini Models';buckets=@(@{window='5h';remainingFraction=.9},@{window='weekly';remainingFraction=.8})})}
    }
    if($Uri -match ':fetchAvailableModels$'){return @{models=[pscustomobject]@{'gemini-4-argon-disabled'=@{disabled=$true}}}}
    throw 'Unexpected API call'
}
$q=Get-AccountQuotaInfo 'fixture.json'
Assert ($q.Success -and $q.Plan -eq 'Pro' -and $q.ArgonStatus -eq 'Disabled') 'Pro plan does not imply Argon access'
$script:paid='g1-ultra-tier'
Assert ((Get-AccountQuotaInfo 'fixture.json').Plan -eq 'Ultra') 'Plan updates on a subsequent scan without login'
$script:quotaFails=$true
$q=Get-AccountQuotaInfo 'fixture.json'
Assert (-not $q.Success -and $q.Plan -eq 'Ultra') 'Successful plan lookup survives a later quota failure'
$script:authFails=$true
Assert ((Get-AccountQuotaInfo 'fixture.json').Plan -eq 'Unknown') 'Failed authentication does not reuse a previous plan'
