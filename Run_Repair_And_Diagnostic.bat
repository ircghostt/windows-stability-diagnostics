@echo off
title Full Windows Diagnostics and Auto-Repair (Admin)
:: Self-elevates to Administrator and executes diagnose_system.ps1 with full 3-stage repair
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%~dp0src\scripts\diagnose_system.ps1\"\"' -Verb RunAs"
