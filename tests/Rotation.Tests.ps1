$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'AutoRotator.ps1')
$script:TestFailures = 0
function Assert-Equal($actual, $expected, $name) {
    if ($actual -ne $expected) { $script:TestFailures++; Write-Host "FAIL: $name (expected $expected, got $actual)" }
    else { Write-Host "PASS: $name" }
}
function Write-RotatorLog { param($msg) }
function Get-CurrentActiveName { 'current' }
function Get-RuntimeIdentity { [pscustomobject]@{ Email='current@example.test'; Idle=$true } }
function Get-AllAccountsQuota { $script:FixtureAccounts }
function Read-RotationState { $script:FixtureState }
$script:LastSwitchedTarget = ''
function Switch-ActiveAccount { param($targetAccountName, $Reason, [switch]$Notify) $script:Switches++; $script:LastSwitchedTarget=$targetAccountName; $true }
function Account([string]$name, [double]$five, [double]$week, [bool]$success=$true, [double]$argon=-1.0) {
    [pscustomobject]@{ AccountName=$name; Email="$name@example.test"; Gemini5H=$five; GeminiWeekly=$week; ArgonWeekly=$argon; Success=$success }
}
function Check($accounts, $expected, $name) {
    $script:FixtureAccounts = $accounts
    $script:Switches = 0
    $script:LastSwitchedTarget = ''
    $script:PreviousQuotas = @{}
    $script:LastSwitchTime = [datetime]::MinValue
    Invoke-AutoRotationCheck
    Assert-Equal $script:Switches $expected $name
}
Check @((Account 'current' 0 0), (Account 'other' 0 0)) 0 'Exhausted pool must not ping-pong'
Check @((Account 'current' -1 -1 $false), (Account 'other' 1 1)) 0 'Network failure must not change account'
Check @((Account 'current' .1 .9), (Account 'other' 1 1)) 1 'Low quota selects healthy account'
Check @((Account 'current' .9 .9), (Account 'other' 1 1)) 0 'Healthy active account stays'
Check @((Account 'current' .1999 .9), (Account 'other' 1 1)) 1 'Below 20 percent triggers rotation'
Check @((Account 'current' .20 .9), (Account 'other' 1 1)) 0 'Exactly 20 percent does not trigger five-hour rotation'
Check @((Account 'current' .21 .9), (Account 'other' 1 1)) 0 'Above 20 percent stays'
Check @((Account 'current' .19 .9), (Account 'other' .19 .9)) 0 'Never rotate into another account below 20 percent'
Check @((Account 'current' .8 .08), (Account 'other' 1 1)) 1 'Weekly quota trigger is preserved'
Check @((Account 'current' .95 .90 $true .08), (Account 'other' .90 .90 $true .85)) 1 'Exhausted Gemini 4 Argon weekly quota triggers rotation even when 5h/weekly Gemini are high'
Check @((Account 'current' .95 .90 $true .19), (Account 'other' .90 .90 $true .85)) 0 'Healthy Gemini 4 Argon quota above threshold stays on active account'
Check @((Account 'current' .95 .90 $true .05), (Account 'other' .95 .90 $true .04)) 0 'Never rotate into another account with exhausted Gemini 4 Argon quota'
Check @((Account 'current' .95 .90 $true .05), (Account 'noargon' 1.0 1.0 $true -1.0), (Account 'argonok' .85 .85 $true .75)) 1 'Argon rotation prefers candidate with healthy Argon quota over non-Argon candidate'
Assert-Equal $script:LastSwitchedTarget 'argonok' 'Selected target is the Argon-capable account'
$script:FixtureState=[pscustomobject]@{Status='Verified';UpdatedAt=[datetime]::UtcNow.AddMinutes(-3).ToString('o')}
Check @((Account 'current' .1 .9), (Account 'other' 1 1)) 1 'Expired cooldown parsed from disk does not add the local timezone offset'
$script:FixtureState=[pscustomobject]@{Status='Verified';UpdatedAt=[datetime]::UtcNow.AddSeconds(-30).ToString('o')}
Check @((Account 'current' .1 .9), (Account 'other' 1 1)) 0 'Recent switch still enforces cooldown'
$script:FixtureState=$null
if ($script:TestFailures) { throw "$script:TestFailures regression test(s) failed" }
