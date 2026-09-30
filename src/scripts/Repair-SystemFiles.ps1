#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Automated Windows Component Store (DISM) and System File Checker (SFC) repair script.
.DESCRIPTION
    Executes DISM /Online /Cleanup-Image /RestoreHealth followed by sfc /scannow.
    Logs execution results and reports exit codes to repair corruptions resulting from BSOD crashes.
#>

[CmdletBinding()]
param(
    [string]$LogFile = "$PSScriptRoot\repair_log.txt"
)

$ErrorActionPreference = "Continue"

# Check Administrator Elevation
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "[ERROR] This script requires administrative privileges. Please right-click PowerShell and select 'Run as Administrator'."
    exit 1
}

function Log-Output([string]$message, [string]$color = "White") {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $message"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

# Initialize Log
if (Test-Path $LogFile) {
    Remove-Item $LogFile -Force -ErrorAction SilentlyContinue
}

Log-Output "================================================================================" "Cyan"
Log-Output " WINDOWS SYSTEM FILE & COMPONENT STORE REPAIR UTILITY" "Cyan"
Log-Output " Target Log: $LogFile" "Cyan"
Log-Output "================================================================================" "Cyan"

# -----------------------------------------------------------------------------
# STEP 1: DISM COMPONENT STORE REPAIR
# -----------------------------------------------------------------------------
Log-Output "`n[STAGE 1/2] Executing: dism.exe /online /cleanup-image /restorehealth" "Yellow"
Log-Output "Contacting Windows Update servers to repair damaged WinSxS packages..." "Gray"

$dismStartTime = Get-Date
$dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /restorehealth" -Wait -PassThru -NoNewWindow
$dismDuration = [math]::Round(((Get-Date) - $dismStartTime).TotalSeconds, 1)

if ($dismProcess.ExitCode -eq 0) {
    Log-Output "[OK] DISM operation completed successfully (Duration: ${dismDuration}s)." "Green"
} else {
    Log-Output "[WARNING] DISM exited with code $($dismProcess.ExitCode) (Duration: ${dismDuration}s)." "Red"
}

# -----------------------------------------------------------------------------
# STEP 2: SYSTEM FILE CHECKER (SFC)
# -----------------------------------------------------------------------------
Log-Output "`n[STAGE 2/2] Executing: sfc.exe /scannow" "Yellow"
Log-Output "Verifying active system binaries against golden copies in WinSxS..." "Gray"

$sfcStartTime = Get-Date
$sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
$sfcDuration = [math]::Round(((Get-Date) - $sfcStartTime).TotalSeconds, 1)

if ($sfcProcess.ExitCode -eq 0) {
    Log-Output "[OK] SFC completed successfully with no integrity violations (Duration: ${sfcDuration}s)." "Green"
} elseif ($sfcProcess.ExitCode -eq 1) {
    Log-Output "[INFO] SFC completed: Found corrupt files and repaired them successfully (Duration: ${sfcDuration}s)." "Green"
} else {
    Log-Output "[NOTICE] SFC finished with return code $($sfcProcess.ExitCode) (Duration: ${sfcDuration}s)." "Yellow"
}

# -----------------------------------------------------------------------------
# STEP 3: DISM COMPONENT STORE CLEANUP
# -----------------------------------------------------------------------------
Log-Output "`n[STAGE 3/3] Executing: dism.exe /online /cleanup-image /startcomponentcleanup" "Yellow"
Log-Output "Pruning superseded component versions and reclaiming disk space in WinSxS..." "Gray"

$cleanupStartTime = Get-Date
$cleanupProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /startcomponentcleanup" -Wait -PassThru -NoNewWindow
$cleanupDuration = [math]::Round(((Get-Date) - $cleanupStartTime).TotalSeconds, 1)

if ($cleanupProcess.ExitCode -eq 0) {
    Log-Output "[OK] Component Store Cleanup completed successfully (Duration: ${cleanupDuration}s)." "Green"
} else {
    Log-Output "[WARNING] Component Store Cleanup exited with code $($cleanupProcess.ExitCode) (Duration: ${cleanupDuration}s)." "Yellow"
}

# -----------------------------------------------------------------------------
# SUMMARY & VERIFICATION
# -----------------------------------------------------------------------------
Log-Output "`n================================================================================" "Cyan"
Log-Output " REPAIR OPERATION SUMMARY" "Cyan"
Log-Output "================================================================================" "Cyan"
Log-Output "DISM RestoreHealth Exit Code : $($dismProcess.ExitCode)"
Log-Output "SFC ScanNow Exit Code        : $($sfcProcess.ExitCode)"
Log-Output "DISM Cleanup Exit Code       : $($cleanupProcess.ExitCode)"
Log-Output "Detailed CBS Log: C:\Windows\Logs\CBS\CBS.log"
Log-Output "Repair Log Path : $LogFile"
Log-Output "Status         : Component store and active OS binaries verification complete." "Green"
Log-Output "================================================================================" "Cyan"
