param([switch]$AllowSwitch)
# Prints a portable MCP stdio configuration using this clone's absolute path.
$arguments=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'AntigravityMcp.ps1'))
if ($AllowSwitch) { $arguments+='-AllowSwitch' }
@{mcpServers=@{'antigravity-auto-hub'=@{command=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe');args=$arguments}}} | ConvertTo-Json -Depth 6
