---
id: telemetry.crash-dump.parser
title: Pure PowerShell Binary Crash Dump Parser Specification
version: 1.0.0
tags:
  - crash/kernel-dump
  - crash/minidump
  - parser/binary
description: Algorithmic specification for reading MDMP and PAGE/DU64 binary stream directories in PowerShell without external debuggers.
references:
  - telemetry.domain.index
---

# Binary Crash Dump Parser Specification

## 1. Architectural Scope
Extracts faulting drivers and instruction pointers directly from binary Windows crash dump files without requiring WinDbg, Python, or Microsoft debug symbols (`.pdb`).

---

## 2. Minidump (`MDMP`) Stream Parsing Algorithm

1. **Header Validation**:
   * Reads 4-byte signature at offset `0x000`. Must match `0x504D444D` (`MDMP`).
   * Reads `NumberOfStreams` (offset `0x008`) and `StreamDirectoryRva` (offset `0x00C`).
2. **Directory Traversal**:
   * Iterates through `MINIDUMP_DIRECTORY` structures (12 bytes: `StreamType`, `DataSize`, `Rva`).
3. **Exception Stream (Type 8)**:
   * Locates `MINIDUMP_EXCEPTION_STREAM`.
   * Extracts `ExceptionCode` (BugCheck code) and `ExceptionAddress` (64-bit instruction pointer / `RIP`).
4. **Module List Stream (Type 4)**:
   * Reads `NumberOfModules` followed by `MINIDUMP_MODULE` entries (108 bytes each).
   * For each module, records `BaseOfImage`, `SizeOfImage`, and reads Unicode filename string from `ModuleNameRva`.
5. **Driver Isolation**:
   * Correlates:
     $$\text{BaseOfImage} \le \text{ExceptionAddress} < (\text{BaseOfImage} + \text{SizeOfImage})$$
   * The matched module is designated as the primary faulting driver.

---

## 3. Kernel Memory Dump (`PAGE/DU64`) Fallback
* Validates `PAGE` signature (offset `0x000`) and `DU64` marker (offset `0x004`).
* Extracts `BugCheckCode` (offset `0x038`) and Parameters 1–4 (offsets `0x040`, `0x048`, `0x050`, `0x058`).
