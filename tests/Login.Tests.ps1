$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'AccountLogin.ps1')
function Assert($Value,[string]$Name) { if(-not $Value){throw $Name}; Write-Host "PASS: $Name" }
foreach($path in @('/o/oauth2/auth','/o/oauth2/v2/auth')) {
    $url='https://accounts.google.com'+$path+'?state=test&client_id=fixture'
    Assert ([AntigravityAccountLogin]::ExtractAuthUrl('ANTIGRAVITY_OPEN_URL: '+$url) -ceq $url) "Login URL supported: $path"
}
foreach($url in @('http://accounts.google.com/o/oauth2/auth?x=1','https://accounts.google.com.evil.test/o/oauth2/auth?x=1','https://accounts.google.com@evil.test/o/oauth2/auth?x=1','https://accounts.google.com:444/o/oauth2/auth?x=1','https://accounts.google.com/unknown?x=1')) {
    Assert ($null -eq [AntigravityAccountLogin]::ExtractAuthUrl($url)) 'Reject unexpected authorization destination'
}
$psi=[AntigravityAccountLogin]::CreateStartInfo('C:\fixture\language_server.exe','C:\fixture with spaces','test-csrf')
Assert ($psi.Arguments -match '--subclient_type=hub' -and $psi.Arguments -match '--override_ide_name=antigravity') 'Use interactive Hub mode'
Assert ($psi.RedirectStandardOutput -and $psi.RedirectStandardError -and $psi.RedirectStandardInput -and $psi.CreateNoWindow) 'Read both output streams and close redirected stdin'
Assert ($psi.EnvironmentVariables['ANTIGRAVITY_VSCODE_HOST'] -eq '1') 'Helper emits URL instead of opening browser twice'
Assert ([AntigravityAccountLogin]::IsVerificationUrl('https://accounts.google.com/signin/continue?fixture=1')) 'Allow official account verification continuation'
foreach($url in @('http://accounts.google.com/signin/continue','https://accounts.google.com.evil.test/signin/continue','https://evil.test/','https://accounts.google.com:444/signin/continue','https://user@accounts.google.com/signin/continue','https://accounts.google.com/unknown')) {
    Assert (-not [AntigravityAccountLogin]::IsVerificationUrl($url)) 'Reject untrusted verification destination'
}
$script:owner=42
function Get-NetTCPConnection { param($LocalPort,$State,$ErrorAction) [pscustomobject]@{OwningProcess=$script:owner;LocalAddress='127.0.0.1'} }
$session=[pscustomobject]@{Process=[pscustomobject]@{Id=42;HasExited=$false};Port=34567;Failure=$null;RequestStarted=$false;Calls=0}
$session | Add-Member ScriptMethod BeginLogin {$this.Calls++;$this.RequestStarted=$true}
Update-AccountLoginSession $session
Update-AccountLoginSession $session
Assert ($session.Calls -eq 1) 'Request Login once on helper-owned listener'
$session.RequestStarted=$false; $script:owner=99
$failed=$false; try{Update-AccountLoginSession $session}catch{$failed=$_.Exception.Message -eq 'LoginListenerMismatch'}
Assert ($failed -and $session.Calls -eq 1) 'Never send login to another process listener'
$session.Process.HasExited=$true
$failed=$false;try{Update-AccountLoginSession $session}catch{$failed=$_.Exception.Message -eq 'LoginHelperExited'}
Assert $failed 'Helper exit is an explicit failure'

# Exercise actual UI cleanup with fake controls/session and a held local mutex.
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'AntigravityHub.ps1'),[ref]$null,[ref]$null)
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Complete-AccountLogin'},$true)
Invoke-Expression $fn.Extent.Text
$script:stored='new'; $script:restoredFile=$null; $script:removed=$false; $script:attention=$false
function Get-StoredCredential {$script:stored}
function Restore-StoredCredential {param($Content) $script:stored=$Content}
function Write-AtomicText {param($Path,$Text) $script:restoredFile=$Text}
function Remove-LoginTempDirectory {param($Path) $script:removed=$true}
function Set-RotationState {param($Status) $script:attention=$Status -eq 'NeedsAttention'}
function Write-RotatorLog {param($Message)}
$accountsContainer=[pscustomobject]@{IsEnabled=$false};$btnAddAccount=[pscustomobject]@{IsEnabled=$true;Content='Cancel'};$btnSaveCurrent=[pscustomobject]@{IsEnabled=$false}
$script:loginProtection=[Threading.Mutex]::new($false,'Local\LoginTest.'+[guid]::NewGuid().ToString('N'))
$null=$script:loginProtection.WaitOne(0)
$script:loginSnapshotReady=$true;$script:loginOldCredential='old';$script:loginOldFallback='fallback'
$script:loginSession=[pscustomobject]@{Stopped=$false};$script:loginSession|Add-Member ScriptMethod Dispose {$this.Stopped=$true}
$helper=$script:loginSession
Assert (Complete-AccountLogin) 'Cancel cleanup succeeds'
Assert ($helper.Stopped -and $script:stored -eq 'old' -and $script:restoredFile -eq 'fallback' -and $script:removed -and -not $script:attention -and $null -eq $script:loginProtection) 'Cancel stops helper, restores credential and releases mutex'
Assert ($accountsContainer.IsEnabled -and $btnSaveCurrent.IsEnabled) 'Cancel re-enables account controls'
$script:loginProtection=[Threading.Mutex]::new($false,'Local\LoginTest.'+[guid]::NewGuid().ToString('N'))
$null=$script:loginProtection.WaitOne(0)
$script:loginSnapshotReady=$true;$script:loginOldCredential='original';$script:stored='changed'
function Restore-StoredCredential {param($Content) throw 'FixtureRestoreFailure'}
Assert (-not (Complete-AccountLogin)) 'Cleanup failure is not reported as success'
Assert ($script:attention -and $null -eq $script:loginProtection) 'Cleanup failure pauses rotation and releases mutex'

$response=[pscustomobject]@{Succeeded=$true;ResponseJson='{"authResult":{"hasValidAuth":true}}'}
Assert ((Get-AccountLoginResult $response).hasValidAuth) 'Read successful authentication body'
foreach($body in @('{}','{"authResult":{"hasValidAuth":false}}','not-json')) {
    $response.ResponseJson=$body; $failed=$false
    try {$null=Get-AccountLoginResult $response}catch{$failed=$true}
    Assert $failed 'HTTP success alone is not successful authentication'
}
# Reproduce the provider response seen after a successful Google browser callback.
$response.ResponseJson='{"authResult":{"ineligible":{"reason":"fixture"}}}'
$failureCode=$null
try {$null=Get-AccountLoginResult $response}catch{$failureCode=$_.Exception.Message}
Assert ($failureCode -eq 'LoginIneligible') 'Provider ineligible response retains its specific error code'
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-AccountLoginFailureMessage'},$true)
Invoke-Expression $fn.Extent.Text
$message=Get-AccountLoginFailureMessage $failureCode
Assert ($message -match 'Antigravity' -and $message -match 'ineligible' -and $message -ne (Get-AccountLoginFailureMessage 'unknown')) 'Eligibility failure has an actionable UI message distinct from generic login failure'
foreach($case in @(
    @('verificationRequired','verification_required','LoginVerificationRequired'),
    @('tosViolation','tos_violation','LoginTermsRejected'),
    @('generalError','general_error','LoginProviderError'),
    @('projectRequired','project_required','LoginProjectRequired'),
    @('headlessAuthRequired','headless_auth_required','LoginInteractiveRequired'),
    @('licenseRequired','license_required','LoginLicenseRequired')
)) {
    foreach($field in @($case[0],$case[1])) {
        $response.ResponseJson='{"authResult":{"'+$field+'":{}}}'
        $failureCode=$null
        try {$null=Get-AccountLoginResult $response}catch{$failureCode=$_.Exception.Message}
        Assert ($failureCode -eq $case[2] -and (Get-AccountLoginFailureMessage $failureCode) -ne (Get-AccountLoginFailureMessage 'unknown')) "Provider failure maps to explicit code and UI: $field"
    }
}
$response.ResponseJson='{"auth_result":{"has_valid_auth":true}}'
Assert ((Get-AccountLoginResult $response).has_valid_auth) 'Accept protobuf snake-case valid authentication'
foreach($body in @('{"authResult":{"hasValidAuth":"true"}}','{"authResult":{"hasValidAuth":true,"ineligible":{}}}')) {
    $response.ResponseJson=$body; $failed=$false
    try {$null=Get-AccountLoginResult $response}catch{$failed=$true}
    Assert $failed 'Reject malformed boolean and conflicting eligibility response before token lookup'
}
# A failure must not depend on writable diagnostics or expose the raw response.
$script:LoginDiagnosticsPath='invalid://fixture'
$response.ResponseJson='{"authResult":{"ineligible":{"reason":"fixture-private-value"},"uiMessage":"fixture-private-value"}}'
$failureCode=$null
try {$null=Get-AccountLoginResult $response}catch{$failureCode=$_.Exception.Message}
Assert ($failureCode -ceq 'LoginIneligible') 'Provider error remains a fixed code without diagnostic I/O or raw details'
Remove-Variable LoginDiagnosticsPath -Scope Script
$pendingBody='{"authResult":{"ineligible":{"verificationUrl":"https://accounts.google.com/signin/continue?fixture=1"}}}'
$authSession=[pscustomobject]@{Succeeded=$true;ResponseJson=$pendingBody;LatestResponse=$pendingBody;Reads=0}
$authSession | Add-Member ScriptMethod ReadAuthStatus {$this.Reads++; return $this.LatestResponse}
$progress=Get-AccountLoginProgress $authSession
Assert ($progress.Status -eq 'VerificationRequired' -and $authSession.Reads -eq 0) 'Login with verification stays pending instead of aborting the session'
$progress=Get-AccountLoginProgress $authSession -Recheck
Assert ($progress.Status -eq 'VerificationRequired' -and $authSession.Reads -eq 1) 'Poll helper auth status while Google verification remains pending'
$authSession.LatestResponse='{"authResult":{"hasValidAuth":true}}'
Assert ((Get-AccountLoginProgress $authSession -Recheck).Status -eq 'Ready' -and $authSession.Reads -eq 2) 'Continue to identity validation only after helper confirms valid auth'
$authSession.ResponseJson='{"auth_result":{"verification_required":{"verification_url":"https://accounts.google.com/signin/continue"}}}'
Assert ((Get-AccountLoginProgress $authSession).Status -eq 'VerificationRequired') 'Snake-case verification result keeps session alive'
foreach($body in @('{"authResult":{"ineligible":{}}}','{"authResult":{"ineligible":{"verificationUrl":"https://evil.test/"}}}','{"authResult":{"generalError":{},"verificationRequired":{"verificationUrl":"https://evil.test/"}}}')) {
    $authSession.ResponseJson=$body; $failed=$false
    try {$null=Get-AccountLoginProgress $authSession}catch{$failed=$true}
    Assert $failed 'Missing or unsafe verification link never becomes success or an open-browser action'
}
$authSession.LatestResponse='not-json';$failed=$false
try {$null=Get-AccountLoginProgress $authSession -Recheck}catch{$failed=$_.Exception.Message -eq 'LoginInvalidResponse'}
Assert $failed 'Malformed auth recheck fails closed'
function Get-RefreshToken {param($Token) $Token.token.refresh_token}
function Get-FreshToken {param($Token) $Token}
function Invoke-RestMethod {param($Uri,$Headers,$TimeoutSec,$ErrorAction)
    [pscustomobject]@{email=if($Headers.Authorization -eq 'Bearer new'){'new@example.test'}else{'old@example.test'}}
}
$old='{"token":{"access_token":"old","refresh_token":"fixture-old"}}'
$new='{"token":{"access_token":"new","refresh_token":"fixture-new"}}'
Assert ($null -eq (Get-VerifiedAccountLoginToken @($old) 'new@example.test')) 'Reject previous account after new account login'
Assert ((Get-VerifiedAccountLoginToken @($old) 'old@example.test').Email -eq 'old@example.test') 'Accept unchanged credential only when helper identity matches'
Assert ((Get-VerifiedAccountLoginToken @($old,$new) 'new@example.test').Email -eq 'new@example.test') 'Choose token matching authenticated helper identity'
$fixture=Join-Path $repo ('work\login-token-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'app') -Force | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $fixture 'app\jetski-standalone-oauth-token'),$new)
    $fallback=Join-Path $fixture 'fallback'
    [IO.File]::WriteAllText($fallback,$old)
    $script:stored=$old
    function Get-StoredCredential {$script:stored}
    $candidates=@(Get-AccountLoginTokenCandidates $fixture $fallback)
    Assert ($candidates.Count -eq 3 -and $candidates[0] -eq $new) 'Read nested helper token and shared fallback plus unchanged keyring'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if($resolved.StartsWith([IO.Path]::GetFullPath((Join-Path $repo 'work'))+'\') -and [IO.Path]::GetFileName($resolved) -match '^login-token-test-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
