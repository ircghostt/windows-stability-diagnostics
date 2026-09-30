---
id: triage.hardware.sandy-bridge-memory
title: Sandy Bridge Memory Controller & 4-DIMM Stability Specification
version: 1.0.0
tags:
  - hardware/bios
  - hardware/imc
  - triage/sandy-bridge
description: Root-cause triage rules and BIOS voltage/timing remediation profiles for Intel Sandy Bridge 32GB 4-DIMM memory stability.
references:
  - triage.domain.index
  - telemetry.hardware.audit
---

# Sandy Bridge 4-DIMM Memory Stability Specification

## 1. Triage Rule Matrix
When analyzing `report.txt`, agents must apply the following deterministic decision rules:

* **Alternating BugChecks**: If logs show multiple different memory BugChecks (`0x4E PFN_LIST_CORRUPT`, `0xBE ATTEMPTED_WRITE_TO_READONLY_MEMORY`, `0x1A MEMORY_MANAGEMENT`), conclude **hardware/bus instability**, not single-driver bugs.
* **Pre-Crash Heap Faults**: If compilers or memory allocators crash with `0xC0000374` (`STATUS_HEAP_CORRUPTION`) prior to a BSOD, conclude **memory bit-flip under load**.
* **Malware Elimination**: If Windows Defender real-time protection is active and threat detections are zero, rule out malware.

---

## 2. Platform Architecture Constraints (Intel Sandy Bridge)
* **Official IMC Maximum**: Intel rates the 2nd Gen Core memory controller for **DDR3-1333 MHz** at **1.50V (±5%)**.
* **4-Slot Penalty**: Fully populating 4 slots with 8GB dual-rank modules (8 ranks total) severely strains the aging memory controller. Running 1866 MHz XMP at 1.65V induces signal reflection and bus degradation over time.

---

## 3. Enduring BIOS Configuration Profile (ASUS P8P67 Deluxe)

| BIOS Parameter | Value | Technical Justification |
| :--- | :--- | :--- |
| **`Memory Frequency`** | `DDR3-1333MHz` | Aligns operating clock with Intel IMC native rating. |
| **`DRAM Command Mode`** | `2T` | **Mandatory**: Prevents address collision across 4 dual-rank DIMMs. |
| **`DRAM CAS# Latency`** | `9-9-9-24` | JEDEC standard baseline timings. |
| **`DRAM Voltage`** | `1.525V` | +0.025V compensates for motherboard VRM capacitor aging. |
| **`VCCIO Voltage`** | `1.100V` | Stabilizes IMC bus driving 32 GB (8 ranks). |
| **`CPU VCCSA Voltage`** | `0.950V` | Stabilizes System Agent circuitry. |
