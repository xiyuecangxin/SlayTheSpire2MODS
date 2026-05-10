@echo off
title STS2 Mod Manager
mode con: cols=220 lines=42 >nul 2>nul
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1"
pause
