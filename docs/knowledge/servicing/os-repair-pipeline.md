---
id: servicing.os.repair-pipeline
title: Automated 3-Stage Windows OS Servicing Pipeline
version: 1.0.0
tags:
  - servicing/dism
  - servicing/pipeline
  - servicing/sfc
description: Three-stage automated OS maintenance pipeline executing DISM RestoreHealth, SFC ScanNow, and Component Cleanup.
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

## 2. Stage Invariants
* **Elevation**: Execution requires `SeSecurityPrivilege` / Administrator role.
* **Component Store Priority**: DISM `/RestoreHealth` must execute prior to `SFC /ScanNow` to ensure the backup store (`WinSxS`) is verified before repairing active binaries.
* **Non-Destructive Guarantee**: The pipeline only repairs core Microsoft OS packages; personal files, applications, and settings remain untouched.
