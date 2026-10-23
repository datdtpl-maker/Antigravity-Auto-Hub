$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'AutoRotator.ps1')
function Assert($Value,$Name){if(-not $Value){throw $Name};Write-Host "PASS: $Name"}
$disabled=[pscustomobject]@{models=[pscustomobject]@{'gemini-4-argon-disabled'=[pscustomobject]@{displayName='Gemini 4 Argon';disabled=$true}}}
$q=Convert-ArgonModelQuota $disabled
Assert ($q.Status -eq 'Disabled' -and $q.Remaining -eq -1) 'Explicit provider-disabled Argon is distinguished from missing quota'
$enabled=[pscustomobject]@{models=[pscustomobject]@{
    'gemini-4-argon-high'=[pscustomobject]@{quotaInfo=@{remainingFraction=.7}}
    'gemini-4-argon-medium'=[pscustomobject]@{quotaInfo=@{remainingFraction=.8}}
}}
$q=Convert-ArgonModelQuota $enabled
Assert ($q.Status -eq 'Available' -and $q.Remaining -eq .7) 'Read conservative Argon model quota without logging into the IDE'
$enabled.models.'gemini-4-argon-high'.quotaInfo.remainingFraction=0
Assert ((Convert-ArgonModelQuota $enabled).Remaining -eq 0) 'Zero model quota is real exhaustion'
foreach($invalid in @($null,'NaN',-1,1.1,'not-a-number')) {
    $enabled.models.'gemini-4-argon-high'.quotaInfo.remainingFraction=$invalid
    Assert ((Convert-ArgonModelQuota $enabled).Status -eq 'Unknown') 'Incomplete or invalid Argon variant quota is not invented from another variant'
}
Assert ((Convert-ArgonModelQuota ([pscustomobject]@{models=@{}})).Status -eq 'Unknown') 'Missing model catalog does not mean Argon disabled'

# Exercise the real account pipeline, mocking only credentials and HTTP.
function Get-FreshToken {param($Token) [pscustomobject]@{token=@{access_token='fixture'}}}
function Get-Content {param($LiteralPath,[switch]$Raw,$Encoding) '{}'}
$script:catalog=$disabled;$script:catalogFails=$false;$script:catalogCalls=0;$script:separate=$false
function Invoke-RestMethod {
    param($Uri,$Method,$Headers,$Body,$ContentType,$TimeoutSec,$ErrorAction)
    if($Uri -match '/userinfo$'){return @{email='fixture@example.test'}}
    if($Uri -match ':loadCodeAssist$'){return @{cloudaicompanionProject=@{id='fixture-project'}}}
    if($Uri -match ':retrieveUserQuotaSummary$'){
        $groups=@(@{displayName='Gemini Models';buckets=@(@{window='5h';remainingFraction=.7},@{window='week';remainingFraction=.8})})
        if($script:separate){$groups+=@{displayName='Gemini 4 Argon';buckets=@(@{window='weekly';remainingFraction=.3})}}
        return @{groups=$groups}
    }
    if($Uri -match ':fetchAvailableModels$'){
        $script:catalogCalls++
        Assert (($Body|ConvertFrom-Json).project -eq 'fixture-project') 'Model lookup uses this saved account project'
        if($script:catalogFails){throw 'provider body with fixture-private-token'}
        return $script:catalog
    }
    throw 'Unexpected API call'
}
$q=Get-AccountQuotaInfo 'fixture.json'
Assert ($q.Success -and $q.ArgonStatus -eq 'Disabled' -and $q.ArgonWeekly -eq -1 -and $q.GeminiWeekly -eq .8) 'Saved account reports disabled Argon while preserving usable Gemini quota'
$enabled.models.'gemini-4-argon-high'.quotaInfo.remainingFraction=.6
$script:catalog=$enabled
$q=Get-AccountQuotaInfo 'fixture.json'
Assert ($q.Success -and $q.ArgonStatus -eq 'Available' -and $q.ArgonWeekly -eq .6 -and $q.ArgonQuotaSource -eq 'ModelCatalog') 'Missing summary Argon falls back to real per-model quota'
$script:catalogFails=$true
$q=Get-AccountQuotaInfo 'fixture.json'
Assert ($q.Success -and $q.ArgonStatus -eq 'Unknown' -and $q.ArgonWeekly -eq -1 -and ($q|ConvertTo-Json -Compress) -notmatch 'fixture-private-token') 'Catalog failure leaves Argon unknown without losing Gemini quota or leaking errors'
$script:separate=$true;$script:catalogCalls=0
$q=Get-AccountQuotaInfo 'fixture.json'
Assert ($q.ArgonWeekly -eq .3 -and $q.ArgonQuotaSource -eq 'Summary' -and $script:catalogCalls -eq 0) 'Separate Argon summary needs no additional model request'
