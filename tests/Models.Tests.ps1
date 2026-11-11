$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'AutoRotator.ps1')
function Assert($Value,$Name){if(-not $Value){throw $Name};Write-Host "PASS: $Name"}
$catalog=[pscustomobject]@{models=[pscustomobject]@{
    'claude-opus-5-5-medium'=[pscustomobject]@{displayName='Claude Opus 5.5 Medium';disabled=$false;quotaInfo=@{remainingFraction=.71;resetTime='2026-11-18T00:00:00Z'}}
    'claude-sonnet-5-5-high'=[pscustomobject]@{displayName='Claude Sonnet 5.5 High';quotaInfo=@{remainingFraction=0}}
    'gpt-oss-120b'=[pscustomobject]@{displayName='GPT-OSS 120B';quotaInfo=@{remainingFraction=1}}
    'gemini-4-carbon-disabled'=[pscustomobject]@{displayName='Gemini 4 Carbon';disabled=$true;quotaInfo=@{remainingFraction=1}}
    'gemini-3.8-flash-high'=[pscustomobject]@{displayName='Gemini 3.8 Flash High';quotaInfo=@{remainingFraction=.9}}
    'gemini-4-argon-low'=[pscustomobject]@{displayName='Gemini 4 Argon Low';quotaInfo=@{remainingFraction=.5}}
    'gemini-2.5-flash'=[pscustomobject]@{displayName='Gemini 3.5 Flash Lite';quotaInfo=@{remainingFraction=.8}}
    'internal-model'=[pscustomobject]@{quotaInfo=@{remainingFraction=1};access_token='PRIVATE_SENTINEL'}
}}
$models=@(Convert-ModelQuotaCatalog $catalog)
Assert ($models.Count -eq 7 -and @($models | Where-Object Family -eq 'Other').Count -eq 1) 'Catalog preserves named models and excludes internal unnamed models'
foreach($family in @('Opus','Sonnet','GptOss','Carbon','Flash','Argon')){Assert (@($models|Where-Object Family -eq $family).Count -eq 1) "Recognizes model family $family"}
Assert (($models|Where-Object Family -eq Carbon).Status -eq 'Disabled' -and ($models|Where-Object Family -eq Carbon).Remaining -eq -1) 'Explicit disabled wins over quota and never becomes 100 percent'
Assert (($models|Where-Object Family -eq Sonnet).Remaining -eq 0) 'Zero quota remains available but exhausted'
Assert (($models|Where-Object Family -eq Opus).ResetAt -eq '2026-11-18T00:00:00.0000000Z') 'Reset timestamp is normalized to UTC'
Assert (($models|ConvertTo-Json) -notmatch 'PRIVATE_SENTINEL|access_token') 'Projection excludes all raw provider fields and secrets'
foreach($invalid in @($null,'NaN',-0.1,1.01,'Infinity','bad',$true)) {Assert ((ConvertTo-QuotaFraction $invalid) -eq -1) 'Malformed fractions stay unknown'}
$catalog.models.'claude-opus-5-5-medium'.disabled='true'
Assert ((Convert-ModelQuotaCatalog $catalog | Where-Object Family -eq Opus).Status -eq 'Unknown') 'Malformed disabled flag is unknown, not guessed enabled'
$catalog.models.'claude-opus-5-5-medium'.disabled=$false
function Get-FreshToken {param($Token) [pscustomobject]@{token=@{access_token='fixture'}}}
function Get-Content {param($LiteralPath,[switch]$Raw,$Encoding) '{}'}
$script:catalogCalls=0;$script:catalogFails=$false;$script:summaryFails=$false
function Invoke-RestMethod {
    param($Uri,$Method,$Headers,$Body,$ContentType,$TimeoutSec,$ErrorAction)
    if($Uri -match '/userinfo$'){return @{email='fixture@example.test'}}
    if($Uri -match ':loadCodeAssist$'){return @{cloudaicompanionProject='fixture-project'}}
    if($Uri -match ':fetchAvailableModels$'){
        $script:catalogCalls++
        Assert (($Body|ConvertFrom-Json).project -eq 'fixture-project') 'Model request uses the saved account project'
        if($script:catalogFails){throw 'PRIVATE_SENTINEL'}
        return $catalog
    }
    if($Uri -match ':retrieveUserQuotaSummary$'){
        if($script:summaryFails){throw 'PRIVATE_SENTINEL'}
        return @{groups=@(
            @{displayName='Gemini Models';buckets=@(@{window='5h';remainingFraction=.7},@{window='weekly';remainingFraction=.8})}
            @{displayName='Gemini 4 Argon';buckets=@(@{window='weekly';remainingFraction=.3})}
            @{displayName='Claude and GPT models';buckets=@(@{window='5h';remainingFraction=.4},@{window='weekly';remainingFraction=.6})}
        )}
    }
    throw 'Unexpected API call'
}
$quota=Get-AccountQuotaInfo 'fixture.json' -IncludeModels
Assert ($quota.Success -and $quota.ModelQuotas.Count -eq 7 -and $quota.QuotaGroups.Count -eq 5 -and $script:catalogCalls -eq 1) 'Full scan fetches all models once and preserves shared quota windows'
Assert ($quota.ArgonWeekly -eq .3 -and $quota.Gemini5H -eq .7) 'Read-only model monitoring does not alter rotation quota policy'
Assert ($quota.CheckedAt -and $quota.ModelsStatus -eq 'Available') 'Account result exposes completion timestamp and model scan status'
$catalog.models.'gemini-4-carbon-disabled'.disabled=$false
$catalog.models.'gemini-4-carbon-disabled'.quotaInfo.remainingFraction=.8
$quota=Get-AccountQuotaInfo 'fixture.json' -IncludeModels
Assert (($quota.ModelQuotas|Where-Object Family -eq Carbon).Status -eq 'Available' -and ($quota.ModelQuotas|Where-Object Family -eq Carbon).Remaining -eq .8) 'Newly granted model access is detected on the next scan without login or cached disabled state'
$script:catalogFails=$true
$quota=Get-AccountQuotaInfo 'fixture.json' -IncludeModels
Assert ($quota.Success -and $quota.ModelQuotas.Count -eq 0 -and $quota.ModelsStatus -eq 'Unavailable') 'Catalog failure preserves valid summary and clears previous models'
$script:catalogFails=$false;$script:summaryFails=$true
$quota=Get-AccountQuotaInfo 'fixture.json' -IncludeModels
Assert (-not $quota.Success -and $quota.ModelQuotas.Count -eq 7) 'Summary failure does not discard independent model quota'
Assert (($quota|ConvertTo-Json -Depth 6) -notmatch 'PRIVATE_SENTINEL') 'Failed API requests never expose raw error contents'
$script:summaryFails=$false;$script:catalogCalls=0
$quota=Get-AccountQuotaInfo 'fixture.json'
Assert ($quota.Success -and $script:catalogCalls -eq 0) 'Rotation-only scans avoid extra full catalog calls'
