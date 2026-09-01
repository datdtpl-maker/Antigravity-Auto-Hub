Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
strScriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
strPs1 = strScriptDir & "\AntigravityHub.ps1"
WshShell.Run "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File """ & strPs1 & """", 0, False
