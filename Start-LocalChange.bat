@echo off
title Hikvision ASMP Local Change Tool
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "LocalChangeTool.ps1"
if errorlevel 1 (
  echo.
  echo Run failed. Please make sure PowerShell is available on this computer.
  pause
)
