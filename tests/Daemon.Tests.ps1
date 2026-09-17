$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'AntigravityHub.ps1'),[ref]$null,[ref]$null)
$functionAst=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DaemonStatus'},$true)
if (-not $functionAst) { throw 'Missing daemon status function' }
Invoke-Expression $functionAst.Extent.Text

# A single CIM instance has no Count in Windows PowerShell 5.1.
$script:processes=@()
function Get-CimInstance { param($ClassName,$Filter,$ErrorAction) $script:processes }
foreach ($count in @(0,1,2)) {
    $script:processes=@(for ($i=0; $i -lt $count; $i++) {
        New-CimInstance -ClassName Win32_Process -ClientOnly -Property @{ProcessId=[uint32](100+$i)}
    })
    $actual=Get-DaemonStatus
    if ($actual -ne ($count -gt 0)) { throw "Incorrect daemon status for $count process(es): $actual" }
    Write-Host "PASS: Daemon status for $count process(es)"
}
