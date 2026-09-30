---
id: servicing.cbs.log-parser
title: CBS & DISM Streaming Log Parsing Engine
version: 1.0.0
tags:
  - logging/cbs
  - logging/dism
  - parser/regex
description: Stream-parsing algorithm for extracting repaired active binaries, corrupt payloads, and HRESULT error codes from CBS.log.
references:
  - servicing.domain.index
---

# CBS & DISM Streaming Log Parser Specification

## 1. Architectural Scope
Extracts structured telemetry from `C:\Windows\Logs\CBS\CBS.log` using a memory-efficient `[System.IO.StreamReader]` line-by-line pipeline.

---

## 2. Extraction Regex Patterns

| Target Category | Regex Pattern | Meaning |
| :--- | :--- | :--- |
| **SFC Repaired File** | `\[SR\] Repairing (?:corrupted )?file (?:\\\\\?\\)?(?<file>[^\r\n]+?)(?: from store)?$` | Active system file repaired in `System32`. |
| **SFC Failed File** | `\[SR\] (?:Could not reproject corrupted file\|Cannot repair member file) (?:\\\\\?\\)?(?<file>[^\r\n]+)` | Active file unrepairable from store. |
| **DISM Fixed Payload** | `\(p\)\s+CSI Payload Corrupt\s+\(w\)\s+\(Fixed\)\s+(?<comp>[^\r\n]+)` | Component store payload downloaded and fixed. |
| **DISM Missing Source** | `\(p\)\s+CSI Payload Corrupt\s+\(n\)\s+(?<comp>[^\r\n]+)` | Component payload missing from update catalog. |
| **DISM HRESULT Errors** | `HRESULT = (?<hex>0x[0-9a-fA-F]+)\s*-\s*(?<code>[A-Z0-9_]+)` | Explicit error status codes (e.g., `0x800f081f`). |
| **CheckSur Totals** | `Total (?:Detected\|Repaired) Corruption:\s+(?<count>\d+)` | High-level component corruption counters. |
