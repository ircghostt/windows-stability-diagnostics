---
id: servicing.os.repair-pipeline
title: Automated 3-Stage Windows OS Servicing Pipeline
version: 1.0.1
tags:
  - servicing/dism
  - servicing/pipeline
  - servicing/sfc
description: Three-stage automated OS maintenance pipeline executing DISM RestoreHealth, SFC ScanNow, and Component Cleanup across orchestrator and standalone tools.
references:
  - servicing.domain.index
  - servicing.cbs.log-parser
---

# 3-Stage OS Servicing Pipeline

## 1. Execution Flow & Rationale
Operating system crashes often corrupt files cached in transit. The toolkit executes a deterministic three-stage remediation sequence:

```
[Stage 1: DISM /Online /Cleanup-Image /RestoreHealth]
  └── Scans WinSxS component store; replaces damaged packages using Windows Update.
[Stage 2: SFC /ScanNow]
  └── Compares protected system binaries in C:\Windows\System32 against WinSxS.
[Stage 3: DISM /Online /Cleanup-Image /StartComponentCleanup]
  └── Prunes superseded historical versions, reclaims disk space, and resets CBS flags.
```

---

## 2. Implementation Mapping

The 3-stage pipeline is implemented consistently across two execution vehicles:

1. **`src/scripts/diagnose_system.ps1`** (Consolidated Master Tool):
   * Runs the 3 stages by default (or via double-clicking `Run_Repair_And_Diagnostic.bat`).
   * Automatically stream-parses `CBS.log` to catalog repaired files vs. unrepaired files and embeds findings into `report.txt`.
2. **`src/scripts/Repair-SystemFiles.ps1`** (Dedicated Standalone Utility):
   * Standalone execution of the 3-stage sequence without gathering full hardware/crash dump telemetry.
   * Logs duration and exit codes to `repair_log.txt`.

---

## 3. Stage Invariants
* **Elevation**: Execution requires `SeSecurityPrivilege` / Administrator role.
* **Component Store Priority**: DISM `/RestoreHealth` must execute prior to `SFC /ScanNow` to ensure the backup store (`WinSxS`) is verified before repairing active binaries.
* **Non-Destructive Guarantee**: The pipeline only repairs core Microsoft OS packages; personal files, applications, and settings remain untouched.
