# Hypervisor Strategy for Mixed-Criticality Systems

## 1. Overview
This document defines the hypervisor strategy for running mixed-criticality workloads on the Medical Device Platform SDK. The architecture supports simultaneous execution of:
- **Safety-Critical RTOS** (IEC 62304 Class C) - Patient monitoring, therapy delivery
- **Linux OS** (IEC 62304 Class B) - UI, networking, data management
- **Non-Critical Services** - Diagnostics, logging, updates

Compliant with IEC 62304 isolation requirements and FDA cybersecurity guidance.

## 2. Architecture Selection

### 2.1 Hypervisor Type: Type-1 (Bare Metal)
**Selected**: Qualcomm Cloud AI 100 Hypervisor (based on ARM Trusted Firmware-A)

**Rationale:**
- Direct hardware access for real-time VMs
- Minimal overhead (< 2% performance penalty)
- Hardware-enforced isolation via ARM Virtualization Extensions
- Certified safety features (ISO 26262 ASIL-B capable)

**Rejected Alternatives:**
- Type-2 (Hosted): KVM, VirtualBox - Too much overhead, not deterministic
- Container-based: Docker, LXC - Insufficient isolation for Class C software

### 2.2 System Architecture Diagram
```
+-----------------------------------------------------------------------+
|                    Application Layer                                  |
|  +------------------+  +------------------+  +---------------------+  |
|  |  Medical App     |  |  Linux Services  |  |  Diagnostic Tools   |  |
|  |  (Class C RTOS)  |  |  (Class B Linux) |  |  (Non-Critical)     |  |
|  +------------------+  +------------------+  +---------------------+  |
+-----------------------------------------------------------------------+
|                    Guest Operating Systems                            |
|  +------------------+  +------------------+  +---------------------+  |
|  |   FreeRTOS /     |  |   Yocto Linux    |  |   Alpine Linux      |  |
|  |   Zephyr RTOS    |  |   (PREEMPT_RT)   |  |                     |  |
|  +------------------+  +------------------+  +---------------------+  |
+-----------------------------------------------------------------------+
|                    Type-1 Hypervisor (EL2)                            |
|  +-----------------------------------------------------------------+  |
|  |  ARM Trusted Firmware-A with Hypervisor Extensions              |  |
|  |  - VM Scheduling (Priority-based)                               |  |
|  |  - Memory Virtualization (Stage-2 MMU)                          |  |
|  |  - Interrupt Virtualization (GICv3)                             |  |
|  |  - Device Passthrough (IOMMU)                                   |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
|                    Hardware Layer (QCS8550)                           |
|  +---------+  +---------+  +---------+  +---------+  +-------------+  |
|  | CPU     |  |  GPU    |  |  DSP    |  |  IOMMU  |  |  Peripherals|  |
|  | Cores   |  |         |  | (Hexagon)|  | (SMMU) |  |  (UART,SPI) |  |
|  | 0-1     |  |         |  |         |  |         |  |             |  |
|  +---------+  +---------+  +---------+  +---------+  +-------------+  |
+-----------------------------------------------------------------------+
```

## 3. VM Partitioning Strategy

### 3.1 CPU Allocation
| VM | Purpose | CPU Cores | Priority | Scheduler |
|----|---------|-----------|----------|-----------|
| VM0 | Safety-Critical RTOS | Core 0 (dedicated) | Real-time (highest) | Static partition |
| VM1 | Linux General Purpose | Cores 1-3 | Best-effort | CFS with RT boost |
| VM2 | Diagnostics/Updates | Core 4 (time-sliced) | Low priority | Background |

**Isolation Guarantees:**
- Core 0: Exclusively assigned to VM0, no time-sharing
- Cache partitioning: LLC (Last Level Cache) ways allocated per VM
- Memory bandwidth: QoS limits prevent VM1/VM2 from starving VM0

### 3.2 Memory Allocation
| VM | RAM Size | Type | Protection |
|----|----------|------|------------|
| VM0 | 512 MB | Locked, non-swappable | Stage-2 MMU, read-only hypervisor mappings |
| VM1 | 2 GB | Standard | Stage-2 MMU, CMA reserved for DMA |
| VM2 | 256 MB | Standard | Stage-2 MMU, limited DMA |

**Memory Safety Features:**
- No shared memory between VMs (except explicit IPC channels)
- Memory scrubbing on VM teardown (prevent data leakage)
- ECC protection: Enabled on all DRAM regions

### 3.3 Device Assignment
| Device | Assigned To | Method | Rationale |
|--------|-------------|--------|-----------|
| Camera ISP | VM0 | Direct passthrough | Deterministic capture timing |
| AI Accelerator | VM0 | Direct passthrough | Low-latency inference |
| Ethernet | VM1 | VirtIO paravirtualized | Shared network stack OK |
| USB | VM1 | Direct passthrough | Linux has mature USB support |
| UART (Debug) | VM2 | Emulated | Non-critical diagnostics |
| Watchdog | VM0 | Direct access | Safety-critical timeout monitoring |

**IOMMU Configuration:**
- Each VM has isolated IOMMU domain
- DMA addresses translated via Stage-2 page tables
- Fault handling: VM-specific error recovery, no cross-VM impact

## 4. Inter-VM Communication (IPC)

### 4.1 Communication Channels
| Channel Type | Protocol | Use Case | Latency Target |
|--------------|----------|----------|----------------|
| Shared Memory | RPMsg + VirtIO | High-throughput data (images) | < 100 µs |
| VirtQueue | VirtIO-RPC | Function calls (Linux → RTOS) | < 50 µs |
| Signaling | SGI (Software Generated Interrupt) | Event notification | < 10 µs |
| Serial | VirtIO-Console | Debug/logging | < 1 ms |

### 4.2 Security Controls
- **Authentication**: Each IPC channel has unique UUID, validated at connection
- **Authorization**: Access control matrix enforced by hypervisor
- **Data Integrity**: CRC32 checksums on all shared memory transfers
- **Encryption**: Optional AES-128 for sensitive patient data (VM0 ↔ VM1)

### 4.3 Example: Camera Data Flow
```
[Camera Sensor] 
      ↓ (MIPI CSI-2)
[ISP in VM0] → Process image (Class C algorithm)
      ↓ (Shared Memory via RPMsg)
[AI Model in VM0] → Inference (tumor detection)
      ↓ (VirtIO-RPC)
[UI in VM1] → Display results to clinician
      ↓ (Network)
[PACS Server] → Store DICOM image
```

## 5. Safety & Security Isolation

### 5.1 Fault Containment Regions (FCRs)
| FCR | Components | Failure Mode | Containment Strategy |
|-----|------------|--------------|----------------------|
| FCR-0 | VM0 (RTOS) | Software crash | Watchdog reset VM0 only, VM1 continues |
| FCR-1 | VM1 (Linux) | Kernel panic | Hypervisor captures dump, VM0 unaffected |
| FCR-2 | VM2 (Diagnostics) | Hang | Kill VM2, auto-restart without affecting others |
| FCR-3 | Hypervisor | Corruption | Hardware watchdog, full system reboot |

### 5.2 Security Boundaries
```
+-------------------+     +-------------------+     +-------------------+
|       VM0         |     |       VM1         |     |       VM2         |
|  (Trust Level 3)  |     |  (Trust Level 2)  |     |  (Trust Level 1)  |
|                   |     |                   |     |                   |
|  - Patient Data   |     |  - Network Stack  |     |  - Update Agent   |
|  - Therapy Control|     |  - Database       |     |  - Log Collector  |
|  - Crypto Keys    |     |  - User Auth      |     |  - Telemetry      |
|                   |     |                   |     |                   |
|  [No outbound net]|     |  [Firewalled]     |     |  [Outbound only]  |
+-------------------+     +-------------------+     +-------------------+
         ↓                        ↓                        ↓
+-----------------------------------------------------------------------+
|                    Hypervisor Security Monitor                        |
|  - Enforce access policies                                            |
|  - Detect anomalous behavior                                          |
|  - Log security events to secure storage                              |
+-----------------------------------------------------------------------+
```

### 5.3 Attack Surface Reduction
- **VM0**: No network stack, no USB, minimal drivers
- **VM1**: SELinux enforcing, firewall rules, read-only rootfs
- **VM2**: Seccomp-bpf, capability dropping, namespace isolation
- **Hypervisor**: Minimal codebase (< 50 KLOC), formally verified components

## 6. Boot & Lifecycle Management

### 6.1 Boot Sequence
1. **Secure Boot** (BL1-BL2): Verify hypervisor signature
2. **Hypervisor Init** (BL31): Initialize EL2, set up stage-2 MMU
3. **VM0 Launch**: Load RTOS image, start on Core 0
4. **VM1 Launch**: Load Linux kernel, start on Cores 1-3
5. **VM2 Launch** (optional): Load diagnostic container

**Boot Time Budget:**
- Hypervisor initialization: < 200 ms
- VM0 boot: < 500 ms (critical path)
- VM1 boot: < 2 s (concurrent with VM0 operation)
- **Total to medical readiness**: < 1 s

### 6.2 Firmware Updates
- **Hypervisor**: A/B partition scheme, rollback on failure
- **VM Images**: Signed updates, verified before installation
- **Rollback Protection**: Anti-rollback counter in eFuse

### 6.3 Runtime Monitoring
- **Health Checks**: Hypervisor polls VM heartbeats every 10 ms
- **Anomaly Detection**: ML-based detection of abnormal VM behavior
- **Recovery Actions**: 
  - VM crash: Auto-restart (max 3 attempts)
  - Repeated failures: Alert clinician, enter safe mode

## 7. Verification & Validation

### 7.1 Test Cases
1. **TC-HY-01**: Verify VM isolation (no memory corruption across VMs)
2. **TC-HY-02**: Measure IPC latency (< 100 µs for shared memory)
3. **TC-HY-03**: Inject fault in VM1, verify VM0 continues operating
4. **TC-HY-04**: Verify hypervisor enforces device access policies
5. **TC-HY-05**: Measure boot time to medical readiness (< 1 s)
6. **TC-HY-06**: Validate secure update mechanism (reject unsigned images)

### 7.2 Performance Benchmarks
| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Hypervisor overhead | < 2% | SPEC CPU2017 comparison |
| Context switch latency | < 5 µs | Cycle-accurate tracing |
| IPC throughput | > 500 MB/s | dd benchmark over shared memory |
| Interrupt latency (VM0) | < 50 µs | Oscilloscope measurement |

### 7.3 Tool Qualification
- **Hypervisor Build**: Yocto Project (qualified toolchain)
- **Testing**: Custom test harness (IEC 62304 qualified)
- **Coverage Analysis**: gcov/lcov (target: 100% MC/DC for hypervisor)

## 8. Documentation & Traceability
- **Requirements**: SYS-REQ-HY-001 through SYS-REQ-HY-020
- **Risk Controls**: RC-SAF-005 (VM isolation), RC-CYB-003 (secure IPC)
- **Test Reports**: TR-HY-001 (Hypervisor Validation Report)
- **Safety Case**: SC-HY-001 (Argument for adequate isolation)

---
**Document Control**
- Version: 1.0
- Status: Released
- Author: System Architecture Team
- Review Date: 2024-Q2
