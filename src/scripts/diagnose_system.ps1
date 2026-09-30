#Requires -Version 5.1
<#
.SYNOPSIS
    Unified Windows Hardware Diagnostics, BSOD Telemetry, and OS Repair Utility.
.DESCRIPTION
    1. Collects complete hardware, IMC, RAM topology, BugCheck, application crash,
       and binary crash dump telemetry for LLM analysis.
    2. Optional (-Repair): Executes 3-stage repair pipeline (DISM RestoreHealth ->
       SFC ScanNow -> DISM StartComponentCleanup), performs deep regex parsing of
       CBS.log and DISM.log, and appends a categorized audit of repaired vs. unrepaired
       files directly into report.txt.
.PARAMETER Repair
    When specified, elevates/executes the full OS repair and component store cleanup
    and parses the repair logs.
.PARAMETER OutputFile
    Path to destination report file. Defaults to report.txt in script directory.
#>

[CmdletBinding()]
param(
    [switch]$DiagnoseOnly,
    [string]$OutputFile = "$PSScriptRoot\report.txt",
    [switch]$NoPause
)

# Default Behavior: Full 3-stage repair runs automatically unless -DiagnoseOnly is explicitly passed
$Repair = -not $DiagnoseOnly

# Auto-Elevation: If Repair is active and session is not elevated, relaunch as Administrator
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Repair -and -not $isAdmin) {
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        Write-Host "[*] Full Auto-Repair enabled by default. Prompting for Administrator elevation..." -ForegroundColor Yellow
        try {
            $scriptArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            if ($OutputFile) { $scriptArgs += " -OutputFile `"$OutputFile`"" }
            Start-Process powershell.exe -ArgumentList $scriptArgs -Verb RunAs
            exit 0
        } catch {
            Write-Warning "Elevation cancelled by user. Proceeding in Telemetry-Only mode."
            $Repair = $false
        }
    } else {
        Write-Warning "Non-interactive session without Administrator privileges. Proceeding in Telemetry-Only mode."
        $Repair = $false
    }
}

$ErrorActionPreference = "SilentlyContinue"
$report = [System.Text.StringBuilder]::new()

function Write-SectionHeader([string]$title) {
    [void]$report.AppendLine("================================================================================")
    [void]$report.AppendLine(" $title")
    [void]$report.AppendLine("================================================================================")
}

function Write-SubHeader([string]$title) {
    [void]$report.AppendLine("--- $title ---")
}

# =============================================================================
# HELPER: DEEP CBS / DISM / SFC LOG PARSER
# =============================================================================
function Parse-CbsLog([datetime]$StartTime) {
    $cbsLogPath = "C:\Windows\Logs\CBS\CBS.log"
    $dismLogPath = "C:\Windows\Logs\DISM\dism.log"

    $results = [PSCustomObject]@{
        SfcRepairedFiles   = [System.Collections.Generic.List[string]]::new()
        SfcFailedFiles     = [System.Collections.Generic.List[string]]::new()
        DismFixedPayloads  = [System.Collections.Generic.List[string]]::new()
        DismFailedPayloads = [System.Collections.Generic.List[string]]::new()
        DismErrorCodes     = [System.Collections.Generic.List[string]]::new()
        CheckSurSummary    = [System.Collections.Generic.List[string]]::new()
        TotalCorruptions   = 0
        TotalRepaired      = 0
    }

    if (-not (Test-Path $cbsLogPath)) {
        return $results
    }

    # Stream read lines from CBS.log to avoid memory bloat
    $reader = [System.IO.StreamReader]::new($cbsLogPath)
    $inCheckSur = $false

    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            # Basic timestamp filter (CBS format: 2026-09-30 18:55:25)
            if ($line.Length -ge 19) {
                $timeStr = $line.Substring(0, 19)
                $lineTime = [datetime]::MinValue
                if ([datetime]::TryParseExact($timeStr, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$lineTime)) {
                    if ($lineTime -lt $StartTime.AddSeconds(-30)) {
                        continue
                    }
                }
            }

            # 1. SFC Repaired Files
            if ($line -match '\[SR\] Repairing (?:corrupted )?file (?:\\\\\?\\)?(?<file>[^\r\n]+?)(?: from store)?$') {
                $f = $Matches['file'].Trim()
                if (-not $results.SfcRepairedFiles.Contains($f)) {
                    $results.SfcRepairedFiles.Add($f)
                }
            }

            # 2. SFC Failed / Unrepairable Files
            if ($line -match '\[SR\] (?:Could not reproject corrupted file|Cannot repair member file) (?:\\\\\?\\)?(?<file>[^\r\n]+)') {
                $f = $Matches['file'].Trim()
                if (-not $results.SfcFailedFiles.Contains($f)) {
                    $results.SfcFailedFiles.Add($f)
                }
            }

            # 3. DISM Fixed Components
            if ($line -match '\(p\)\s+CSI Payload Corrupt\s+\(w\)\s+\(Fixed\)\s+(?<comp>[^\r\n]+)') {
                $c = $Matches['comp'].Trim()
                if (-not $results.DismFixedPayloads.Contains($c)) {
                    $results.DismFixedPayloads.Add($c)
                }
            }

            # 4. DISM Unfixed / Missing Source Components
            if ($line -match '\(p\)\s+CSI Payload Corrupt\s+\(n\)\s+(?<comp>[^\r\n]+)') {
                $c = $Matches['comp'].Trim()
                if (-not $results.DismFailedPayloads.Contains($c)) {
                    $results.DismFailedPayloads.Add($c)
                }
            }

            # 5. DISM Specific Error Codes
            if ($line -match 'HRESULT = (?<hex>0x[0-9a-fA-F]+)\s*-\s*(?<code>[A-Z0-9_]+)') {
                $err = "$($Matches['hex']) ($($Matches['code']))"
                if (-not $results.DismErrorCodes.Contains($err)) {
                    $results.DismErrorCodes.Add($err)
                }
            }

            # 6. CheckSur Summary Section
            if ($line -match 'Checking System Update Readiness\.') {
                $inCheckSur = $true
            }
            if ($inCheckSur) {
                if ($line -match 'Total Detected Corruption:\s+(?<count>\d+)') {
                    $results.TotalCorruptions = [int]$Matches['count']
                }
                if ($line -match 'Total Repaired Corruption:\s+(?<count>\d+)') {
                    $results.TotalRepaired = [int]$Matches['count']
                }
                if ($line -match '(?:Total|CSI|CBS)\s+(?:Detected|Repaired|Manifest|Payload|Metadata)[^:]*:\s+\d+') {
                    $cleanSummary = $line.Trim()
                    if (-not $results.CheckSurSummary.Contains($cleanSummary)) {
                        $results.CheckSurSummary.Add($cleanSummary)
                    }
                }
                if ($line -match 'Total Operation Time:') {
                    $inCheckSur = $false
                }
            }
        }
    } finally {
        $reader.Close()
    }

    return $results
}

# =============================================================================
# PHASE 1: TELEMETRY EXTRACTION
# =============================================================================
Write-SectionHeader "1. TELEMETRY EXTRACTION CONTEXT"
[void]$report.AppendLine("Extraction Timestamp : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
[void]$report.AppendLine("Target Machine       : $env:COMPUTERNAME")
[void]$report.AppendLine("Script Mode          : $(if ($Repair) { 'Consolidated Diagnostic & OS Repair' } else { 'Telemetry Audit Only' })")
[void]$report.AppendLine("Script Version       : 3.0.0 (Unified Forensics & Deep Log Parser)")
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 2. OPERATING SYSTEM & ENVIRONMENT
# -----------------------------------------------------------------------------
Write-SectionHeader "2. OPERATING SYSTEM & ENVIRONMENT"
$os = Get-CimInstance Win32_OperatingSystem
if ($os) {
    [void]$report.AppendLine("OS Caption      : $($os.Caption)")
    [void]$report.AppendLine("OS Version      : $($os.Version)")
    [void]$report.AppendLine("OS Build Number : $($os.BuildNumber)")
    [void]$report.AppendLine("Architecture    : $($os.OSArchitecture)")
    [void]$report.AppendLine("Install Date    : $($os.InstallDate)")
    [void]$report.AppendLine("Last Boot Time  : $($os.LastBootUpTime)")
    $uptime = (Get-Date) - $os.LastBootUpTime
    [void]$report.AppendLine("System Uptime   : $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m $($uptime.Seconds)s")
}
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 3. MOTHERBOARD & FIRMWARE (BIOS)
# -----------------------------------------------------------------------------
Write-SectionHeader "3. MOTHERBOARD & FIRMWARE (BIOS)"
$board = Get-CimInstance Win32_BaseBoard
$bios = Get-CimInstance Win32_BIOS
if ($board) {
    [void]$report.AppendLine("Motherboard Vendor : $($board.Manufacturer)")
    [void]$report.AppendLine("Motherboard Model  : $($board.Product)")
    [void]$report.AppendLine("Motherboard Version: $($board.Version)")
}
if ($bios) {
    [void]$report.AppendLine("BIOS Vendor        : $($bios.Manufacturer)")
    [void]$report.AppendLine("BIOS Version       : $($bios.SMBIOSBIOSVersion)")
    [void]$report.AppendLine("BIOS Release Date  : $($bios.ReleaseDate)")
}
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 4. PROCESSOR & MEMORY CONTROLLER (IMC)
# -----------------------------------------------------------------------------
Write-SectionHeader "4. PROCESSOR SPECIFICATIONS (IMC CONTEXT)"
$cpuList = Get-CimInstance Win32_Processor
foreach ($cpu in $cpuList) {
    [void]$report.AppendLine("CPU Name          : $($cpu.Name.Trim())")
    [void]$report.AppendLine("Physical Cores    : $($cpu.NumberOfCores)")
    [void]$report.AppendLine("Logical Threads   : $($cpu.NumberOfLogicalProcessors)")
    [void]$report.AppendLine("Max Clock Speed   : $($cpu.MaxClockSpeed) MHz")
    [void]$report.AppendLine("Socket            : $($cpu.SocketDesignation)")
}
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 5. PHYSICAL MEMORY (RAM) TOPOLOGY & POPULATION
# -----------------------------------------------------------------------------
Write-SectionHeader "5. PHYSICAL MEMORY (RAM) MODULE TOPOLOGY"
$dimms = Get-CimInstance Win32_PhysicalMemory
$memArray = Get-CimInstance Win32_PhysicalMemoryArray
$totalInstalledBytes = 0

if ($memArray) {
    [void]$report.AppendLine("Total Memory Slots on Board: $($memArray.MemoryDevices)")
}
[void]$report.AppendLine("Populated DIMM Count       : $($dimms.Count)")

Write-SubHeader "Installed DIMM Inventory"
foreach ($dimm in $dimms) {
    $totalInstalledBytes += [uint64]$dimm.Capacity
    $capGB = [math]::Round([uint64]$dimm.Capacity / 1GB, 2)
    [void]$report.AppendLine("Slot/Locator    : $($dimm.DeviceLocator) ($($dimm.BankLabel))")
    [void]$report.AppendLine("  Manufacturer  : $($dimm.Manufacturer)")
    [void]$report.AppendLine("  Part Number   : $($dimm.PartNumber.Trim())")
    [void]$report.AppendLine("  Capacity      : $capGB GB ($($dimm.Capacity) bytes)")
    [void]$report.AppendLine("  Rated Speed   : $($dimm.Speed) MHz")
    [void]$report.AppendLine("  Config Speed  : $($dimm.ConfiguredClockSpeed) MHz")
    [void]$report.AppendLine("  Serial Number : $($dimm.SerialNumber)")
    [void]$report.AppendLine()
}
$totalGB = [math]::Round($totalInstalledBytes / 1GB, 2)
[void]$report.AppendLine("Total Physical RAM Installed: $totalGB GB")
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 6. KERNEL CRASH TELEMETRY & BINARY DUMP ANALYSIS
# -----------------------------------------------------------------------------
Write-SectionHeader "6. KERNEL CRASH TELEMETRY (BUGCHECKS & REBOOTS)"

$knownBugChecks = @{
    0x0A = "IRQL_NOT_LESS_OR_EQUAL"
    0x1A = "MEMORY_MANAGEMENT"
    0x1E = "KMODE_EXCEPTION_NOT_HANDLED"
    0x24 = "NTFS_FILE_SYSTEM"
    0x3B = "SYSTEM_SERVICE_EXCEPTION"
    0x4E = "PFN_LIST_CORRUPT"
    0x50 = "PAGE_FAULT_IN_NONPAGED_AREA"
    0x7E = "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED"
    0x9F = "DRIVER_POWER_STATE_FAILURE"
    0xBE = "ATTEMPTED_WRITE_TO_READONLY_MEMORY"
    0xD1 = "DRIVER_IRQL_NOT_LESS_OR_EQUAL"
    0x109 = "CRITICAL_STRUCTURE_CORRUPTION"
    0x116 = "VIDEO_TDR_FAILURE"
    0x124 = "WHEA_UNCORRECTABLE_ERROR"
    0x133 = "DPC_WATCHDOG_VIOLATION"
    0x139 = "KERNEL_SECURITY_CHECK_FAILURE"
}

Write-SubHeader "Kernel-Power Event ID 41 (Last 10 Events)"
$kpEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41} -MaxEvents 10 -ErrorAction SilentlyContinue

if ($kpEvents) {
    foreach ($evt in $kpEvents) {
        $props = $evt.Properties
        if ($props -and $props.Count -ge 5) {
            $rawCode = [uint64]$props[0].Value
            $p1 = [uint64]$props[1].Value
            $p2 = [uint64]$props[2].Value
            $p3 = [uint64]$props[3].Value
            $p4 = [uint64]$props[4].Value
            
            $hexCode = '0x{0:X}' -f $rawCode
            $intCode = [int32]($rawCode -band 0xFFFFFFFF)
            $codeName = if ($knownBugChecks.ContainsKey($intCode)) { 
                $knownBugChecks[$intCode] 
            } elseif ($rawCode -eq 0) { 
                "HARD_RESET / SUDDEN_POWER_LOSS" 
            } else { 
                "UNKNOWN_BUGCHECK" 
            }

            [void]$report.AppendLine("Timestamp    : $($evt.TimeCreated)")
            [void]$report.AppendLine("BugCheckCode : $hexCode ($codeName, Decimal: $rawCode)")
            [void]$report.AppendLine("Parameter 1  : 0x{0:X}" -f $p1)
            [void]$report.AppendLine("Parameter 2  : 0x{0:X}" -f $p2)
            [void]$report.AppendLine("Parameter 3  : 0x{0:X}" -f $p3)
            [void]$report.AppendLine("Parameter 4  : 0x{0:X}" -f $p4)
            [void]$report.AppendLine()
        }
    }
}

Write-SubHeader "Binary Crash Dump Inspection"
$parserScript = Join-Path $PSScriptRoot "Parse-Minidump.ps1"
if (Test-Path $parserScript) {
    $parsedDump = & $parserScript
    if ($parsedDump) {
        [void]$report.AppendLine("Dump Format      : $($parsedDump.DumpType)")
        [void]$report.AppendLine("Parsed Dump File : $($parsedDump.FilePath)")
        [void]$report.AppendLine("BugCheck Code    : $($parsedDump.BugCheckCode) ($($parsedDump.BugCheckName))")
        if ($parsedDump.FaultingDriver) {
            [void]$report.AppendLine("Faulting Driver  : $($parsedDump.FaultingDriver)")
            [void]$report.AppendLine("Driver Location  : $($parsedDump.DriverPath)")
            [void]$report.AppendLine("Driver Version   : $($parsedDump.DriverVersion)")
            [void]$report.AppendLine("Instruction (RIP): $($parsedDump.ExceptionAddress)")
            [void]$report.AppendLine("Driver Memory    : $($parsedDump.DriverBase) - $($parsedDump.DriverEnd)")
        } else {
            [void]$report.AppendLine("Parameter 1 (VA) : $($parsedDump.Parameter1)")
            [void]$report.AppendLine("Parameter 2 (PTE): $($parsedDump.Parameter2)")
            [void]$report.AppendLine("Parameter 3 (TRP): $($parsedDump.Parameter3)")
            [void]$report.AppendLine("Parameter 4 (SUB): $($parsedDump.Parameter4)")
        }
    }
}
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 7. PRE-CRASH APPLICATION FAULTS
# -----------------------------------------------------------------------------
Write-SectionHeader "7. APPLICATION FAULT TELEMETRY (EVENT ID 1000)"
$appErrors = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000} -MaxEvents 15 -ErrorAction SilentlyContinue
if ($appErrors) {
    foreach ($ae in $appErrors) {
        [void]$report.AppendLine("TimeCreated : $($ae.TimeCreated)")
        [void]$report.AppendLine("Message     :")
        $lines = $ae.Message -split "`r?`n"
        foreach ($l in $lines) {
            if ($l.Trim()) {
                [void]$report.AppendLine("    $l")
            }
        }
        [void]$report.AppendLine()
    }
}
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 8. STORAGE HEALTH & INTEGRITY
# -----------------------------------------------------------------------------
Write-SectionHeader "8. STORAGE HEALTH & INTEGRITY"
$disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
if ($disks) {
    Write-SubHeader "Physical Disks"
    foreach ($d in $disks) {
        [void]$report.AppendLine("Disk ID : $($d.DeviceId) | Name: $($d.FriendlyName) | Media: $($d.MediaType) | Health: $($d.HealthStatus) | Status: $($d.OperationalStatus)")
    }
}
$volumes = Get-Volume -ErrorAction SilentlyContinue
if ($volumes) {
    [void]$report.AppendLine()
    Write-SubHeader "Logical Volumes"
    foreach ($v in $volumes) {
        if ($v.DriveLetter) {
            $freeGB = [math]::Round($v.SizeRemaining / 1GB, 2)
            $totalVolGB = [math]::Round($v.Size / 1GB, 2)
            [void]$report.AppendLine("Drive $($v.DriveLetter): ($($v.FileSystemLabel)) | FileSystem: $($v.FileSystem) | Health: $($v.HealthStatus) | Free: $freeGB GB / $totalVolGB GB")
        }
    }
}
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 9. SECURITY & MALWARE VERIFICATION
# -----------------------------------------------------------------------------
Write-SectionHeader "9. SECURITY & MALWARE VERIFICATION (WINDOWS DEFENDER)"
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($defender) {
    [void]$report.AppendLine("Antivirus Enabled           : $($defender.AntivirusEnabled)")
    [void]$report.AppendLine("Real-Time Protection        : $($defender.RealTimeProtectionEnabled)")
    [void]$report.AppendLine("Signatures Last Updated     : $($defender.AntivirusSignatureLastUpdated)")
    [void]$report.AppendLine("Antispyware Enabled         : $($defender.AntispywareEnabled)")
}
$threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
if ($threats) {
    $threatCount = ($threats | Measure-Object).Count
    [void]$report.AppendLine("Recorded Threat Count       : $threatCount")
} else {
    [void]$report.AppendLine("Active Threat Detections    : Zero (No threats currently detected).")
}
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# 10. THIRD-PARTY KERNEL DRIVERS
# -----------------------------------------------------------------------------
Write-SectionHeader "10. THIRD-PARTY KERNEL DRIVER ROSTER"
$thirdPartyDrivers = Get-ChildItem "C:\Windows\System32\drivers\*.sys" -ErrorAction SilentlyContinue | ForEach-Object {
    $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($_.FullName)
    if ($vi.CompanyName -and $vi.CompanyName -notmatch '(?i)Microsoft') {
        [PSCustomObject]@{
            FileName = $_.Name
            Company  = $vi.CompanyName
            Product  = $vi.ProductName
            Modified = $_.LastWriteTime
        }
    }
} | Sort-Object Modified -Descending | Select-Object -First 25

if ($thirdPartyDrivers) {
    foreach ($drv in $thirdPartyDrivers) {
        [void]$report.AppendLine("$($drv.FileName.PadRight(18)) | $($drv.Company.PadRight(30)) | $($drv.Modified.ToString('yyyy-MM-dd')) | $($drv.Product)")
    }
}
[void]$report.AppendLine()

# =============================================================================
# PHASE 2: SYSTEM REPAIR PIPELINE & DEEP LOG PARSER (IF -Repair IS PASSED)
# =============================================================================
if ($Repair) {
    Write-SectionHeader "11. OS REPAIR EXECUTION & CBS/DISM LOG AUDIT"
    
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        [void]$report.AppendLine("[SKIPPED] Administrative elevation is required to execute repair pipeline.")
        Write-Warning "Auto-Repair requires Administrative privileges. Please run as Administrator."
    } else {
        $repairStart = Get-Date

        # Stage 1 Banner
        Write-Host "`n================================================================================" -ForegroundColor Cyan
        Write-Host " [STAGE 1/3] DISM /Online /Cleanup-Image /RestoreHealth" -ForegroundColor Yellow
        Write-Host " What it is    : Windows Component Store (WinSxS) Master Repair" -ForegroundColor White
        Write-Host " What it does  : Scans WinSxS packages for corruption and downloads authentic" -ForegroundColor Gray
        Write-Host "                 replacement files directly from Microsoft Windows Update servers." -ForegroundColor Gray
        Write-Host " Estimated Time: ~3 to 8 minutes (dependent on internet connection & drive speed)" -ForegroundColor Gray
        Write-Host "================================================================================" -ForegroundColor Cyan
        $dismRestore = Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /restorehealth" -Wait -PassThru -NoNewWindow
        
        # Stage 2 Banner
        Write-Host "`n================================================================================" -ForegroundColor Cyan
        Write-Host " [STAGE 2/3] SFC /ScanNow (System File Checker)" -ForegroundColor Yellow
        Write-Host " What it is    : Active Operating System Protected Binaries Verification" -ForegroundColor White
        Write-Host " What it does  : Verifies core files in C:\Windows\System32 and restores damaged" -ForegroundColor Gray
        Write-Host "                 DLL, EXE, and SYS files using the verified WinSxS golden master." -ForegroundColor Gray
        Write-Host " Estimated Time: ~2 to 5 minutes" -ForegroundColor Gray
        Write-Host "================================================================================" -ForegroundColor Cyan
        $sfcScan = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru -NoNewWindow
        
        # Stage 3 Banner
        Write-Host "`n================================================================================" -ForegroundColor Cyan
        Write-Host " [STAGE 3/3] DISM /Online /Cleanup-Image /StartComponentCleanup" -ForegroundColor Yellow
        Write-Host " What it is    : Component Store Maintenance & Cache Reclamation" -ForegroundColor White
        Write-Host " What it does  : Prunes superseded, obsolete, and dormant staging payloads," -ForegroundColor Gray
        Write-Host "                 reclaims disk space, and clears component corruption flags." -ForegroundColor Gray
        Write-Host " Estimated Time: ~2 to 6 minutes" -ForegroundColor Gray
        Write-Host "================================================================================" -ForegroundColor Cyan
        $dismCleanup = Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /startcomponentcleanup" -Wait -PassThru -NoNewWindow
        
        $repairDuration = [math]::Round(((Get-Date) - $repairStart).TotalSeconds, 1)

        [void]$report.AppendLine("Repair Pipeline Start Time : $($repairStart.ToString('yyyy-MM-dd HH:mm:ss'))")
        [void]$report.AppendLine("Repair Pipeline Duration   : ${repairDuration}s")
        [void]$report.AppendLine("DISM RestoreHealth ExitCode: $($dismRestore.ExitCode)")
        [void]$report.AppendLine("SFC ScanNow ExitCode       : $($sfcScan.ExitCode)")
        [void]$report.AppendLine("DISM Cleanup ExitCode      : $($dismCleanup.ExitCode)")
        [void]$report.AppendLine()

        Write-Host "`n[+] Parsing CBS and DISM diagnostic logs..." -ForegroundColor Cyan
        $cbsAudit = Parse-CbsLog -StartTime $repairStart

        # Sub-Section: SFC Active Binaries
        Write-SubHeader "SFC Active Binaries Audit (System32 / Active OS)"
        if ($cbsAudit.SfcRepairedFiles.Count -gt 0) {
            [void]$report.AppendLine("Successfully Repaired Active Files ($($cbsAudit.SfcRepairedFiles.Count)):")
            foreach ($f in $cbsAudit.SfcRepairedFiles) {
                [void]$report.AppendLine("  [FIXED] $f")
            }
        } else {
            [void]$report.AppendLine("No integrity violations or repaired files detected by SFC during this session.")
        }

        if ($cbsAudit.SfcFailedFiles.Count -gt 0) {
            [void]$report.AppendLine()
            [void]$report.AppendLine("Failed / Unrepairable Active Files ($($cbsAudit.SfcFailedFiles.Count)):")
            foreach ($f in $cbsAudit.SfcFailedFiles) {
                [void]$report.AppendLine("  [FAIL] $f")
            }
        }
        [void]$report.AppendLine()

        # Sub-Section: DISM Component Store Payloads
        Write-SubHeader "DISM Component Store Audit (WinSxS / CheckSur)"
        [void]$report.AppendLine("Total Detected Store Corruptions: $($cbsAudit.TotalCorruptions)")
        [void]$report.AppendLine("Total Repaired Store Corruptions: $($cbsAudit.TotalRepaired)")

        if ($cbsAudit.DismFixedPayloads.Count -gt 0) {
            [void]$report.AppendLine("Fixed Component Payloads ($($cbsAudit.DismFixedPayloads.Count)):")
            foreach ($p in $cbsAudit.DismFixedPayloads) {
                [void]$report.AppendLine("  [FIXED] $p")
            }
        }

        if ($cbsAudit.DismFailedPayloads.Count -gt 0) {
            [void]$report.AppendLine("Unrepaired / Missing Replacement Payloads ($($cbsAudit.DismFailedPayloads.Count)):")
            foreach ($p in $cbsAudit.DismFailedPayloads) {
                [void]$report.AppendLine("  [UNREPAIRED] $p")
            }
        }

        if ($cbsAudit.DismErrorCodes.Count -gt 0) {
            [void]$report.AppendLine("DISM Error Codes Encountered:")
            foreach ($err in $cbsAudit.DismErrorCodes) {
                [void]$report.AppendLine("  - $err")
            }
        }
        [void]$report.AppendLine()
    }
}

# -----------------------------------------------------------------------------
# 12. INSTRUCTIONS FOR CONSUMING LLM
# -----------------------------------------------------------------------------
Write-SectionHeader "12. INSTRUCTIONS FOR ANALYZING LLM / AI AGENT"
[void]$report.AppendLine("AI AGENT / LLM INSTRUCTIONS:")
[void]$report.AppendLine("1. Review Sections 4 & 5: Check CPU IMC generation vs. RAM slot population and frequency.")
[void]$report.AppendLine("2. Review Section 6: Analyze BugChecks (0x4E, 0xBE) and Binary Minidump parser results.")
[void]$report.AppendLine("3. Review Section 7: Correlate user applications crashing with 0xC0000374 (Heap Corruption).")
[void]$report.AppendLine("4. Review Section 11 (if present): Inspect SFC and DISM log parse tables to verify whether component store and active system files were repaired.")
[void]$report.AppendLine("5. Output an enduring diagnosis distinguishing hardware memory controller load from software flaws.")
[void]$report.AppendLine()

# -----------------------------------------------------------------------------
# WRITE FILE
# -----------------------------------------------------------------------------
try {
    [System.IO.File]::WriteAllText($OutputFile, $report.ToString(), [System.Text.Encoding]::UTF8)
    Write-Host "[OK] Diagnostic report successfully generated at: $OutputFile" -ForegroundColor Green
} catch {
    Write-Error ("Failed to write diagnostic report: " + $_.Exception.Message)
}

# -----------------------------------------------------------------------------
# PAUSE TERMINAL BEFORE EXIT (KEEPS WINDOW OPEN ON DOUBLE-CLICK)
# -----------------------------------------------------------------------------
if (-not $NoPause -and -not [Console]::IsInputRedirected) {
    Write-Host "`nExecution completed. Press Enter to exit..." -ForegroundColor Yellow
    [void](Read-Host)
}
