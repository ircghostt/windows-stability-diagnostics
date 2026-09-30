---
id: guide.llm.report-analysis-prompt
title: LLM Ingestion & Prompting Guide
version: 1.0.0
tags:
  - guide/llm
  - triage/prompting
description: Recommended prompt templates and instructions for feeding report.txt into AI models for hardware and crash triage.
---

# LLM Prompting Guide for `report.txt`

When you encounter a system freeze, Blue Screen of Death (BSOD), or application crash, generate `report.txt` and provide it to any LLM (e.g., Gemini, Claude, ChatGPT) using the prompt template below.

---

## Recommended Prompt Template

```markdown
I am experiencing system crashes/BSODs on my Windows machine. 
I have run an automated diagnostic telemetry script that collected hardware specifications, 
memory controller topology, BugCheck crash logs, pre-crash application errors, and OS repair logs.

Attached is my `report.txt`. Please perform a surgical triage:
1. Examine the CPU architecture and the official Integrated Memory Controller (IMC) frequency ceiling.
2. Cross-reference with the physical RAM topology (number of populated slots, rated XMP speed vs. configured clock).
3. Analyze the BugCheck codes (e.g., 0x4E, 0xBE, 0x1A, 0x3B) and determine whether they indicate software/driver flaws, malware, or hardware/timing instability.
4. Review pre-crash application failures (e.g., heap corruption 0xC0000374) to correlate user-mode pressure with kernel crashes.
5. If the repair section is present, check which system files were repaired or left unrepairable.
6. Provide an enduring, root-cause resolution (including BIOS voltages, frequency down-clocking, or hardware isolation).
```
