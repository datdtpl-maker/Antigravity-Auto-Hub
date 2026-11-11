$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'AutoRotator.ps1')
function Assert($Condition,$Name){if(-not $Condition){throw $Name};Write-Host "PASS: $Name"}
$script:Selected='Claude Sonnet 5.5 Medium';$script:Idle=$true;$script:FixtureState=$null
function Write-RotatorLog {param($Message)}
function Get-RuntimeIdentity {[pscustomobject]@{Email='current@example.test';Idle=$script:Idle;Runtimes=@(@{})}}
function Get-RuntimeSelectedModel {param($Runtime) $script:Selected}
function Get-AllAccountsQuota {param([switch]$IncludeModels) Assert $IncludeModels 'Automatic scan includes model catalogs';$script:FixtureAccounts}
function Read-RotationState {$script:FixtureState}
function Switch-ActiveAccount {param($targetAccountName,$Reason,[switch]$Notify,$ExpectedModel,$ExpectedEmail) $script:Switched=$targetAccountName;$script:ExpectedModel=$ExpectedModel;$script:ExpectedEmail=$ExpectedEmail;$true}
function Account($Name,[double]$Quota,[string]$Status='Available',[double]$Shared=1){
    [pscustomobject]@{AccountName=$Name;Email="$Name@example.test";Success=$true;ModelsStatus='Available';Gemini5H=1;GeminiWeekly=1;ArgonWeekly=0;ModelQuotas=@([pscustomobject]@{Name='Claude Sonnet 5.5 (Medium)';Family='Sonnet';Remaining=$Quota;Status=$Status});QuotaGroups=@([pscustomobject]@{Name='Claude and GPT models';Window='weekly';Remaining=$Shared})}
}
function Check($Accounts,$Expected,$Name){$script:FixtureAccounts=$Accounts;$script:Switched='';Invoke-AutoRotationCheck;Assert ($script:Switched -eq $Expected) $Name}
Check @((Account current .19),(Account other .8)) 'other' 'Selected Sonnet below twenty percent rotates despite unrelated exhausted Argon'
Assert ($script:ExpectedModel -eq $script:Selected -and $script:ExpectedEmail -eq 'current@example.test') 'Transaction receives expected model and active identity for race protection'
Check @((Account current .20),(Account other .8)) '' 'Exactly twenty percent does not trigger'
Check @((Account current .21),(Account other .8)) '' 'Healthy selected model does not rotate for unused models'
Check @((Account current .1),(Account other .2)) '' 'Target must exceed twenty percent'
Check @((Account current .1),(Account other .1)) '' 'Exhausted pool never ping-pongs'
Check @((Account current .1),(Account other 1 Disabled)) '' 'Target without access is rejected'
Check @((Account current .1),(Account other -1 Unknown)) '' 'Unknown target quota is rejected'
Check @((Account current -1 Unknown),(Account other .9)) '' 'Unknown current quota never triggers rotation'
$failed=Account current .1;$failed.Success=$false
Check @($failed,(Account other .9)) '' 'Failed active quota request defers rather than forcing rotation'
$failed=Account other .9;$failed.ModelsStatus='Unavailable'
Check @((Account current .1),$failed) '' 'Failed target catalog never reuses stale model quota'
foreach($invalid in @($null,'NaN',1.5)){
    $invalidTarget=Account other .9;$invalidTarget.ModelQuotas[0].Remaining=$invalid
    Check @((Account current .1),$invalidTarget) '' 'Invalid model fraction is rejected before ranking'
}
Check @((Account current .9 Available .19),(Account other .9 Available .8)) 'other' 'Shared weekly limit below twenty percent triggers for selected Claude'
Check @((Account current .1),(Account other .9 Available .1)) '' 'High model percentage cannot override exhausted shared quota'
Check @((Account current .1),(Account lower .6),(Account best .9)) 'best' 'Best target has the most remaining quota for the selected model'
$wrong=Account other .9;$wrong.ModelQuotas[0].Name='Claude Sonnet 5.5 (High)'
Check @((Account current .1),$wrong) '' 'A different effort variant is not substituted for the selected model'
$script:Idle=$false
Check @((Account current .1),(Account other .9)) '' 'Busy agents defer rotation without switching'
$script:Idle=$true;$script:Selected=''
Check @((Account current .1),(Account other .9)) '' 'Unrecognized or ambiguous selected model fails closed'
$script:Selected='Claude Sonnet 5.5 Medium'
$script:FixtureState=@{Status='Verified';UpdatedAt=[datetime]::UtcNow.AddSeconds(-30).ToString('o')}
Check @((Account current .1),(Account other .9)) '' 'Persistent cooldown protects manual and automatic switches'
$script:FixtureState=@{Status='Verified';UpdatedAt=[datetime]::UtcNow.AddMinutes(-3).ToString('o')}
Check @((Account current .1),(Account other .9)) 'other' 'Expired cooldown permits automatic rotation'
foreach($name in @('Gemini 3.8 Flash High','Gemini 4 Argon Medium','Gemini 4 Carbon High','Claude Opus 5.5 Medium','GPT-OSS 120B Medium')){
    $script:Selected=$name;$current=Account current .1;$target=Account other .8
    foreach($account in @($current,$target)){$account.ModelQuotas[0].Name=$name;$account.ModelQuotas[0].Family=Get-ModelQuotaFamily '' $name;$account.QuotaGroups=@()}
    Check @($current,$target) 'other' "Selected model supported: $name"
}
