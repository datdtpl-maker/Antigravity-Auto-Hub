$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'AutoRotator.ps1')
$script:Failed=0
function Assert($condition, $name) {
    if (-not $condition) { $script:Failed++; Write-Host "FAIL: $name" } else { Write-Host "PASS: $name" }
}
function Summary($buckets) { [pscustomobject]@{groups=@([pscustomobject]@{displayName='Gemini';buckets=$buckets})} }
function Bucket($window,$fraction) { [pscustomobject]@{window=$window;remainingFraction=$fraction} }
foreach ($fixture in @(@{}, (Summary @()), (Summary @((Bucket '5h' 1))), (Summary @((Bucket '5h' $null),(Bucket 'week' 1))), (Summary @((Bucket '5h' 2),(Bucket 'week' 1))), (Summary @((Bucket '5h' 'NaN'),(Bucket 'week' 1))))) {
    $rejected=$false
    try { Convert-QuotaSummary $fixture | Out-Null } catch { $rejected=$true }
    Assert $rejected 'Unknown or invalid quota is rejected'
}
$quota=Convert-QuotaSummary (Summary @((Bucket '5h' 0),(Bucket 'week' .7)))
Assert ($quota.Gemini5H -eq 0 -and $quota.GeminiWeekly -eq .7 -and $quota.ArgonWeekly -eq -1) 'Zero is real exhaustion and missing Argon stays -1'
$quota=Convert-QuotaSummary (Summary @((Bucket '5h' .9),(Bucket '5h' .2),(Bucket 'week' .7)))
Assert ($quota.Gemini5H -eq .2) 'Multiple windows use lowest quota'
$argonSummary=[pscustomobject]@{groups=@(
    [pscustomobject]@{displayName='Gemini Models';buckets=@((Bucket '5h' .95),(Bucket 'weekly' .80))}
    [pscustomobject]@{displayName='Gemini 4 Argon';description='For paid Pro plans, Argon quota is separate.';buckets=@([pscustomobject]@{bucketId='gemini-argon-wtu-weekly';displayName='Gemini 4 Argon Weekly Limit';window='weekly';remainingFraction=.25})}
)}
$argonQuota=Convert-QuotaSummary $argonSummary
Assert ($argonQuota.Gemini5H -eq .95 -and $argonQuota.GeminiWeekly -eq .80 -and $argonQuota.ArgonWeekly -eq .25) 'Gemini 4 Argon weekly bucket is tracked separately from standard Gemini weekly'

# Transaction tests use isolated files and mocked native boundaries. No live credentials/processes.
$testDir=Join-Path $baseDir ('work\test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$accDir=$testDir; $geminiTokenPath=Join-Path $testDir 'fallback.txt'; $activeFile=Join-Path $testDir 'active.txt'; $stateFile=Join-Path $testDir 'state.json'
Write-AtomicText (Join-Path $testDir 'target.json') '{"token":{"refresh_token":"fixture"}}'
function Write-RotatorLog { param($msg) }
function Send-ToastNotification { param($Message) }
$script:TargetArgonWeekly=1.0
function Get-AccountQuotaInfo { param($tokenFilePath) [pscustomobject]@{Success=$true;Email='target@example.test';Gemini5H=1.0;GeminiWeekly=1.0;ArgonWeekly=$script:TargetArgonWeekly} }
function Get-FreshToken { param($Token) [pscustomobject]@{token=@{access_token='fixture-only';refresh_token='fixture-only'}} }
function Get-RuntimeIdentity { $script:FixtureRuntime }
function Get-RuntimeWindows { param($Runtime) @([pscustomobject]@{Safe=$script:SafeWindow}) }
function Restore-RuntimeWindows { param($SavedWindows) $script:RestoredWindows++ }
function Get-StoredCredential { '{"token":{"refresh_token":"fixture"}}' }
function Invoke-RestMethod { param($Uri) [pscustomobject]@{email=$script:StoredEmail} }
function Get-CredentialEmail { param($Content) if ($script:EmailBranch) { if ($Content -match 'different-token') { 'old@example.test' } else { 'target@example.test' } } else { $script:StoredEmail } }
function Set-StoredCredential { param($Content) $script:Writes++; if($script:FailWrite){throw 'fixture write failure'} }
function Restore-StoredCredential { param($Content) $script:Rollbacks++ }
function Restart-AntigravityRuntime { param($Runtime) $script:Restarts++ }
function Wait-AntigravityIdentity { param($Email) $script:Verified }
function Reset-Fixture {
    $script:FixtureRuntime=[pscustomobject]@{Email='old@example.test';Idle=$true;Runtimes=@([pscustomobject]@{ProcessId=0})}
    $script:Writes=0; $script:Rollbacks=0; $script:Restarts=0; $script:RestoredWindows=0
    $script:Verified=$true; $script:FailWrite=$false; $script:SafeWindow=$true
    $script:StoredEmail='old@example.test'; $script:TargetArgonWeekly=1.0
    if (Test-Path -LiteralPath $stateFile) { Remove-Item -LiteralPath $stateFile }
    Write-AtomicText $geminiTokenPath 'old-fallback'
    Write-AtomicText $activeFile 'old-account'
}
Reset-Fixture
$script:TargetArgonWeekly=.05
Assert (-not (Switch-ActiveAccount 'target') -and $script:Writes -eq 0) 'Exhausted Gemini 4 Argon target quota is rejected before switching'
Assert ($script:LastSwitchMessage -eq (Get-SwitchFailureMessage 'Target quota unavailable or exhausted.')) 'Exhausted Argon target reports quota unavailable or exhausted'
Reset-Fixture
$script:FixtureRuntime.Idle=$false
Assert (-not (Switch-ActiveAccount 'target') -and $script:Writes -eq 0 -and $script:Restarts -eq 0) 'Running agent defers without writes'
Assert ($script:LastSwitchMessage -eq (Get-SwitchFailureMessage 'SwitchAgentRunning')) 'Running agent reports the specific deferral reason'
Reset-Fixture
$script:SafeWindow=$false
Assert (-not (Switch-ActiveAccount 'target') -and $script:Writes -eq 0) 'Unsaved draft defers without writes'
Assert ($script:LastSwitchMessage -eq (Get-SwitchFailureMessage 'Unsaved draft or focused editor; rotation deferred.')) 'Draft protection reports an actionable reason'
Reset-Fixture
Assert (Switch-ActiveAccount 'target') 'Verified transaction succeeds'
Assert ((Read-RotationState).Status -eq 'Verified' -and $script:Restarts -eq 1 -and $script:RestoredWindows -eq 1) 'Runtime restarted, navigation restored, identity verified'
Assert ((Get-Content $activeFile -Raw) -eq 'target') 'Active marker written only after verification'
Assert (-not (Switch-ActiveAccount 'target') -and $script:Writes -eq 1) 'Persistent cooldown blocks second switch'
Assert ($script:LastSwitchMessage -eq (Get-SwitchFailureMessage 'SwitchCooldown')) 'Cooldown explains why a repeated switch is deferred'
Assert ((Get-SwitchFailureMessage 'secret-fixture-provider-url') -notmatch 'secret-fixture-provider-url') 'Unknown switch exceptions never leak raw details'
Set-RotationState 'Verified' 'old-account' 'old@example.test'
$expired=Read-RotationState
$expired.UpdatedAt=[datetime]::UtcNow.AddMinutes(-3).ToString('o')
Write-AtomicText $stateFile ($expired | ConvertTo-Json -Compress)
Assert (Switch-ActiveAccount 'target') 'Manual switch accepts cooldown older than 120 real seconds'
Reset-Fixture
$script:Verified=$false
Assert (-not (Switch-ActiveAccount 'target')) 'Wrong runtime identity rejects success'
Assert ($script:Rollbacks -eq 1 -and (Read-RotationState).Status -eq 'NeedsAttention') 'Unverified switch rolls back and pauses'
Assert ((Get-Content $activeFile -Raw) -eq 'old-account') 'Failed switch preserves active marker'
Reset-Fixture
$script:FailWrite=$true
Assert (-not (Switch-ActiveAccount 'target') -and $script:Rollbacks -eq 1 -and $script:Restarts -eq 0) 'Credential write failure rolls back without restart'
Reset-Fixture
$script:FixtureRuntime=$null
Assert (Switch-ActiveAccount 'target') 'Closed IDE prepares account'
Assert ((Read-RotationState).Status -eq 'Prepared' -and $script:Restarts -eq 0 -and (Get-Content $activeFile -Raw) -eq 'old-account') 'Prepared account is not reported as active'
Reset-Fixture
Assert (-not (Switch-ActiveAccount '../outside') -and $script:Writes -eq 0) 'Account path traversal rejected'
Reset-Fixture
$script:StoredEmail='different@example.test'
Assert (-not (Switch-ActiveAccount 'target') -and $script:Writes -eq 0) 'Rollback credential must match runtime identity'
Reset-Fixture
Set-RotationState 'NeedsAttention' '' 'old@example.test'
$expired=Read-RotationState
$expired.UpdatedAt=[datetime]::UtcNow.AddMinutes(-3).ToString('o')
Write-AtomicText $stateFile ($expired | ConvertTo-Json -Compress)
Write-AtomicText (Join-Path $testDir 'target.json') '{"token":{"refresh_token":"target-token"}}'
Write-AtomicText (Join-Path $testDir 'old-account.json') '{"token":{"refresh_token":"different-token"}}'
$script:EmailBranch = $true
Assert (Repair-RotationState) 'Repair reconciles matching runtime and stored email even when refresh token string differs'
Assert ((Read-RotationState).Status -eq 'Verified' -and (Read-RotationState).Account -eq 'old-account') 'Reconciled state is Verified with matching account name'
$script:EmailBranch = $false
Reset-Fixture
Set-RotationState 'NeedsAttention' '' 'old@example.test'
$expired=Read-RotationState
$expired.UpdatedAt=[datetime]::UtcNow.AddMinutes(-3).ToString('o')
Write-AtomicText $stateFile ($expired | ConvertTo-Json -Compress)
Write-AtomicText (Join-Path $testDir 'target.json') '{"token":{"refresh_token":"fixture"}}'
Assert (Switch-ActiveAccount 'target') 'Manual switch automatically reconciles previous NeedsAttention state when identities match'
Reset-Fixture
Set-RotationState 'NeedsAttention' '' 'old@example.test'
$expired=Read-RotationState
$expired.UpdatedAt=[datetime]::UtcNow.AddMinutes(-3).ToString('o')
Write-AtomicText $stateFile ($expired | ConvertTo-Json -Compress)
$script:StoredEmail='mismatch@example.test'
Assert (-not (Switch-ActiveAccount 'target')) 'Manual switch blocks when NeedsAttention cannot be reconciled'
Assert ($script:LastSwitchMessage -eq (Get-SwitchFailureMessage 'Previous switch requires reconciliation.')) 'Failure message indicates previous switch requires reconciliation'
if ($script:Failed) { throw "$script:Failed test(s) failed" }
