---
id: system.architecture.windows-stability-diagnostics
title: Windows Stability Diagnostics Architecture
version: 1.0.0
tags:
  - architecture/diagnostics
  - os/windows
  - system/triage
description: Technical architecture, binary parsing algorithms, and OS servicing pipeline for windows-stability-diagnostics.
---

# Architecture & Telemetry Pipeline

## 1. Overview
`windows-stability-diagnostics` is a self-contained, dependency-free toolkit for Windows systems. It operates in two cooperative phases:
1. **Telemetry Extraction**: Non-destructive, fast audit of hardware architecture, memory bus topology, BugCheck event history, and binary crash dumps.
2. **Automated Servicing & Repair Pipeline**: 3-stage component store and active system file remediation with deep regex log parsing.

---

## 2. Binary Crash Dump Parsing Engine (`Parse-Minidump.ps1`)

Unlike traditional crash dump analysis that relies on WinDbg (`dbghelp.dll`, `.pdb` debug symbols), `Parse-Minidump.ps1` implements a direct binary parser in pure PowerShell using `[System.IO.BinaryReader]`:

### Minidump (`MDMP`) Flow
```
[Minidump File (.dmp)]
  ├── Header Verification: Validates 'MDMP' signature (0x504D444D)
  ├── Stream Directory: Seeks through MINIDUMP_DIRECTORY table via RVA
  │     ├── ExceptionStream (Type 8):
  │     │     ├── ExceptionCode (BugCheck code)
  │     │     └── ExceptionAddress (RIP / EIP Instruction Pointer)
  │     └── ModuleListStream (Type 4):
  │           └── Iterates all loaded drivers (.sys) and modules
  └── Memory Map Correlation:
        Tests: BaseOfImage <= ExceptionAddress < (BaseOfImage + SizeOfImage)
        └── Isolates exact faulting driver name, path, and version
```

### 64-Bit Kernel Dump (`PAGE/DU64`) Fallback
* Parses `DUMP_HEADER64` at offset `0x000`.
* Extracts `BugCheckCode` (offset `0x38`), parameters 1–4 (offset `0x40`), `MachineImageType`, and CPU processor count.

---

## 3. Repair & Servicing Lifecycle

The 3-stage repair pipeline executes Microsoft's recommended servicing sequence:

```
[Stage 1: DISM RestoreHealth]
      │ Scans master WinSxS component store; downloads authentic replacements from Windows Update.
      ▼
[Stage 2: SFC ScanNow]
      │ Compares protected binaries in C:\Windows\System32 against the verified WinSxS store.
      ▼
[Stage 3: DISM StartComponentCleanup]
      │ Prunes superseded/dormant payloads, cleans update caches, and resets CBS corruption flags.
      ▼
[CBS & DISM Deep Log Parser]
      │ Parses C:\Windows\Logs\CBS\CBS.log for [SR] Repairing file and (p) CSI Payload Corrupt.
      ▼
[Consolidated report.txt]
```
