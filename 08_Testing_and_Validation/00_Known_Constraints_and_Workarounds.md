# Known Constraints and Workarounds

**Version:** 1.0  
**Status:** Living Document - Updated Quarterly  
**Classification:** Medical Device SDK - Risk Management  
**Compliance:** ISO 14971, IEC 62304, FDA Cybersecurity Guidance  

---

## Overview

This document identifies known technical constraints, limitations, and risks in the Medical Device Platform SDK along with approved workarounds and mitigation strategies. This is a living document that must be reviewed and updated:
- Before each phase gate review
- Upon discovery of new constraints
- After regulatory feedback or audit findings

---

## Active Constraints

### 1. Hypervisor Maturity on QCS8550

| Attribute | Details |
|-----------|---------|
| **Risk ID** | CONST-001 |
| **Category** | System Architecture |
| **Severity** | High |
| **Probability** | Medium |
| **Impact** | Isolation stability between safety-critical and application domains may be compromised during early development |

**Technical Details:**
- Qualcomm's Type-1 hypervisor reference implementation for QCS8550 is still maturing
- Limited documentation on VM exit latency and interrupt routing
- No pre-certified hypervisor configuration for medical use

**Approved Workarounds:**
1. **Primary**: Use Qualcomm reference Type-1 hypervisor with extensive HIL testing
2. **Fallback**: PREEMPT_RT kernel + cgroups + namespace isolation (single-OS mode)
3. **Long-term**: Engage ACRN/Jailhouse communities for mainline support

**Validation Requirements:**
- Measure VM exit latency under load (>10,000 iterations)
- Fault injection testing (hypervisor crash recovery)
- Memory corruption detection between partitions

**Target Resolution:** Phase 2 (M6)

---

### 2. Linux Real-Time Performance Limits

| Attribute | Details |
|-----------|---------|
| **Risk ID** | CONST-002 |
| **Category** | Real-Time Performance |
| **Severity** | High |
| **Probability** | Low |
| **Impact** | Cannot guarantee <100µs response time for safety-critical control loops |

**Technical Details:**
- Linux PREEMPT_RT typically achieves 200-500µs worst-case latency
- SMI (System Management Interrupts), cache misses, and TLB flushes cause jitter spikes
- Not suitable for Class C software controlling high-risk actuators

**Approved Workarounds:**
1. **Mandatory**: External Cortex-R52 or AURIX TC4x MCU for safety-critical loops (<100µs)
2. **IPC Mechanism**: `SafetyBridge` protocol with certified message passing (shared memory + hardware semaphore)
3. **Monitoring**: Hardware watchdog with independent clock source

**Architecture Decision:**
```
┌─────────────────────┐     ┌──────────────────────┐
│   Linux (QCS8550)   │     │  Safety MCU (Cortex-R)│
│   Application Layer │◀───▶│  Real-Time Control   │
│   (>1ms acceptable) │ IPC │  (<100µs guaranteed) │
└─────────────────────┘     └──────────────────────┘
```

**Target Resolution:** Architectural requirement (permanent)

---

### 3. AI Model Drift (Class III SaMD)

| Attribute | Details |
|-----------|---------|
| **Risk ID** | CONST-003 |
| **Category** | AI/ML Safety |
| **Severity** | High |
| **Probability** | Medium |
| **Impact** | Clinical accuracy degradation over time due to population shift, device variation, or adversarial inputs |

**Technical Details:**
- FDA PCCP (Predetermined Change Control Plan) required for AI model updates
- Shadow mode validation needed before deployment
- Continuous monitoring for performance degradation

**Approved Workarounds:**
1. **PCCP Framework**: Pre-approved model update envelope (accuracy bounds, input distribution limits)
2. **Shadow Mode**: New models run parallel to production, compare outputs without affecting clinical decisions
3. **Rollback Capability**: OTA with atomic rollback to last validated model version
4. **Physician Override**: Manual disable switch for AI recommendations

**Regulatory Alignment:**
- FDA AI/ML SaMD Action Plan
- IMDRF AI/ML Working Group guidelines
- EU MDR Annex XVI (AI classification rules)

**Target Resolution:** Phase 3 (M9) - Full PCCP implementation

---

### 4. Thermal Throttling (Passive Cooling)

| Attribute | Details |
|-----------|---------|
| **Risk ID** | CONST-004 |
| **Category** | Hardware Performance |
| **Severity** | Medium |
| **Probability** | High |
| **Impact** | Sustained workloads (AI inference, video encoding) trigger thermal throttling, causing performance degradation |

**Technical Details:**
- QCS8550 TDP: 5-7W (typical), up to 10W (burst)
- Passive cooling limited to ~5W continuous in enclosed medical housing
- Throttling starts at 85°C junction temperature

**Approved Workarounds:**
1. **Dynamic DVFS**: Frequency/voltage scaling based on thermal headroom
2. **Workload Prioritization**: Throttle non-critical tasks (UI animations, background sync) before real-time pipelines
3. **Thermal Guard API**: Applications receive thermal state notifications and adapt accordingly
4. **Active Cooling**: Optional fan/heatsink design for high-performance configurations

**Mitigation Code Example:**
```cpp
if (thermal_zone.get_temp() > 75°C) {
    scheduler.reduce_priority(NON_CRITICAL_TASKS);
    ai_engine.set_max_fps(15);  // Reduce from 30fps
}
```

**Target Resolution:** Phase 2 (M5) - Thermal management API complete

---

### 5. SOUP CVE Exposure

| Attribute | Details |
|-----------|---------|
| **Risk ID** | CONST-005 |
| **Category** | Cybersecurity |
| **Severity** | High |
| **Probability** | Medium |
| **Impact** | Third-party library vulnerabilities (OpenCV, Qt, OpenSSL) may delay certification or require urgent patches |

**Technical Details:**
- Average CVE discovery rate: 2-3 critical vulnerabilities per quarter in major SOUP components
- Patch validation cycle: 2-4 weeks for regression testing
- Regulatory impact: May require supplemental submission if patch affects safety functions

**Approved Workarounds:**
1. **Automated SBOM**: CycloneDX format generated at every build, continuously monitored against OSV/Snyk databases
2. **30-Day Patch SLA**: Critical CVEs patched within 30 days of disclosure
3. **Offline Patch Testing**: Isolated test environment for patch validation without production impact
4. **Minimal Attack Surface**: Disable unused features, strip unnecessary libraries

**Compliance Workflow:**
```
CVE Detected → SBOM Updated → Risk Assessment → Patch Applied → 
Regression Test → Documentation Update → Regulatory Notification (if required)
```

**Target Resolution:** Ongoing (CI/CD integration complete by Phase 1)

---

## Emerging Risks (Under Investigation)

| ID | Description | Status | Expected Resolution |
|----|-------------|--------|---------------------|
| EMRG-001 | Qualcomm Hexagon DSP toolchain licensing restrictions | Under legal review | M4 |
| EMRG-002 | Yocto Kirkstone LTS support timeline beyond 2026 | Monitoring upstream | M6 |
| EMRG-003 | NVIDIA Orin PCIe compatibility with QCS8550 root complex | HIL testing planned | M5 |
| EMRG-004 | DICOM TLS certificate rotation in air-gapped environments | Design review scheduled | M7 |

---

## Review and Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| System Architect | _____________ | _____________ | _______ |
| Quality Assurance | _____________ | _____________ | _______ |
| Regulatory Affairs | _____________ | _____________ | _______ |
| Project Manager | _____________ | _____________ | _______ |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05 | SDK Team | Initial release |

---

## Related Documents

- [Risk Mitigation and Validation](./04_Risk_Mitigation_and_Validation.md)
- [Safety Architecture Principles](../01_Regulatory_and_QMS/04_Safety_Architecture_Principles.md)
- [Performance Benchmarks and Tuning](./03_Performance_Benchmarks_and_Tuning.md) 


