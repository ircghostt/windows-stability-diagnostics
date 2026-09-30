@echo off
title Fast System Stability Diagnostics (Read-Only)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\scripts\diagnose_system.ps1" -DiagnoseOnly
