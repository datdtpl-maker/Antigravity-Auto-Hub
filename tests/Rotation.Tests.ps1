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
function Read-RotationState { $null }
function Switch-ActiveAccount { param($targetAccountName, $Reason, [switch]$Notify) $script:Switches++; $true }
function Account([string]$name, [double]$five, [double]$week, [bool]$success=$true) {
    [pscustomobject]@{ AccountName=$name; Email="$name@example.test"; Gemini5H=$five; GeminiWeekly=$week; Success=$success }
}
function Check($accounts, $expected, $name) {
    $script:FixtureAccounts = $accounts
    $script:Switches = 0
    $script:PreviousQuotas = @{}
    $script:LastSwitchTime = [datetime]::MinValue
    Invoke-AutoRotationCheck
    Assert-Equal $script:Switches $expected $name
}
Check @((Account 'current' 0 0), (Account 'other' 0 0)) 0 'Exhausted pool must not ping-pong'
Check @((Account 'current' -1 -1 $false), (Account 'other' 1 1)) 0 'Network failure must not change account'
Check @((Account 'current' .1 .9), (Account 'other' 1 1)) 1 'Low quota selects healthy account'
Check @((Account 'current' .9 .9), (Account 'other' 1 1)) 0 'Healthy active account stays'
if ($script:TestFailures) { throw "$script:TestFailures regression test(s) failed" }
