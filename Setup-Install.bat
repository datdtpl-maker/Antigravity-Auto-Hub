@echo off
chcp 65001 >nul
title Setup Antigravity Auto-Hub
echo ==============================================================================
echo   CAI DAT ANTIGRAVITY AUTO-ROTATION HUB (WINDOWS)
echo ==============================================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
echo.
pause
