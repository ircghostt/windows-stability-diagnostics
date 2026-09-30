---
id: telemetry.hardware.audit
title: Hardware & Integrated Memory Controller Telemetry Specification
version: 1.0.0
tags:
  - hardware/imc
  - hardware/ram
  - telemetry/hardware
description: Specification of hardware discovery algorithms for CPU memory controllers and 4-slot DIMM topologies.
references:
  - telemetry.domain.index
  - triage.hardware.sandy-bridge-memory
---

# Hardware & IMC Telemetry Specification

## 1. Architectural Scope
The hardware telemetry component extracts precise silicon identifiers and topology factors that induce memory bus instability.

---

## 2. Extraction Schema & Sources

### Processor & IMC Context
* **Class**: `Win32_Processor`
* **Target Properties**: `Name`, `NumberOfCores`, `NumberOfLogicalProcessors`, `MaxClockSpeed`, `SocketDesignation`.
* **Analytical Purpose**: Correlates the CPU microarchitecture against official Intel/AMD Integrated Memory Controller (IMC) frequency specifications (e.g., Sandy Bridge IMC official maximum: DDR3-1333).

### Memory Subsystem Topology
* **Class**: `Win32_PhysicalMemory` & `Win32_PhysicalMemoryArray`
* **Target Properties**:
  * `DeviceLocator`: Maps channel layout (`ChannelA-DIMM0`, `ChannelB-DIMM1`).
  * `Capacity`: Raw byte capacity per stick.
  * `Speed`: Factory JEDEC/XMP rated speed.
  * `ConfiguredClockSpeed`: Current active operating frequency negotiated by the BIOS.
  * `PartNumber`: Manufacturer part string (e.g., `KHX1866C10D3/8G`).
* **Analytical Rule**: Populating all 4 physical DIMM slots introduces capacitive load and trace reflection on 2nd-generation Intel motherboards, necessitating lower operating frequencies and 2T Command Rates.
