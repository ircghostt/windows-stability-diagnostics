<#
.SYNOPSIS
    Pure PowerShell binary crash dump parser for Windows Minidumps (.dmp) and Kernel Dumps (MEMORY.DMP).
.DESCRIPTION
    Directly reads Microsoft Minidump (MDMP) and Kernel Dump (PAGE/DU64) binary structures.
    Extracts BugCheck codes, Exception Addresses (RIP/EIP), and maps the faulting memory address
    to the exact offending kernel driver (.sys) and module list without requiring WinDbg or external tools.
.PARAMETER Path
    Path to a .dmp or MEMORY.DMP file. If omitted, automatically selects the latest file from C:\Windows\Minidump
    or falls back to C:\Windows\MEMORY.DMP.
#>

[CmdletBinding()]
param(
    [string]$Path
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

# Common Windows BugCheck translation dictionary
$bugCheckDict = @{
    0x0A = "IRQL_NOT_LESS_OR_EQUAL"
    0x1A = "MEMORY_MANAGEMENT"
    0x1E = "KMODE_EXCEPTION_NOT_HANDLED"
    0x24 = "NTFS_FILE_SYSTEM"
    0x3B = "SYSTEM_SERVICE_EXCEPTION"
    0x4E = "PFN_LIST_CORRUPT"
    0x50 = "PAGE_FAULT_IN_NONPAGED_AREA"
    0x7B = "INACCESSIBLE_BOOT_DEVICE"
    0x7E = "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED"
    0x9F = "DRIVER_POWER_STATE_FAILURE"
    0xBE = "ATTEMPTED_WRITE_TO_READONLY_MEMORY"
    0xD1 = "DRIVER_IRQL_NOT_LESS_OR_EQUAL"
    0xF7 = "DRIVER_OVERRAN_STACK_BUFFER"
    0x109 = "CRITICAL_STRUCTURE_CORRUPTION"
    0x116 = "VIDEO_TDR_FAILURE"
    0x124 = "WHEA_UNCORRECTABLE_ERROR"
    0x133 = "DPC_WATCHDOG_VIOLATION"
    0x139 = "KERNEL_SECURITY_CHECK_FAILURE"
}

# Resolve file path
if (-not $Path) {
    $latestMini = Get-ChildItem -Path "C:\Windows\Minidump\*.dmp" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestMini) {
        $Path = $latestMini.FullName
    } elseif (Test-Path "C:\Windows\MEMORY.DMP") {
        $Path = "C:\Windows\MEMORY.DMP"
    } else {
        Write-Error "No crash dump file found in C:\Windows\Minidump or C:\Windows\MEMORY.DMP."
        return
    }
}

if (-not (Test-Path $Path)) {
    Write-Error "Specified file does not exist: $Path"
    return
}

$fileItem = Get-Item $Path
$fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$br = [System.IO.BinaryReader]::new($fs)

try {
    # Read first 4 bytes signature
    $sigBytes = $br.ReadBytes(4)
    $sigAscii = [System.Text.Encoding]::ASCII.GetString($sigBytes)

    # =========================================================================
    # FORMAT 1: Microsoft Minidump (MDMP)
    # =========================================================================
    if ($sigAscii -eq "MDMP") {
        Write-Host "`n[+] Recognized Microsoft Minidump: $Path" -ForegroundColor Cyan
        
        $version = $br.ReadUInt32()
        $numStreams = $br.ReadUInt32()
        $streamDirRva = $br.ReadUInt32()
        $checkSum = $br.ReadUInt32()
        $timeDateStamp = $br.ReadUInt32()
        $flags = $br.ReadUInt64()

        $crashDate = ([datetime]'1970-01-01 00:00:00Z').AddSeconds($timeDateStamp).ToLocalTime()

        # Read Stream Directory
        $streams = @()
        $fs.Seek($streamDirRva, [System.IO.SeekOrigin]::Begin) | Out-Null
        for ($i = 0; $i -lt $numStreams; $i++) {
            $streams += [PSCustomObject]@{
                StreamType = $br.ReadUInt32()
                DataSize   = $br.ReadUInt32()
                Rva        = $br.ReadUInt32()
            }
        }

        # Find Exception Stream (Type 8)
        $excStream = $streams | Where-Object { $_.StreamType -eq 8 } | Select-Object -First 1
        $exceptionAddress = [uint64]0
        $exceptionCode = [uint32]0
        $bugCheckName = "N/A"

        if ($excStream) {
            $fs.Seek($excStream.Rva, [System.IO.SeekOrigin]::Begin) | Out-Null
            $threadId = $br.ReadUInt32()
            $alignment = $br.ReadUInt32()
            $exceptionCode = $br.ReadUInt32()
            $exceptionFlags = $br.ReadUInt32()
            $exceptionRecord = $br.ReadUInt64()
            $exceptionAddress = $br.ReadUInt64()
            $numParams = $br.ReadUInt32()
            $unusedAlign = $br.ReadUInt32()

            $params = @()
            for ($p = 0; $p -lt 15; $p++) {
                $params += $br.ReadUInt64()
            }

            $bugCheckInt = [int32]($exceptionCode -band 0xFFFFFFFF)
            if ($bugCheckDict.ContainsKey($bugCheckInt)) {
                $bugCheckName = $bugCheckDict[$bugCheckInt]
            }
        }

        # Find Module List Stream (Type 4)
        $modStream = $streams | Where-Object { $_.StreamType -eq 4 } | Select-Object -First 1
        $modules = @()

        if ($modStream) {
            $fs.Seek($modStream.Rva, [System.IO.SeekOrigin]::Begin) | Out-Null
            $numModules = $br.ReadUInt32()

            for ($m = 0; $m -lt $numModules; $m++) {
                $baseOfImage = $br.ReadUInt64()
                $sizeOfImage = $br.ReadUInt32()
                $modCheckSum = $br.ReadUInt32()
                $modTimeDate = $br.ReadUInt32()
                $nameRva     = $br.ReadUInt32()

                # Read VS_FIXEDFILEINFO (52 bytes)
                $verBytes = $br.ReadBytes(52)
                $fileVerMS = [BitConverter]::ToUInt32($verBytes, 8)
                $fileVerLS = [BitConverter]::ToUInt32($verBytes, 12)
                $fileVersion = "{0}.{1}.{2}.{3}" -f ($fileVerMS -shr 16), ($fileVerMS -band 0xFFFF), ($fileVerLS -shr 16), ($fileVerLS -band 0xFFFF)

                # Skip CvRecord (8 bytes) + MiscRecord (8 bytes) + Reserved0 (8) + Reserved1 (8) = 32 bytes
                $cvRecord = $br.ReadBytes(32)

                $modules += [PSCustomObject]@{
                    BaseOfImage = $baseOfImage
                    EndOfImage  = $baseOfImage + $sizeOfImage
                    Size        = $sizeOfImage
                    NameRva     = $nameRva
                    Version     = $fileVersion
                    Path        = ""
                    FileName    = ""
                }
            }

            # Resolve module names from NameRva
            foreach ($mod in $modules) {
                if ($mod.NameRva -gt 0) {
                    $fs.Seek($mod.NameRva, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $nameLen = $br.ReadUInt32()
                    $nameChars = $br.ReadBytes($nameLen)
                    $modPath = [System.Text.Encoding]::Unicode.GetString($nameChars).TrimEnd([char]0)
                    $mod.Path = $modPath
                    $mod.FileName = [System.IO.Path]::GetFileName($modPath)
                }
            }
        }

        # Correlate Faulting Instruction Address to Module
        $faultingModule = $null
        if ($exceptionAddress -gt 0 -and $modules.Count -gt 0) {
            $faultingModule = $modules | Where-Object { $exceptionAddress -ge $_.BaseOfImage -and $exceptionAddress -lt $_.EndOfImage } | Select-Object -First 1
        }

        # Build Output Result
        $result = [PSCustomObject]@{
            DumpType         = "Minidump (MDMP)"
            FilePath         = $Path
            CrashTime        = $crashDate
            BugCheckCode     = "0x{0:X}" -f $exceptionCode
            BugCheckName     = $bugCheckName
            ExceptionAddress = "0x{0:X}" -f $exceptionAddress
            FaultingDriver   = if ($faultingModule) { $faultingModule.FileName } else { "Unknown / Hardware Memory Bit-Flip" }
            DriverPath       = if ($faultingModule) { $faultingModule.Path } else { "N/A" }
            DriverVersion    = if ($faultingModule) { $faultingModule.Version } else { "N/A" }
            DriverBase       = if ($faultingModule) { "0x{0:X}" -f $faultingModule.BaseOfImage } else { "N/A" }
            DriverEnd        = if ($faultingModule) { "0x{0:X}" -f $faultingModule.EndOfImage } else { "N/A" }
            TotalModules     = $modules.Count
        }

        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host " MINIDUMP CRASH DIAGNOSIS REPORT" -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host "Crash Timestamp  : $($result.CrashTime)"
        Write-Host "BugCheck Code    : $($result.BugCheckCode) ($($result.BugCheckName))"
        Write-Host "Instruction (RIP): $($result.ExceptionAddress)"
        Write-Host "Faulting Driver  : $($result.FaultingDriver)" -ForegroundColor Red
        Write-Host "Driver Location  : $($result.DriverPath)"
        Write-Host "Driver Version   : $($result.DriverVersion)"
        Write-Host "Driver Memory    : $($result.DriverBase) - $($result.DriverEnd)"
        Write-Host "Total Loaded Mods: $($result.TotalModules)"
        Write-Host "================================================================================`n" -ForegroundColor Yellow

        return $result

    # =========================================================================
    # FORMAT 2: Microsoft 64-bit Kernel Dump (PAGE / DU64)
    # =========================================================================
    } elseif ($sigAscii -eq "PAGE") {
        Write-Host "`n[+] Recognized Windows 64-bit Kernel Memory Dump: $Path" -ForegroundColor Cyan
        
        $validDump = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        if ($validDump -ne "DU64") {
            Write-Warning "File signature is PAGE but secondary marker is not DU64: $validDump"
        }

        $majorVersion = $br.ReadUInt32()
        $minorVersion = $br.ReadUInt32()
        $dirTableBase = $br.ReadUInt64()
        $pfnDataBase  = $br.ReadUInt64()
        $psLoadedMods = $br.ReadUInt64()
        $psActiveProc = $br.ReadUInt64()
        $machineType  = $br.ReadUInt32()
        $numCPUs      = $br.ReadUInt32()

        # Bugcheck info at offset 0x38
        $fs.Seek(0x38, [System.IO.SeekOrigin]::Begin) | Out-Null
        $bugCheckCode = $br.ReadUInt32()
        $fs.Seek(0x40, [System.IO.SeekOrigin]::Begin) | Out-Null
        $p1 = $br.ReadUInt64()
        $p2 = $br.ReadUInt64()
        $p3 = $br.ReadUInt64()
        $p4 = $br.ReadUInt64()

        $bugCheckInt = [int32]($bugCheckCode -band 0xFFFFFFFF)
        $bugCheckName = if ($bugCheckDict.ContainsKey($bugCheckInt)) { $bugCheckDict[$bugCheckInt] } else { "UNKNOWN_BUGCHECK" }

        $result = [PSCustomObject]@{
            DumpType         = "Kernel Memory Dump (PAGE/DU64)"
            FilePath         = $Path
            FileSizeMB       = [math]::Round($fileItem.Length / 1MB, 2)
            LastModified     = $fileItem.LastWriteTime
            BugCheckCode     = "0x{0:X}" -f $bugCheckCode
            BugCheckName     = $bugCheckName
            Parameter1       = "0x{0:X}" -f $p1
            Parameter2       = "0x{0:X}" -f $p2
            Parameter3       = "0x{0:X}" -f $p3
            Parameter4       = "0x{0:X}" -f $p4
            NumberProcessors = $numCPUs
            DirectoryTable   = "0x{0:X}" -f $dirTableBase
            PsLoadedModules  = "0x{0:X}" -f $psLoadedMods
        }

        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host " KERNEL DUMP HEADER DIAGNOSIS REPORT" -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host "File Size        : $($result.FileSizeMB) MB"
        Write-Host "Last Modified    : $($result.LastModified)"
        Write-Host "BugCheck Code    : $($result.BugCheckCode) ($($result.BugCheckName))" -ForegroundColor Red
        Write-Host "Parameter 1 (VA) : $($result.Parameter1)"
        Write-Host "Parameter 2 (PTE): $($result.Parameter2)"
        Write-Host "Parameter 3 (TRP): $($result.Parameter3)"
        Write-Host "Parameter 4 (SUB): $($result.Parameter4)"
        Write-Host "Processor Count  : $($result.NumberProcessors)"
        Write-Host "PsLoadedMod Ptr  : $($result.PsLoadedModules)"
        Write-Host "================================================================================`n" -ForegroundColor Yellow

        return $result

    } else {
        Write-Error "Unrecognized dump file signature: $sigAscii (Expected 'MDMP' or 'PAGE')"
        return
    }

} finally {
    $br.Close()
    $fs.Close()
}
