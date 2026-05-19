# Safety Architecture Principles

## Overview

This document defines the core safety architecture principles for the Medical Device Platform SDK, ensuring compliance with IEC 62304 (Software Lifecycle), ISO 14971 (Risk Management), and IEC 61508 (Functional Safety). These principles guide all design decisions to achieve Class B/C medical device certification.

---

## 1. Core Safety Principles

### 1.1 Fail-Safe Defaults

**Principle**: All system states default to the safest possible configuration on boot, error, or undefined behavior.

**Implementation Requirements**:
- **Peripheral Initialization**: All GPIOs, PWM outputs, and communication interfaces initialize to high-impedance or safe-off states
- **AI Fallback**: If inference latency exceeds 50ms or confidence < 70%, system reverts to rule-based algorithms
- **Network Degradation**: Loss of network connectivity triggers local recording mode with DICOM queue buffering (minimum 4 hours)
- **Power Loss**: UPS-backed graceful shutdown with state preservation to non-volatile memory

**Verification**: Fault injection testing during HIL validation (see Section 10_Testing_Validation_and_QMS.md)

### 1.2 Defense in Depth

**Principle**: Multiple independent layers of protection prevent single-point failures from causing harm.

**Architecture Layers**:
```
┌─────────────────────────────────────────────────────┐
│ Layer 5: Application Safety Monitor                 │
│  - Runtime anomaly detection                        │
│  - Heartbeat watchdog supervision                   │
├─────────────────────────────────────────────────────┤
│ Layer 4: OS-Level Isolation                         │
│  - SELinux/AppArmor mandatory access control        │
│  - Cgroups resource limits                          │
│  - Namespaces process isolation                     │
├─────────────────────────────────────────────────────┤
│ Layer 3: Hypervisor Partition                       │
│  - Type-1 hypervisor (Jailhouse/Xen)                │
│  - Memory MMU isolation                             │
│  - Interrupt routing separation                     │
├─────────────────────────────────────────────────────┤
│ Layer 2: Hardware Safety MCU                        │
│  - Independent Cortex-R52 / AURIX TC3xx             │
│  - Hardware watchdog timer                          │
│  - Direct emergency stop circuit                    │
├─────────────────────────────────────────────────────┤
│ Layer 1: Physical Safety                            │
│  - Hardware E-stop button                           │
│  - Current/voltage monitoring                       │
│  - Thermal sensors                                  │
└─────────────────────────────────────────────────────┘
```

**Independence Requirement**: Each layer must use different implementation technologies to prevent common-cause failures.

### 1.3 Deterministic Behavior

**Principle**: Time-critical safety functions execute within bounded, predictable latency budgets.

**Latency Budget Table**:

| Function | Max Latency | Worst-Case Budget | Enforcement Mechanism | Safety Class |
|----------|-------------|-------------------|----------------------|--------------|
| Emergency Stop Propagation | ≤10 µs | 8 µs | Hardware interrupt (NMI) | Class C |
| Joint/Haptic Control Loop | ≤100 µs | 80 µs | Cortex-R52 + PREEMPT_RT | Class C |
| Video Frame Acquisition | ≤5 ms | 4 ms | V4L2 DMA-BUF + RT thread | Class B |
| AI Inference Pipeline | ≤30 ms | 25 ms | NPU priority queue | Class B |
| UI Response (Critical Alerts) | ≤100 ms | 80 ms | Qt High-Priority Queue | Class B |
| DICOM Network Send | ≤500 ms | 400 ms | Background thread pool | Class A |

**Verification Method**: Cycle-accurate tracing with Lauterbach Trace32 or equivalent during HIL testing.

### 1.4 Isolation by Design

**Principle**: Safety-critical and non-safety components are physically and logically isolated.

**Partition Strategy**:

| Partition | Components | Isolation Method | Communication |
|-----------|------------|------------------|---------------|
| **Safety-Critical** | Emergency stop, motor control, vital signs monitoring | Hypervisor partition + separate CPU cluster | Ring buffer IPC with CRC + sequence numbers |
| **Clinical Applications** | AI inference, image processing, diagnostics | Linux container + cgroups | Shared memory (read-only from safety) |
| **User Interface** | Display, touch input, audio | Separate process namespace | Message queue with timeout |
| **Connectivity** | DICOM, HL7, WiFi, Ethernet | Network namespace + firewall rules | Encrypted TLS tunnel |

**Memory Protection**: 
- MPU/MMU enforced no-execute (NX) and read-only (RO) regions
- Stack canaries and ASLR enabled for all user-space processes
- DMA buffers allocated from reserved CMA regions with IOMMU protection

---

## 2. Memory Safety & Resource Management

### 2.1 Memory Allocation Rules

**For Safety-Class C Components**:
- ❌ No dynamic allocation (`malloc`/`new`) after initialization phase
- ✅ Use static allocation or pre-allocated memory pools
- ✅ All buffers size-checked at compile-time where possible
- ✅ Stack usage analysis with 40% margin headroom

**For Safety-Class B Components**:
- ⚠️ Dynamic allocation permitted with strict limits:
  - Maximum allocation size: 1 MB per request
  - Pool-based allocators preferred (e.g., jemalloc with fixed pools)
  - All allocations must have timeout and retry logic
  - Memory leak detection via Valgrind integration in CI

**For Safety-Class A Components**:
- ✅ Standard allocation permitted
- ⚠️ Must implement graceful degradation on OOM conditions

### 2.2 Resource Quotas

| Resource | Safety Partition | Application Partition | UI Partition |
|----------|------------------|----------------------|--------------|
| CPU Cores | 2 dedicated (R52) | 6 cores (QCS8550) | 2 cores |
| Memory | 512 MB locked | 6 GB shared | 1 GB reserved |
| Storage I/O | 10 MB/s guaranteed | 200 MB/s burst | 50 MB/s |
| Network Bandwidth | N/A | 80% prioritized | 20% best-effort |
| GPU/NPU | N/A | 100% access | Compositor only |

**Enforcement**: Linux cgroups v2 + RT scheduler with SCHED_DEADLINE for time-critical threads.

---

## 3. Watchdog & Health Monitoring

### 3.1 Multi-Level Watchdog Architecture

```
Level 1: Hardware Watchdog (Independent IC)
  ├─ Timeout: 100 ms
  ├─ Trigger: System reset
  └─ Kicked by: Safety MCU only

Level 2: Safety MCU Watchdog
  ├─ Timeout: 50 ms
  ├─ Trigger: Safety partition restart
  └─ Kicked by: RTOS task every 10 ms

Level 3: Application Watchdog (Linux)
  ├─ Timeout: 500 ms
  ├─ Trigger: Application restart
  └─ Kicked by: RuntimeCore heartbeat thread

Level 4: Process-Level Watchdogs
  ├─ Timeout: Per-process (100 ms - 5 s)
  ├─ Trigger: Individual process restart
  └─ Kicked by: Each service health check
```

**Watchdog Feeding Rules**:
- Only kick watchdog if all health checks pass
- Implement exponential backoff on repeated failures
- Log all watchdog events to persistent storage with timestamp
- Never kick watchdog from interrupt context

### 3.2 Health Check Metrics

| Metric | Threshold | Action | Recovery |
|--------|-----------|--------|----------|
| CPU Temperature | > 85°C | Throttle NPU/GPU | Active cooling |
| CPU Temperature | > 95°C | Safe shutdown | Manual restart |
| Memory Usage | > 90% | Kill non-critical processes | Auto-reclaim |
| Disk Usage | > 85% | Stop recording, alert | Archive old data |
| Network Latency | > 200 ms | Switch to backup | Reconnect primary |
| AI Confidence | < 70% | Fallback to rules | Retrain model |
| Frame Drop Rate | > 5% | Reduce resolution | Check cable/driver |

---

## 4. Error Handling & Fault Tolerance

### 4.1 Error Classification

| Class | Description | Examples | Response | Documentation |
|-------|-------------|----------|----------|---------------|
| **Critical (Safe State)** | Immediate patient risk | E-stop pressed, motor stall, voltage spike | Hardware shutdown, log to FRAM | Incident report within 24h |
| **Major (Degraded Mode)** | Functionality loss | Network failure, AI timeout, sensor drift | Fallback mode, alert operator | CAPA within 5 days |
| **Minor (Self-Healing)** | Transient error | Packet loss, temporary OOM, soft lockup | Auto-retry, restart component | Logged for trend analysis |
| **Info (Cosmetic)** | No impact | UI glitch, timestamp skew | Continue operation | Debug log only |

### 4.2 Error Propagation Rules

1. **Upward Propagation**: Lower-level errors notify higher levels via event queue
2. **No Silent Failures**: All errors logged with severity, timestamp, context
3. **Timeout Enforcement**: All synchronous calls have maximum wait time
4. **Circuit Breaker Pattern**: After 3 consecutive failures, disable component for 60s

**Error Code Standard**:
```c
typedef enum {
    ERR_OK = 0,
    ERR_CRITICAL_HW_FAULT = 0x1000,
    ERR_CRITICAL_SAFETY_VIOLATION = 0x1001,
    ERR_MAJOR_RESOURCE_EXHAUSTED = 0x2000,
    ERR_MAJOR_TIMEOUT = 0x2001,
    ERR_MINOR_RETRYABLE = 0x3000,
    ERR_INFO_DEPRECATED = 0x4000
} SafetyErrorCode;
```

---

## 5. State Machine & Transition Safety

### 5.1 System State Diagram

```
[OFF] → [BOOT] → [SELF_TEST] → [STANDBY] ↔ [OPERATIONAL]
   ↑         ↓          ↓            ↓           ↓
   └────[SAFE_SHUTDOWN]←[FAULT]←───┴──────[EMERGENCY_STOP]
```

**State Definitions**:
- **OFF**: No power or hardware E-stop active
- **BOOT**: U-Boot + Kernel loading (watchdog inactive)
- **SELF_TEST**: POST, memory test, sensor calibration (≤30s)
- **STANDBY**: System ready, peripherals idle, safety monitors active
- **OPERATIONAL**: Normal clinical use with all functions enabled
- **FAULT**: Recoverable error detected, degraded mode active
- **SAFE_SHUTDOWN**: Controlled power-down with state preservation

### 5.2 Transition Guards

| Transition | Precondition | Validation | Timeout | Fallback |
|------------|--------------|------------|---------|----------|
| BOOT → SELF_TEST | Power good, voltages stable | HW init checksum | 5s | Retry 3x → OFF |
| SELF_TEST → STANDBY | All tests pass | CRC on test results | 30s | FAULT state |
| STANDBY → OPERATIONAL | Operator auth, no faults | Digital signature check | 10s | Remain STANDBY |
| OPERATIONAL → FAULT | Error threshold exceeded | Error classification | Immediate | Degrade gracefully |
| ANY → EMERGENCY_STOP | E-stop button pressed | Hardware interrupt | ≤10 µs | Cut power to actuators |
| FAULT → STANDBY | Error cleared, operator reset | Manual confirmation | 60s | SAFE_SHUTDOWN if fails |

**Cryptographic Verification**: State transitions require HMAC-signed commands from authorized sources.

---

## 6. Data Integrity & Audit Trail

### 6.1 Data Protection Mechanisms

| Data Type | Integrity Check | Encryption | Backup Strategy |
|-----------|-----------------|------------|-----------------|
| Patient Records | SHA-256 + digital signature | AES-256-GCM | RAID-1 + offsite sync |
| Configuration | CRC32 + version hash | AES-128-CBC | Dual-partition A/B |
| Logs/Audit | Append-only + Merkle tree | None (signed) | Write-once storage |
| AI Models | SHA-512 model hash | Optional | Version-controlled repository |
| Firmware | RSA-4096 secure boot | Encrypted payload | Recovery partition |

### 6.2 Audit Trail Requirements

**Immutable Logging**:
- All state transitions logged with timestamp (±1ms accuracy)
- Operator actions recorded with user ID and authentication method
- Error events include stack trace and register dump
- Logs stored in append-only format with cryptographic chaining

**Retention Policy**:
- Operational logs: 7 years (FDA requirement)
- Audit trail: Lifetime of device + 5 years
- Calibration records: Permanent

---

## 7. Security-Safety Integration

### 7.1 Threat Model for Safety

| Threat | Safety Impact | Mitigation |
|--------|---------------|------------|
| Unauthorized firmware update | Device malfunction | Secure boot + signed updates |
| Network intrusion | Data tampering, command injection | Firewall + zero-trust architecture |
| Denial of Service | Delayed response, timeout | Rate limiting + QoS prioritization |
| Credential theft | Unauthorized access | MFA + hardware security module |
| Supply chain attack | Compromised dependencies | SBOM + reproducible builds |

### 7.2 Security Boundaries

```
┌─────────────────────────────────────────────────────┐
│                  Trust Zone                         │
│  ┌─────────────┐    ┌─────────────┐                 │
│  │ Safety MCU  │◄──►│ Secure Encl │ (HSM/TEE)       │
│  └─────────────┘    └─────────────┘                 │
│         ▲                   ▲                        │
│         │ Signed Commands   │ Cryptographic Ops     │
│         ▼                   ▼                        │
│  ┌─────────────────────────────────────┐            │
│  │      Hypervisor (Trusted Base)      │            │
│  └─────────────────────────────────────┘            │
│         │                   │                        │
│    ┌────▼────┐         ┌────▼────┐                  │
│    │ Linux   │         │  RTOS   │                  │
│    │ (Rich)  │         │(Safety) │                  │
│    └─────────┘         └─────────┘                  │
└─────────────────────────────────────────────────────┘
```

---

## 8. Verification & Validation Requirements

### 8.1 Safety Principle Verification Matrix

| Principle | Verification Method | Test Coverage | Acceptance Criteria |
|-----------|--------------------|---------------|---------------------|
| Fail-Safe Defaults | Fault injection testing | 100% of fault scenarios | System enters safe state within budget |
| Defense in Depth | Penetration testing + FMEA | All 5 layers tested independently | Single fault cannot bypass >1 layer |
| Deterministic Latency | Cycle-accurate tracing | 1000 iterations per function | 99.99% of executions within budget |
| Isolation | Memory corruption tests | All partition boundaries | No cross-partition memory access |
| Watchdog | Intentional hang injection | All watchdog levels | System recovers within 2x timeout |
| Error Handling | Chaos engineering | All error classes | No silent failures, proper escalation |
| State Machine | Model checking (TLA+) | All state transitions | No deadlocks, all guards validated |

### 8.2 Tool Qualification

Per IEC 62304 Section 7.3.2, tools used in safety-critical development must be qualified:

| Tool Category | Examples | Qualification Level | Required Evidence |
|---------------|----------|---------------------|-------------------|
| Compiler | GCC, Clang | Class 2 (verified output) | Test suite + version control |
| Static Analyzer | Coverity, Cppcheck | Class 2 | Configuration audit + false positive analysis |
| Build System | CMake, Yocto | Class 1 (no direct impact) | Reproducible build verification |
| Testing Framework | GoogleTest, Catch2 | Class 2 | Coverage reports + mutation testing |
| CI/CD Pipeline | Jenkins, GitLab CI | Class 1 | Audit trail + access control |

---

## 9. Documentation & Traceability

### 9.1 Required Artifacts

- [ ] Safety Architecture Specification (this document)
- [ ] Hazard Analysis Report (ISO 14971)
- [ ] FMEA/FMECA Reports
- [ ] Software Safety Classification Justification
- [ ] Traceability Matrix (Requirements ↔ Design ↔ Tests)
- [ ] Tool Qualification Plans & Reports
- [ ] Verification Test Protocols & Results
- [ ] Residual Risk Assessment

### 9.2 Change Control

All modifications to safety architecture require:
1. Impact analysis on hazard controls
2. Re-verification of affected components
3. Update to traceability matrix
4. Regulatory assessment (if classification changes)
5. Approval by Safety Review Board

---

## 10. References

- IEC 62304:2006 + AMD1:2015 - Medical device software lifecycle
- ISO 14971:2019 - Risk management for medical devices
- IEC 61508:2010 - Functional safety of electrical/electronic systems
- FDA Guidance: Cybersecurity for Networked Medical Devices (2023)
- EU MDR 2017/745 - Annex I GSPRs
- UL 2900-2-1 - Cybersecurity for healthcare technology
- AAMI TIR57:2016 - Principles for medical device security risk management

---

**Document Control**:
- Version: 2.0
- Status: Approved for Implementation
- Next Review: After Phase 3 (M9) milestone
- Owner: Chief Safety Architect
