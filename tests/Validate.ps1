$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$files=@(Get-ChildItem -LiteralPath $repo -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')
foreach ($file in $files) {
    if (@([IO.File]::ReadAllBytes($file.FullName) | Where-Object { $_ -gt 127 }).Count) { throw "Non-ASCII script: $($file.Name)" }
    $tokens=$null; $parseErrors=$null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw "PowerShell parse error: $($file.Name): $($parseErrors.Message -join ', ')" }
}
Add-Type -AssemblyName PresentationFramework
$reader=[Xml.XmlReader]::Create((Join-Path $repo 'MainWindow.xaml'))
try { $window=[Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
foreach ($name in @('BtnRefresh','BtnAddAccount','AccountsContainer','TxtDaemonStatus')) {
    if (-not $window.FindName($name)) { throw "Missing UI control: $name" }
}
Write-Host 'PASS: ASCII, PowerShell syntax and WPF XAML load'
& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'Rotation.Tests.ps1')
if ($LASTEXITCODE) { throw 'Rotation tests failed' }
& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'Core.Tests.ps1')
if ($LASTEXITCODE) { throw 'Core tests failed' }
