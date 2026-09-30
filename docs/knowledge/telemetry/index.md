---
id: telemetry.domain.index
title: Telemetry & Crash Dump Extraction Domain Index
version: 1.0.0
tags:
  - diagnostics/telemetry
  - os/windows
description: Domain index for hardware audits, memory controller telemetry, and binary crash dump extraction.
references:
  - system.bundle.windows-stability-diagnostics
  - telemetry.hardware.audit
  - telemetry.crash-dump.parser
---

# Telemetry & Crash Dump Extraction Domain Index

## 1. Domain Summary
This domain encompasses the discovery of hardware architecture, processor Integrated Memory Controller (IMC) limits, memory slot topology, Kernel-Power event logs, and direct binary parsing of Windows crash dumps.

---

## 2. Concept Nodes

* **[[telemetry.hardware.audit]]**: Specifications for CIM/WMI hardware extraction, slot population calculation, and memory clock auditing.
* **[[telemetry.crash-dump.parser]]**: Low-level specification of the pure PowerShell binary parser for Microsoft Minidump (`MDMP`) and Kernel Dump (`PAGE/DU64`) files.
