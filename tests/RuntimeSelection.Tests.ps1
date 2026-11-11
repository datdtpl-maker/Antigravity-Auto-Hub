$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'AutoRotator.ps1')
function Assert($Value,$Name){if(-not $Value){throw $Name};Write-Host "PASS: $Name"}
function Test-Path {param($LiteralPath) $true}
function Get-Content {param($LiteralPath,$First) '9222'}
function Get-NetTCPConnection {param($LocalPort,$State,$ErrorAction) [pscustomobject]@{OwningProcess=$script:Owner;LocalAddress='127.0.0.1'}}
function Invoke-RestMethod {param($Uri,$TimeoutSec,$ErrorAction) $script:Pages}
$script:Owner=123
$runtime=[pscustomobject]@{ParentProcessId=123;Port=5000}
$real=[pscustomobject]@{id='fixture';type='page';url='https://127.0.0.1:5000/';webSocketDebuggerUrl='ws://127.0.0.1:9222/devtools/page/fixture'}
$script:Pages=@($real,[pscustomobject]@{type='page';url='data:text/html,fixture'},[pscustomobject]@{type='page';url='about:blank'})
Assert (@(Get-RuntimePages $runtime).Count -eq 1) 'Authenticated IDE pages remain scoped while unrelated data preview pages are excluded'
$script:Pages=@($real,[pscustomobject]@{type='page';url='https://example.test/'})
$failed=$false;try{Get-RuntimePages $runtime|Out-Null}catch{$failed=$true}
Assert $failed 'Unexpected network page fails closed rather than inspecting its content'
$script:Pages=@($real);$script:Owner=999
$failed=$false;try{Get-RuntimePages $runtime|Out-Null}catch{$failed=$true}
Assert $failed 'Debugger must belong to the verified Antigravity process'
