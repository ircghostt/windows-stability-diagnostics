<#
.SYNOPSIS
    Configures Windows to generate Small Memory Dumps (Minidumps) on Blue Screen crashes.
.DESCRIPTION
    Sets CrashDumpEnabled = 3 (Small memory dump, 256KB) in HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl.
    Ensures future BSODs write lightweight .dmp files to C:\Windows\Minidump which can be parsed instantly
    by Parse-Minidump.ps1 to pinpoint the exact offending driver.
#>

[CmdletBinding()]
param()

$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"

try {
    # 3 = Small memory dump (256 KB Minidump)
    Set-ItemProperty -Path $registryPath -Name "CrashDumpEnabled" -Value 3 -ErrorAction Stop
    Set-ItemProperty -Path $registryPath -Name "MinidumpDir" -Value "C:\Windows\Minidump" -ErrorAction Stop
    Set-ItemProperty -Path $registryPath -Name "AutoReboot" -Value 1 -ErrorAction Stop

    Write-Host "[OK] Successfully configured Windows Crash Control:" -ForegroundColor Green
    Write-Host "    CrashDumpEnabled : 3 (Small Memory Dump / Minidump)"
    Write-Host "    Minidump Folder  : C:\Windows\Minidump"
    Write-Host "    Auto Reboot      : 1 (Enabled)"
} catch {
    Write-Error "Failed to update CrashControl settings. Ensure this script is run as Administrator: $_"
}
