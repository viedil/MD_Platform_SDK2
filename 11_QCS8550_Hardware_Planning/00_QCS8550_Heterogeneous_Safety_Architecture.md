# QCS8550 Heterogeneous Computing Architecture for Medical Device Safety

## Executive Summary

The Qualcomm QCS8550 (Automotive/Industrial variant of Snapdragon 8 Gen 2) provides a sophisticated heterogeneous computing platform ideal for high-performance medical devices requiring both intensive signal processing and strict safety guarantees. This document outlines the strategy for leveraging the QCS8550's multi-core, multi-domain architecture to achieve **code isolation**, **fault containment**, and **regulatory compliance** (IEC 62304 Class C, ISO 26262 ASIL-D principles).

## 1. QCS8550 Hardware Architecture Overview

### 1.1 Core Complexes

The QCS8550 features a "Prime + Performance + Efficiency" CPU configuration:

- **Prime Core**: 1x Cortex-X3 (High performance, single-threaded critical tasks)
- **Performance Cores**: 4x Cortex-A715 (Balanced processing for algorithms)
- **Efficiency Cores**: 3x Cortex-A510 (Background services, low-power monitoring)
- **DSP Subsystem**: Hexagon Tensor Processor (HTP) for AI/ML inference
- **GPU**: Adreno GPU for visualization and parallel processing
- **NPU**: Dedicated Neural Processing Unit for deep learning
- **ISP**: Image Signal Processor for camera/sensor input
- **HMP (Heterogeneous Multi-Processing)**: Hardware support for asymmetric workloads

### 1.2 Memory & Security Domains

- **TrustZone**: Hardware-enforced separation between Secure World (TEE) and Normal World (REE)
- **Hypervisor Support**: Type-1 Hypervisor capability for virtualization-based isolation
- **Memory Protection Units (MPU)**: Per-core memory access control
- **Shared Memory Regions**: Carefully managed IPC buffers with hardware locks

## 2. Code Isolation Strategy via Heterogeneous Structure

### 2.1 Safety Domain Mapping (The "Safety Island" Concept)

| Safety Class              | Function Type                                                         | Target Compute Unit                           | Rationale                                                                                    |
|:------------------------- |:--------------------------------------------------------------------- |:--------------------------------------------- |:-------------------------------------------------------------------------------------------- |
| **Class C (High Risk)**   | Alarm management, Patient safety limits, Watchdog, Emergency shutdown | **Prime Core (Cortex-X3)** pinned exclusively | Highest single-thread performance for deterministic response; isolated from noisy neighbors. |
| **Class B (Medium Risk)** | Signal processing, Clinical algorithms, Data validation               | **Performance Cores (4x A715)**               | Parallel processing capability; bounded by resource limits.                                  |
| **Class A (Low Risk)**    | UI rendering, Logging, Network connectivity, File I/O                 | **Efficiency Cores (3x A510)**                | Cost-effective handling of non-critical background tasks.                                    |
| **SOUP / Unverified**     | AI Inference, Third-party libraries, Complex math                     | **Hexagon DSP / NPU**                         | Hardware sandboxing; results validated by Class C core before use.                           |
| **Cryptographic / Auth**  | Key storage, Digital signatures, Secure boot                          | **TrustZone (TEE)**                           | Hardware-rooted security; inaccessible to main OS.                                           |

### 2.2 Implementation Mechanisms

#### A. CPU Affinity & Pinning (Linux `sched_setaffinity`)

Prevent context switching jitter and cross-contamination by pinning threads to specific cores.

```c
// Example: Pin Safety Critical Thread to Prime Core (Core 0)
cpu_set_t mask;
CPU_ZERO(&mask);
CPU_SET(0, &mask); // Assuming Core 0 is the Prime Cortex-X3
pthread_setaffinity_np(safety_thread, sizeof(mask), &mask);
```

*Benefit:* Ensures the safety monitor never waits for a non-critical task to release the core.

#### B. Memory Partitioning

- **Private Heaps:** Allocate separate memory pools for each safety class.
- **MPU Configuration:** Configure Memory Protection Units to prevent Class A/B code from writing to Class C data segments.
- **Shared Memory Guards:** Use hardware semaphores for IPC buffers; implement "double-buffering" to prevent race conditions.

#### C. Hypervisor-Based Virtualization (Optional but Recommended for Highest Safety)

Run two distinct Guest OS instances:

1. **Safety VM (Real-Time OS or Hardened Linux):** Runs on Prime Core + dedicated memory. Handles Class C logic.
2. **Rich VM (Standard Linux/Android):** Runs on remaining cores. Handles UI, Connectivity, AI.
   *Benefit:* A kernel panic in the Rich VM cannot crash the Safety VM.

## 3. Core Distribution Strategy for Determinism

Distributing tasks across specific core clusters is the primary mechanism to achieve **temporal determinism** on the QCS8550. This prevents "noisy neighbor" effects where non-critical workloads interfere with safety-critical timing.

### 3.1 Physical Core Assignment Matrix

| Core Cluster          | Architecture        | Assigned Safety Class  | Workload Types                                                   | Isolation Mechanism                                                        |
|:--------------------- |:------------------- |:---------------------- |:---------------------------------------------------------------- |:-------------------------------------------------------------------------- |
| **Prime Core**        | Cortex-X3 (1x)      | **Class C** (Critical) | Alarm Logic, Watchdog, Safety Limits, Emergency Shutdown         | **Hard Isolation**: Reserved via `isolcpus`, No OS Scheduler, Max Priority |
| **Performance Cores** | Cortex-A715 (4x)    | **Class B** (Major)    | Signal Processing, AI Inference Orchestration, Patient Data Mgmt | **Soft Isolation**: Real-time Scheduler (`SCHED_FIFO`), CPU Affinity Mask  |
| **Efficiency Cores**  | Cortex-A510 (3x)    | **Class A** (Minor)    | UI/UX, Network Stack, Logging, File I/O, OTA Updates             | **Best Effort**: Standard Linux Scheduler (`SCHED_OTHER`), Cgroups Limits  |
| **DSP / NPU**         | Hexagon / AI Engine | **SOUP** (Unverified)  | Raw FFT, Noise Filtering, Neural Net Weights                     | **Hardware Sandbox**: Memory protected, Output validated by Class C        |

### 3.2 Determinism Enforcement Techniques

#### A. CPU Isolation (`isolcpus`)

The Prime Core (Cortex-X3) must be isolated from the general Linux scheduler to prevent context switches from interrupting critical loops.

```bash
# Kernel boot argument example
isolcpus=0 nohz_full=0 rcu_nocbs=0
# Where Core 0 is the Cortex-X3 reserved for Class C
```

#### B. Cache & Memory Partitioning (MPU/PMU)

- **L3 Cache Allocation**: Use Qualcomm's Memory Partitioning and Monitoring (MPAM) if available, or reserve LLC ways for the Prime Core to prevent cache thrashing by A715/A510 cores.
- **Memory Zones**: Allocate a dedicated "CMA" (Contiguous Memory Allocator) region for Class C data to ensure physical continuity and avoid TLB misses.

#### C. Interrupt Affinity

Critical hardware interrupts (e.g., Hardware Watchdog, Emergency GPIO, ADC overrun) must be routed **exclusively** to the Prime Core.

```bash
# Example: Route IRQ 45 (Safety GPIO) to Core 0 only
echo 1 > /proc/irq/45/smp_affinity_list
```

#### D. Bus Arbitration & QoS

Configure the System NoC (Network on Chip) Quality of Service (QoS) registers to prioritize traffic from the Prime Core over DMA transfers from WiFi/Modem subsystems, ensuring memory access latency bounds are met.

### 3.3 Worst-Case Execution Time (WCET) Analysis

By fixing the core assignment, we reduce the variables in WCET analysis:

1. **Context Switch Overhead**: Eliminated for Class C (runs bare-metal or locked thread).
2. **Cache Miss Penalty**: Bounded via partitioning.
3. **Interrupt Latency**: Minimized by disabling non-critical interrupts on the Prime Core.

> **Risk Control**: If the Prime Core utilization exceeds 80% (measured over 100ms window), the System Monitor (Class B) must shed non-critical load (kill UI/Network processes) immediately.

## 4. Safety-Related Scenarios & Mitigations

### Scenario 1: Runaway Non-Critical Process (UI/Network)

- **Risk:** A network driver loop consumes 100% CPU, starving the alarm system.
- **Mitigation:**
  - **Core Isolation:** Network stack runs on Efficiency Cores only.
  - **Cgroups:** Enforce strict CPU bandwidth limits (e.g., max 80% of Efficiency cluster).
  - **Hardware Watchdog:** Independent timer monitored only by Prime Core. If not kicked, hardware resets the specific subsystem or entire SoC.

### Scenario 2: Erroneous AI/DSP Output

- **Risk:** NPU infers a false "normal" state despite raw data indicating distress.
- **Mitigation:**
  - **V-Model Validation Gate:** The Prime Core (Class C) receives *both* raw sensor data and NPU results.
  - **Plausibility Check:** Class C code performs a simplified, deterministic range check. If NPU output contradicts raw data physics, NPU output is discarded, and "Sensor Fault" alarm is raised.
  - **Sandboxing:** NPU runs in a separate process with no direct hardware control privileges.

### Scenario 3: Memory Corruption in Shared Buffers

- **Risk:** A bug in the visualization module overwrites acquisition data.
- **Mitigation:**
  - **Read-Only Mapping:** Map shared data regions as Read-Only for consumers.
  - **Sequence Numbers & CRC:** Every IPC packet includes a sequence ID and CRC32. Mismatched IDs trigger immediate channel shutdown.
  - **Guard Pages:** Insert unmapped memory pages between buffers to catch buffer overflows instantly (SIGSEGV).

### Scenario 4: Thermal Throttling affecting Real-Time Performance

- **Risk:** SoC overheats due to AI load, throttling the Prime Core and delaying alarms.
- **Mitigation:**
  - **Thermal Zones:** Define distinct thermal policies. Critical cores have higher throttling thresholds.
  - **Load Shedding:** Monitor thermal sensors in Class C code. If temperature rises, Class C logic commands the shutdown of Class A/B workloads (UI, Network) to preserve cooling headroom for safety functions.

### Scenario 5: Power Failure / Brownout

- **Risk:** Sudden power loss corrupts patient data or leaves device in undefined state.
- **Mitigation:**
  - **PMIC Integration:** Leverage QCS8550 PMIC interrupts for early warning.
  - **Secure Save:** Prime Core halts all other cores via IPC upon power warning, flushes critical state to FRAM/EEPROM (non-volatile), then initiates graceful shutdown.

## 4. Inter-Process Communication (IPC) Architecture

Safe communication between domains is critical. We utilize a **Message-Passing** architecture rather than shared global variables.

### 4.1 IPC Channels

| Channel Name   | Source Domain       | Dest Domain         | Protocol                 | Safety Check               |
|:-------------- |:------------------- |:------------------- |:------------------------ |:-------------------------- |
| `raw_data_tx`  | Acquisition (A715)  | Processing (A715)   | Shared Mem Ring Buffer   | CRC + Sequence ID          |
| `alarm_req`    | Processing (A715)   | Safety Monitor (X3) | Message Queue (Priority) | Double-Sample Verification |
| `ai_result`    | NPU/DSP             | Safety Monitor (X3) | Shared Mem (Read-Only)   | Plausibility Range Check   |
| `shutdown_cmd` | Safety Monitor (X3) | All Domains         | Broadcast Interrupt      | Hardware Line Assertion    |

### 4.2 Timeout & Heartbeat Mechanism

- **Heartbeat:** Every domain must publish a heartbeat to the Safety Monitor (Prime Core) every 10ms.
- **Timeout Action:** If a domain misses 3 heartbeats:
  1. Safety Monitor logs "Domain Fault".
  2. Safety Monitor isolates the faulty domain (kills process/restarts VM).
  3. If critical domain (Acquisition), transition device to Safe Mode.

## 5. Development & Verification Workflow

### 5.1 Compilation & Linking

- **Separate Binaries:** Compile Safety (Class C) and Non-Safety (Class A/B) code into separate executables/libraries.
- **Compiler Flags:** Use `-fstack-protector-strong`, `-D_FORTIFY_SOURCE=2` for all; disable optimizations that might reorder safety-critical checks (`-O2` vs `-O3` analysis).

### 5.2 Static Analysis

- Run MISRA C/C++ checkers specifically on the Prime Core codebase.
- Verify no dynamic memory allocation (`malloc`/`free`) in Class C paths after initialization.

### 5.3 Fault Injection Testing

- **CPU Lockup:** Simulate 100% load on Efficiency cores; verify Prime Core latency remains < 2ms.
- **Memory Bit-Flip:** Inject errors into shared memory; verify CRC detection and rejection.
- **IPC Delay:** Artificially delay messages; verify timeout handlers trigger correctly.

## 6. Conclusion

The QCS8550's heterogeneous architecture is not just a performance feature but a **safety mechanism**. By strictly mapping software safety classes to hardware domains (Prime Core for Class C, DSP for SOUP, TrustZone for Security), we create a "Defense in Depth" posture. This approach ensures that even if complex, unverified components (AI, Network) fail catastrophically, the hardware-isolated Safety Monitor retains control to protect the patient.

## Appendix: QCS8550 Specific Register References

*(To be populated with specific Qualcomm BSP documentation references during implementation)*

- `APSS_WDT_BASE`: Application Processor Subsystem Watchdog
- `MPU_CONFIG_REGION_X`: Memory Protection Unit configurations
- `TZASC_CTRL`: TrustZone Address Space Controller

+++ 11_QCS8550_Hardware_Planning/00_QCS8550_Heterogeneous_Safety_Architecture.md (修改后)

# QCS8550 Heterogeneous Computing Architecture for Medical Device Safety

## Executive Summary

The Qualcomm QCS8550 (Automotive/Industrial variant of Snapdragon 8 Gen 2) provides a sophisticated heterogeneous computing platform ideal for high-performance medical devices requiring both intensive signal processing and strict safety guarantees. This document outlines the strategy for leveraging the QCS8550's multi-core, multi-domain architecture to achieve **code isolation**, **fault containment**, and **regulatory compliance** (IEC 62304 Class C, ISO 26262 ASIL-D principles).

## 1. QCS8550 Hardware Architecture Overview

### 1.1 Core Complexes

The QCS8550 features a "Prime + Performance + Efficiency" CPU configuration:

- **Prime Core**: 1x Cortex-X3 (High performance, single-threaded critical tasks)
- **Performance Cores**: 4x Cortex-A715 (Balanced processing for algorithms)
- **Efficiency Cores**: 3x Cortex-A510 (Background services, low-power monitoring)
- **DSP Subsystem**: Hexagon Tensor Processor (HTP) for AI/ML inference
- **GPU**: Adreno GPU for visualization and parallel processing
- **NPU**: Dedicated Neural Processing Unit for deep learning
- **ISP**: Image Signal Processor for camera/sensor input
- **HMP (Heterogeneous Multi-Processing)**: Hardware support for asymmetric workloads

### 1.2 Memory & Security Domains

- **TrustZone**: Hardware-enforced separation between Secure World (TEE) and Normal World (REE)
- **Hypervisor Support**: Type-1 Hypervisor capability for virtualization-based isolation
- **Memory Protection Units (MPU)**: Per-core memory access control
- **Shared Memory Regions**: Carefully managed IPC buffers with hardware locks

## 2. Code Isolation Strategy via Heterogeneous Structure

### 2.1 Safety Domain Mapping (The "Safety Island" Concept)

| Safety Class              | Function Type                                                         | Target Compute Unit                           | Rationale                                                                                    |
|:------------------------- |:--------------------------------------------------------------------- |:--------------------------------------------- |:-------------------------------------------------------------------------------------------- |
| **Class C (High Risk)**   | Alarm management, Patient safety limits, Watchdog, Emergency shutdown | **Prime Core (Cortex-X3)** pinned exclusively | Highest single-thread performance for deterministic response; isolated from noisy neighbors. |
| **Class B (Medium Risk)** | Signal processing, Clinical algorithms, Data validation               | **Performance Cores (4x A715)**               | Parallel processing capability; bounded by resource limits.                                  |
| **Class A (Low Risk)**    | UI rendering, Logging, Network connectivity, File I/O                 | **Efficiency Cores (3x A510)**                | Cost-effective handling of non-critical background tasks.                                    |
| **SOUP / Unverified**     | AI Inference, Third-party libraries, Complex math                     | **Hexagon DSP / NPU**                         | Hardware sandboxing; results validated by Class C core before use.                           |
| **Cryptographic / Auth**  | Key storage, Digital signatures, Secure boot                          | **TrustZone (TEE)**                           | Hardware-rooted security; inaccessible to main OS.                                           |

### 2.2 Implementation Mechanisms

#### A. CPU Affinity & Pinning (Linux `sched_setaffinity`)

Prevent context switching jitter and cross-contamination by pinning threads to specific cores.

```c
// Example: Pin Safety Critical Thread to Prime Core (Core 0)
cpu_set_t mask;
CPU_ZERO(&mask);
CPU_SET(0, &mask); // Assuming Core 0 is the Prime Cortex-X3
pthread_setaffinity_np(safety_thread, sizeof(mask), &mask);
```

*Benefit:* Ensures the safety monitor never waits for a non-critical task to release the core.

#### B. Memory Partitioning

- **Private Heaps:** Allocate separate memory pools for each safety class.
- **MPU Configuration:** Configure Memory Protection Units to prevent Class A/B code from writing to Class C data segments.
- **Shared Memory Guards:** Use hardware semaphores for IPC buffers; implement "double-buffering" to prevent race conditions.

#### C. Hypervisor-Based Virtualization (Optional but Recommended for Highest Safety)

Run two distinct Guest OS instances:

1. **Safety VM (Real-Time OS or Hardened Linux):** Runs on Prime Core + dedicated memory. Handles Class C logic.
2. **Rich VM (Standard Linux/Android):** Runs on remaining cores. Handles UI, Connectivity, AI.
   *Benefit:* A kernel panic in the Rich VM cannot crash the Safety VM.

## 3. Core Distribution Strategy for Determinism

Distributing tasks across specific core clusters is the primary mechanism to achieve **temporal determinism** on the QCS8550. This prevents "noisy neighbor" effects where non-critical workloads interfere with safety-critical timing.

### 3.1 Physical Core Assignment Matrix

| Core Cluster          | Architecture        | Assigned Safety Class  | Workload Types                                                   | Isolation Mechanism                                                        |
|:--------------------- |:------------------- |:---------------------- |:---------------------------------------------------------------- |:-------------------------------------------------------------------------- |
| **Prime Core**        | Cortex-X3 (1x)      | **Class C** (Critical) | Alarm Logic, Watchdog, Safety Limits, Emergency Shutdown         | **Hard Isolation**: Reserved via `isolcpus`, No OS Scheduler, Max Priority |
| **Performance Cores** | Cortex-A715 (4x)    | **Class B** (Major)    | Signal Processing, AI Inference Orchestration, Patient Data Mgmt | **Soft Isolation**: Real-time Scheduler (`SCHED_FIFO`), CPU Affinity Mask  |
| **Efficiency Cores**  | Cortex-A510 (3x)    | **Class A** (Minor)    | UI/UX, Network Stack, Logging, File I/O, OTA Updates             | **Best Effort**: Standard Linux Scheduler (`SCHED_OTHER`), Cgroups Limits  |
| **DSP / NPU**         | Hexagon / AI Engine | **SOUP** (Unverified)  | Raw FFT, Noise Filtering, Neural Net Weights                     | **Hardware Sandbox**: Memory protected, Output validated by Class C        |

### 3.2 Determinism Enforcement Techniques

#### A. CPU Isolation (`isolcpus`)

The Prime Core (Cortex-X3) must be isolated from the general Linux scheduler to prevent context switches from interrupting critical loops.

```bash
# Kernel boot argument example
isolcpus=0 nohz_full=0 rcu_nocbs=0
# Where Core 0 is the Cortex-X3 reserved for Class C
```

#### B. Cache & Memory Partitioning (MPU/PMU)

- **L3 Cache Allocation**: Use Qualcomm's Memory Partitioning and Monitoring (MPAM) if available, or reserve LLC ways for the Prime Core to prevent cache thrashing by A715/A510 cores.
- **Memory Zones**: Allocate a dedicated "CMA" (Contiguous Memory Allocator) region for Class C data to ensure physical continuity and avoid TLB misses.

#### C. Interrupt Affinity

Critical hardware interrupts (e.g., Hardware Watchdog, Emergency GPIO, ADC overrun) must be routed **exclusively** to the Prime Core.

```bash
# Example: Route IRQ 45 (Safety GPIO) to Core 0 only
echo 1 > /proc/irq/45/smp_affinity_list
```

#### D. Bus Arbitration & QoS

Configure the System NoC (Network on Chip) Quality of Service (QoS) registers to prioritize traffic from the Prime Core over DMA transfers from WiFi/Modem subsystems, ensuring memory access latency bounds are met.

### 3.3 Worst-Case Execution Time (WCET) Analysis

By fixing the core assignment, we reduce the variables in WCET analysis:

1. **Context Switch Overhead**: Eliminated for Class C (runs bare-metal or locked thread).
2. **Cache Miss Penalty**: Bounded via partitioning.
3. **Interrupt Latency**: Minimized by disabling non-critical interrupts on the Prime Core.

> **Risk Control**: If the Prime Core utilization exceeds 80% (measured over 100ms window), the System Monitor (Class B) must shed non-critical load (kill UI/Network processes) immediately.

## 4. Safety-Related Scenarios & Mitigations

### Scenario 1: Runaway Non-Critical Process (UI/Network)

- **Risk:** A network driver loop consumes 100% CPU, starving the alarm system.
- **Mitigation:**
  - **Core Isolation:** Network stack runs on Efficiency Cores only.
  - **Cgroups:** Enforce strict CPU bandwidth limits (e.g., max 80% of Efficiency cluster).
  - **Hardware Watchdog:** Independent timer monitored only by Prime Core. If not kicked, hardware resets the specific subsystem or entire SoC.

### Scenario 2: Erroneous AI/DSP Output

- **Risk:** NPU infers a false "normal" state despite raw data indicating distress.
- **Mitigation:**
  - **V-Model Validation Gate:** The Prime Core (Class C) receives *both* raw sensor data and NPU results.
  - **Plausibility Check:** Class C code performs a simplified, deterministic range check. If NPU output contradicts raw data physics, NPU output is discarded, and "Sensor Fault" alarm is raised.
  - **Sandboxing:** NPU runs in a separate process with no direct hardware control privileges.

### Scenario 3: Memory Corruption in Shared Buffers

- **Risk:** A bug in the visualization module overwrites acquisition data.
- **Mitigation:**
  - **Read-Only Mapping:** Map shared data regions as Read-Only for consumers.
  - **Sequence Numbers & CRC:** Every IPC packet includes a sequence ID and CRC32. Mismatched IDs trigger immediate channel shutdown.
  - **Guard Pages:** Insert unmapped memory pages between buffers to catch buffer overflows instantly (SIGSEGV).

### Scenario 4: Thermal Throttling affecting Real-Time Performance

- **Risk:** SoC overheats due to AI load, throttling the Prime Core and delaying alarms.
- **Mitigation:**
  - **Thermal Zones:** Define distinct thermal policies. Critical cores have higher throttling thresholds.
  - **Load Shedding:** Monitor thermal sensors in Class C code. If temperature rises, Class C logic commands the shutdown of Class A/B workloads (UI, Network) to preserve cooling headroom for safety functions.

### Scenario 5: Power Failure / Brownout

- **Risk:** Sudden power loss corrupts patient data or leaves device in undefined state.
- **Mitigation:**
  - **PMIC Integration:** Leverage QCS8550 PMIC interrupts for early warning.
  - **Secure Save:** Prime Core halts all other cores via IPC upon power warning, flushes critical state to FRAM/EEPROM (non-volatile), then initiates graceful shutdown.

## 5. Inter-Process Communication (IPC) Architecture

Safe communication between domains is critical. We utilize a **Message-Passing** architecture rather than shared global variables.

### 5.1 IPC Channels

| Channel Name   | Source Domain       | Dest Domain         | Protocol                 | Safety Check               |
|:-------------- |:------------------- |:------------------- |:------------------------ |:-------------------------- |
| `raw_data_tx`  | Acquisition (A715)  | Processing (A715)   | Shared Mem Ring Buffer   | CRC + Sequence ID          |
| `alarm_req`    | Processing (A715)   | Safety Monitor (X3) | Message Queue (Priority) | Double-Sample Verification |
| `ai_result`    | NPU/DSP             | Safety Monitor (X3) | Shared Mem (Read-Only)   | Plausibility Range Check   |
| `shutdown_cmd` | Safety Monitor (X3) | All Domains         | Broadcast Interrupt      | Hardware Line Assertion    |

### 5.2 Timeout & Heartbeat Mechanism

- **Heartbeat:** Every domain must publish a heartbeat to the Safety Monitor (Prime Core) every 10ms.
- **Timeout Action:** If a domain misses 3 heartbeats:
  1. Safety Monitor logs "Domain Fault".
  2. Safety Monitor isolates the faulty domain (kills process/restarts VM).
  3. If critical domain (Acquisition), transition device to Safe Mode.

## 6. Development & Verification Workflow

### 6.1 Compilation & Linking

- **Separate Binaries:** Compile Safety (Class C) and Non-Safety (Class A/B) code into separate executables/libraries.
- **Compiler Flags:** Use `-fstack-protector-strong`, `-D_FORTIFY_SOURCE=2` for all; disable optimizations that might reorder safety-critical checks (`-O2` vs `-O3` analysis).

### 6.2 Static Analysis

- Run MISRA C/C++ checkers specifically on the Prime Core codebase.
- Verify no dynamic memory allocation (`malloc`/`free`) in Class C paths after initialization.

### 6.3 Fault Injection Testing

- **CPU Lockup:** Simulate 100% load on Efficiency cores; verify Prime Core latency remains < 2ms.
- **Memory Bit-Flip:** Inject errors into shared memory; verify CRC detection and rejection.
- **IPC Delay:** Artificially delay messages; verify timeout handlers trigger correctly.

## 7. Conclusion

The QCS8550's heterogeneous architecture is not just a performance feature but a **safety mechanism**. By strictly mapping software safety classes to hardware domains (Prime Core for Class C, DSP for SOUP, TrustZone for Security), we create a "Defense in Depth" posture. This approach ensures that even if complex, unverified components (AI, Network) fail catastrophically, the hardware-isolated Safety Monitor retains control to protect the patient.

## Appendix: QCS8550 Specific Register References

*(To be populated with specific Qualcomm BSP documentation references during implementation)*

- `APSS_WDT_BASE`: Application Processor Subsystem Watchdog
- `MPU_CONFIG_REGION_X`: Memory Protection Unit configurations
- `TZASC_CTRL`: TrustZone Address Space Controller
