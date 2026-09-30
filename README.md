---
id: project.windows-stability-diagnostics
title: Windows Stability Diagnostics & Auto-Repair Toolkit
version: 1.0.0
tags:
  - os/windows
  - hardware/diagnostics
  - triage/bsod
description: Dependency-free PowerShell toolkit for Windows crash dump parsing, memory controller triage, and automated 3-stage OS repair.
---

# Windows Stability Diagnostics & Auto-Repair Toolkit

A lightweight, dependency-free PowerShell suite designed for rapid system triage, hardware memory controller analysis, binary crash dump inspection, and automated Windows operating system repair.

Generates a clean, comprehensive `report.txt` structured specifically for ingestion by Large Language Models (LLMs) to derive surgical root-cause diagnoses for Blue Screen of Death (BSOD) crashes and hardware instability.

---

## Key Capabilities

* **Hardware & IMC Telemetry**: Automatically queries CPU generation, architecture, and official Integrated Memory Controller (IMC) limits.
* **RAM Topology Audit**: Inspects slot population (identifies 4-DIMM capacitive load), module vendors, rated speeds, and configured operating clocks.
* **Pure PowerShell Binary Crash Dump Parser**: Reads Microsoft Minidump (`MDMP`) structures directly without external tools or debuggers (no WinDbg or `.pdb` symbols required). Isolates the faulting `.sys` driver and instruction pointer (`RIP/EIP`).
* **3-Stage Automated OS Repair Pipeline**:
  1. `DISM /RestoreHealth` (Windows Component Store repair)
  2. `SFC /ScanNow` (System32 active binary verification)
  3. `DISM /StartComponentCleanup` (Prunes dormant payloads and clears servicing flags)
* **Deep Servicing Log Parser**: Streams `C:\Windows\Logs\CBS\CBS.log` to catalog repaired files, unrepaired payloads, and HRESULT error codes.
* **LLM-Ready Report Output**: Generates an all-in-one `report.txt` formatted with diagnostic instructions for AI triage.

---

## Directory Structure

```
windows-stability-diagnostics/
├── src/
│   └── scripts/
│       ├── diagnose_system.ps1       # Master telemetry and auto-repair orchestrator
│       ├── Parse-Minidump.ps1        # Binary MDMP & Kernel MEMORY.DMP parser
│       ├── Enable-Minidump.ps1       # One-click registry config for 256 KB minidumps
│       └── Repair-SystemFiles.ps1     # Standalone 2-stage DISM + SFC repair script
├── docs/
│   ├── ARCHITECTURE.md               # Technical binary parsing & servicing specification
│   └── LLM_PROMPT_GUIDE.md           # Instructions for feeding report.txt to AI models
├── Run_Diagnostic.bat                # Double-click launcher: Fast read-only telemetry (~5s)
├── Run_Repair_And_Diagnostic.bat     # Double-click launcher: Full 3-stage repair & report
├── .gitignore
├── LICENSE                           # MIT License
└── README.md
```

---

## Quick Start

### 1. Fast Telemetry Audit (~5 seconds, Read-Only)
Collects full hardware context, memory topology, and crash logs without modifying system files:
* Double-click **`Run_Diagnostic.bat`**, or run:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\src\scripts\diagnose_system.ps1 -DiagnoseOnly
  ```

### 2. Full Diagnostics & 3-Stage Auto-Repair (~10–15 minutes, Admin)
Executes telemetry collection, runs the 3-stage repair pipeline, cleans stale component store caches, and audits repaired files:
* Double-click **`Run_Repair_And_Diagnostic.bat`** (prompts for UAC elevation), or run:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\src\scripts\diagnose_system.ps1
  ```

### 3. Parse a Single Crash Dump Manually
Directly inspect any `.dmp` file or `MEMORY.DMP`:
```powershell
powershell -ExecutionPolicy Bypass -File .\src\scripts\Parse-Minidump.ps1 -Path "C:\Windows\Minidump\your_dump.dmp"
```

---

## Using with LLMs

After running the diagnostic suite:
1. Locate the generated **`report.txt`** in the repository directory.
2. Upload `report.txt` to your LLM of choice (Gemini, Claude, ChatGPT).
3. Refer to [docs/LLM_PROMPT_GUIDE.md](docs/LLM_PROMPT_GUIDE.md) for the optimal analysis prompt.

---

## License

Released under the [MIT License](LICENSE).
