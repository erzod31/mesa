@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start_mesa.ps1"
if errorlevel 1 pause
