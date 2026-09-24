$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'AutoRotator.ps1')
foreach ($version in @('2.12.2','2.12.2.0','2.13.0','2.13.0.0','2.14.0','2.14.0.0','2.15.1','2.15.1.0','2.16.0','2.16.0.0','2.99.0')) {
    Assert-AntigravityVersion $version
    Write-Host "PASS: Supported version $version"
}
foreach ($version in @('2.12.20.1','2.16.0.1','3.0.0','1.99.0','invalid')) {
    $failure=$null
    try { Assert-AntigravityVersion $version } catch { $failure=$_ }
    if (-not $failure -or $failure.Exception.Data['HubReason'] -ne 'UnsupportedVersion') { throw "Unexpected version allowed: $version" }
    $message=Get-RuntimeFailureMessage $failure
    if ($version -ne 'invalid' -and -not $message.Contains($version)) { throw 'UI error hides unsupported version' }
    Write-Host "PASS: Unsupported version rejected and explained: $version"
}
$installedPath = Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\Antigravity.exe'
if (Test-Path -LiteralPath $installedPath) {
    $installedVersion = (Get-Item -LiteralPath $installedPath).VersionInfo.ProductVersion
    Assert-AntigravityVersion $installedVersion $installedPath
    Write-Host "PASS: Installed runtime capabilities accepted: $installedVersion"
}
