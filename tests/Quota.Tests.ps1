$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'AutoRotator.ps1')
function Assert($Value,$Name){if(-not $Value){throw $Name};Write-Host "PASS: $Name"}
function Get-FreshToken {param($Token) [pscustomobject]@{token=@{access_token='fixture'}}}
function Get-Content {param($LiteralPath,[switch]$Raw,$Encoding) '{}'}
$script:quotaMode='verify'
function Invoke-RestMethod {
    param($Uri,$Method,$Headers,$Body,$ContentType,$TimeoutSec,$ErrorAction)
    if($Uri -match '/userinfo$'){return [pscustomobject]@{email='fixture@example.test'}}
    if($Uri -match ':loadCodeAssist$'){return [pscustomobject]@{cloudaicompanionProject='fixture'}}
    if($script:quotaMode -eq 'valid'){return [pscustomobject]@{groups=@([pscustomobject]@{displayName='Gemini';buckets=@([pscustomobject]@{window='5h';remainingFraction=.7},[pscustomobject]@{window='week';remainingFraction=.8})})}}
    $errorRecord=[Management.Automation.ErrorRecord]::new([Exception]::new('fixture private body'),'HttpError',[Management.Automation.ErrorCategory]::PermissionDenied,$null)
    $reason=if($script:quotaMode -eq 'unknown'){'OTHER'}else{'VALIDATION_REQUIRED'}
    $url=if($script:quotaMode -eq 'unsafe'){'https://evil.test/signin/continue'}else{'https://accounts.google.com/signin/continue?fixture=private'}
    $errorRecord.ErrorDetails=[Management.Automation.ErrorDetails]::new((@{error=@{message='fixture-private-message';details=@(@{'@type'='type.googleapis.com/google.rpc.ErrorInfo';reason=$reason;metadata=@{validation_url=$url}})}}|ConvertTo-Json -Depth 6 -Compress))
    throw $errorRecord
}
$q=Get-AccountQuotaInfo 'fixture.json'
Assert (-not $q.Success -and $q.ErrorCode -eq 'AccountVerificationRequired' -and $q.Gemini5H -eq -1) 'Quota validation requirement remains unknown quota with explicit cause'
Assert ($q.Email -eq 'fixture@example.test' -and $q.VerificationUrl -like 'https://accounts.google.com/signin/continue*') 'Verified Google link is available for account action without losing identity'
Assert ($q.Error -notmatch 'private|http') 'Quota error message does not expose provider body or verification URL'
$script:quotaMode='unsafe';$q=Get-AccountQuotaInfo 'fixture.json'
Assert ($q.ErrorCode -eq 'AccountVerificationRequired' -and -not $q.VerificationUrl) 'Untrusted validation link is not exposed to browser action'
$script:quotaMode='unknown';$q=Get-AccountQuotaInfo 'fixture.json'
Assert (-not $q.Success -and $q.ErrorCode -eq 'QuotaUnavailable' -and -not $q.VerificationUrl) 'Unknown provider error stays unavailable without raw details'
$script:quotaMode='valid';$q=Get-AccountQuotaInfo 'fixture.json'
Assert ($q.Success -and $q.Gemini5H -eq .7 -and $q.GeminiWeekly -eq .8 -and -not $q.VerificationUrl -and -not $q.ErrorCode) 'Successful rescan clears validation state and uses actual quota'
