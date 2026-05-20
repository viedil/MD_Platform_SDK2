# RTOS/Linux Partitioning Strategy for QCS8550

## 1. Executive Summary

This document defines the software architecture strategy for partitioning the Qualcomm QCS8550 SoC into distinct safety-critical (RTOS) and general-purpose (Linux) domains. This "Safety Island" approach ensures deterministic behavior for IEC 62304 Class C functions while leveraging the high-performance capabilities of Linux for complex algorithms and connectivity.

### 1.1 Architecture Goal

- **Determinism:** Guarantee hard real-time response (<10μs jitter) for patient monitoring and alarm generation.
- **Isolation:** Prevent non-critical software faults (Linux GUI, Network Stack) from affecting safety-critical functions.
- **Efficiency:** Utilize heterogeneous compute resources (DSP, NPU, GPU) without compromising safety integrity.

### 1.2 Core Allocation Matrix

| Domain                 | Cores                                         | OS                 | Safety Class | Primary Responsibilities                                                               |
|:---------------------- |:--------------------------------------------- |:------------------ |:------------ |:-------------------------------------------------------------------------------------- |
| **Safety Island**      | 1x Cortex-A510 (Efficiency)                   | FreeRTOS / Zephyr  | **Class C**  | ISP Control, Signal Acquisition, Alarms, Watchdog, Safety Limits                       |
| **Application Domain** | 1x Cortex-X3 (Prime)<br>4x Cortex-A715 (Perf) | Linux (PREEMPT_RT) | Class A/B    | AI/ML Inference, UI/UX, DICOM/HL7, Data Logging, Cloud Sync                            |
| **Accelerators**       | Hexagon DSP, NPU                              | SOUP / Drivers     | Class B/C*   | Hardware-accelerated filtering, Neural Network inference (*Validated by Safety Island) |

> **Note:** The Safety Island runs on an Efficiency core to minimize heat/power while maintaining sufficient throughput for control loops. The Prime/Performance cores are reserved for bursty, high-load Linux tasks.

---

## 2. Detailed Domain Specifications

### 2.1 Safety Island (RTOS Domain)

The RTOS domain acts as the "Root of Trust" for system safety. It owns all direct hardware interfaces related to patient data acquisition and critical actuation.

#### Key Responsibilities:

1. **Direct ISP Control:** Bypasses the Linux V4L2 stack to configure Image Signal Processor registers directly via memory-mapped I/O.
2. **Hard Real-Time Acquisition:** Captures sensor data at fixed intervals (e.g., 1kHz ECG, 60fps Video) with nanosecond precision.
3. **Plausibility Checking:** Executes immediate range checks, rate-of-change limits, and artifact detection on raw data.
4. **Alarm Generation:** Implements IEC 60601-1-8 alarm logic with guaranteed latency bounds.
5. **System Health Monitor:** Monitors Linux domain heartbeat; triggers system safe-state if Linux hangs.
6. **Watchdog Management:** Owns the external hardware watchdog timer; Linux must periodically petition RTOS to kick the watchdog.

#### Memory Layout (RTOS):

- **Code:** Strictly statically linked, no dynamic allocation (`malloc`/`free` banned).
- **Stack:** Guard pages enabled, usage monitored at runtime.
- **Shared Memory:** Dedicated cache-coherent regions for IPC (Input/Output buffers only).

### 2.2 Application Domain (Linux Domain)

The Linux domain provides rich services but operates under the supervision of the Safety Island. It is treated as a "potentially unsafe" subsystem.

#### Key Responsibilities:

1. **Advanced Processing:** Runs heavy signal processing (FFT, Wavelet) and AI models (Arrhythmia detection, Image segmentation) using NPU/DSP.
2. **User Interface:** Renders graphical waveforms, trends, and touch interactions (Qt/Android Framework).
3. **Connectivity:** Manages Wi-Fi, Ethernet, Bluetooth, DICOM Store, HL7 ORU, FHIR resources.
4. **Data Persistence:** Handles local database (SQLite) and secure file storage.
5. **Remote Updates:** Manages OTA update packages (validated by RTOS before applying).

#### Constraints:

- **No Direct Hardware Access:** Cannot access ISP, ADC, or GPIOs related to safety outputs directly.
- **Time Slicing:** CPU affinity restricted to Prime/Performance cores; banned from Safety Island core.
- **Watchdog Dependency:** Must send periodic "I am alive" messages to RTOS.

---

## 3. ISP Integration & Data Flow

The Image Signal Processor (ISP) is the most critical hardware block. Direct control by RTOS eliminates Linux kernel scheduling jitter from the acquisition path.

### 3.1 Acquisition Sequence

1. **Configuration (Startup):**
   - RTOS initializes ISP clocks, PHY, and register map.
   - RTOS configures DMA descriptors in shared memory.
2. **Capture Loop (Runtime):**
   - **Step 1:** ISP captures frame → DMA writes to **Shared Buffer A**.
   - **Step 2:** RTOS receives interrupt → Validates header/checksum.
   - **Step 3:** RTOS performs quick plausibility check (e.g., "Is image too dark?", "Is lead off?").
   - **Step 4:** If Valid → RTOS updates "Write Index" in Ring Buffer & signals Linux via Mailbox Interrupt.
   - **Step 5:** If Invalid → RTOS discards frame, logs error, triggers "Signal Quality" alarm.
3. **Processing Handoff:**
   - Linux wakes up (or polls), reads new index, processes Frame A using NPU.
   - Linux writes results (e.g., "SpO2 = 98%") to **Result Buffer**.
   - Linux signals RTOS via Mailbox.
4. **Final Validation:**
   - RTOS reads Result Buffer.
   - RTOS applies safety limits (e.g., "Is 98% within physiological possible range?").
   - If Pass → Update Display Buffer & Alarm State.
   - If Fail → Ignore result, trigger "Algorithm Error" alarm.

### 3.2 Shared Memory Map

| Region          | Size  | Owner (Writer) | Access            | Content                                    |
|:--------------- |:----- |:-------------- |:----------------- |:------------------------------------------ |
| `SHM_CMD`       | 4 KB  | Linux          | RTOS (Read)       | Configuration requests, Mode changes       |
| `SHM_RAW_RING`  | 64 MB | RTOS (ISP)     | Linux (Read)      | Circular buffer of raw video/waveform data |
| `SHM_RES_RING`  | 4 MB  | Linux (AI)     | RTOS (Read)       | Processed parameters, AI confidence scores |
| `SHM_LOG`       | 8 MB  | Both           | Read-Only (Audit) | Circular audit log (WORM style)            |
| `SHM_HEARTBEAT` | 64 B  | Both           | Both              | Timestamped alive counters                 |

> **Implementation Note:** Use `dma_alloc_coherent` (Linux) and equivalent MPU-configured memory (RTOS) to ensure cache coherency without manual flush/invalidate overhead.

---

## 4. Implementation Technologies

Two primary approaches exist for implementing this partition on QCS8550.

### Option A: Asymmetric Multiprocessing (AMP) - *Recommended*

Uses the standard Qualcomm `remoteproc` and `RPMsg` framework. One core runs Linux, another runs RTOS as a "remote processor."

- **Pros:** Native support in Qualcomm BSP, low latency (<5μs), efficient resource sharing.
- **Cons:** Requires careful device tree configuration to hide resources (ISP) from Linux.
- **Mechanism:**
  - Linux loads RTOS binary onto the A510 core via `rproc`.
  - Communication via VirtIO-RPMsg rings.
  - Interrupts mapped directly between cores.

### Option B: Type-1 Hypervisor (Jailhouse / ACRN)

A hypervisor runs bare-metal, launching Linux and RTOS as separate "cells" or VMs.

- **Pros:** Stronger isolation (memory virtualization), independent reboot of Linux without resetting RTOS.
- **Cons:** Higher complexity, potential performance overhead, harder to certify hypervisor itself.
- **Use Case:** Preferred if strict regulatory separation is required or if running Android + RTOS simultaneously.

### Selected Approach: AMP with `remoteproc`

Given the QCS8550 architecture and medical device requirements, AMP offers the best balance of performance, determinism, and ecosystem support.

#### Device Tree Modifications (Linux Side):

```dts
/* Reserve A510 core for RTOS */
reserved-memory {
    rtk_memory: rtk@80000000 {
        reg = <0x0 0x80000000 0x0 0x10000000>; /* 256MB */
        no-map;
        reusable;
    };
};

/* Disable ISP node in Linux, enable in RTOS DTB */
&isp {
    status = "disabled";
};

&rtos_core {
    status = "okay";
    memory-region = <&rtk_memory>;
    firmware-path = "medical_safety_rtos.bin";
};
```

---

## 5. Inter-Process Communication (IPC) Protocol

Communication between Safety Island and Linux must be robust, deadlock-free, and verifiable.

### 5.1 Message Structure

All RPMsg packets follow a strict TLV (Type-Length-Value) format with CRC.

```c
struct SafetyMessage {
    uint32_t magic;      // 0xMED1C4L
    uint16_t msg_id;     // Unique sequence number
    uint16_t type;       // CMD_DATA_READY, CMD_ALARM, etc.
    uint32_t timestamp;  // Nanosecond precision
    uint32_t payload_len;
    uint8_t  payload[];  // Variable data
    uint32_t crc32;      // Integrity check
};
```

### 5.2 Communication Patterns

#### Pattern 1: Data Ready (Push)

- **Sender:** RTOS
- **Receiver:** Linux
- **Action:** RTOS writes index to shared ring, sends RPMsg "DATA_AVAILABLE".
- **Timeout:** Linux must acknowledge within 20ms or RTOS flags "Consumer Lag" warning.

#### Pattern 2: Configuration Request (Pull/Push)

- **Sender:** Linux
- **Receiver:** RTOS
- **Action:** Linux requests parameter change (e.g., "Gain = 2x").
- **Validation:** RTOS validates limits before applying. Rejects if unsafe.
- **Response:** RTOS sends "ACK" or "NACK_REASON".

#### Pattern 3: Heartbeat (Monitor)

- **Frequency:** 100Hz (10ms)
- **Mechanism:** Both sides increment counter in `SHM_HEARTBEAT`.
- **Failure Logic:** If RTOS detects Linux counter stale > 50ms → Initiate Linux Watchdog Reset.

### 5.3 Error Handling

- **Checksum Mismatch:** Discard message, log `ERR_CRC_FAIL`, request retransmission (if applicable) or skip frame.
- **Sequence Gap:** Detect missing messages via `msg_id`. Log `ERR_SEQ_GAP`.
- **Buffer Full:** RTOS stops acquisition (Safe State) if Linux cannot consume data fast enough. Trigger "System Overload" alarm.

---

## 6. Safety Mechanisms & Fault Containment

### 6.1 Temporal Isolation

- **CPU Affinity:** Linux scheduler explicitly banned from A510 core (`isolcpus=1` in kernel cmdline).
- **Interrupt Affinity:** ISP and Safety GPIO interrupts routed exclusively to A510.
- **Bus Arbitration:** Configure NoC (Network on Chip) QoS to prioritize RTOS traffic over Linux DMA.

### 6.2 Memory Protection

- **MPU Configuration:** RTOS configures Memory Protection Unit to mark Linux memory regions as Non-Executable/Non-Accessible.
- **Guard Pages:** Unmapped memory pages surrounding stacks and heaps to detect overflow.

### 6.3 Watchdog Hierarchy

1. **Window Watchdog (RTOS):** Monitors RTOS main loop. Must be kicked within strict time window.
2. **External Watchdog IC:** Controlled by RTOS GPIO.
   - RTOS kicks IC only if: (RTOS Internal OK) AND (Linux Heartbeat OK).
   - If Linux hangs → RTOS stops kicking → System Reset.

### 6.4 Thermal & Power Management

- **Thermal Throttling:** RTOS monitors SoC temperature.
  - Level 1: Reduce Linux CPU frequency.
  - Level 2: Disable NPU/DSP.
  - Level 3: Safe shutdown of patient monitoring.
- **Power Failure:** PMIC interrupt routed to RTOS. RTOS initiates graceful save of critical settings to FRAM/EEPROM before power loss.

---

## 7. Development & Verification Workflow

### 7.1 Build System

- **Dual Pipeline:**
  - **RTOS:** CMake + ARM GCC (Static analysis with Polyspace/Klocwork).
  - **Linux:** Yocto/Buildroot (Standard kernel build).
- **Integration:** Final image generation script combines `Image.gz`, `dtb`, and `rtos.bin` into a single flashable artifact.

### 7.2 Testing Strategy

1. **Unit Testing:** Google Test (Linux) + CppUTest (RTOS) for individual modules.
2. **HIL (Hardware-in-Loop):**
   - Inject simulated sensor data via JTAG/Probe.
   - Verify alarm latency with oscilloscope on GPIO toggle.
3. **Fault Injection:**
   - Kill Linux process randomly → Verify RTOS triggers reset.
   - Corrupt shared memory → Verify CRC detection.
   - Flood IPC channel → Verify backpressure handling.
4. **Timing Analysis:**
   - Worst-Case Execution Time (WCET) measurement for RTOS ISR.
   - Jitter analysis of acquisition loop.

### 7.3 Regulatory Traceability

- **SOUP Identification:** Linux Kernel, RPMsg Driver, FreeRTOS Kernel identified as SOUP.
- **Validation Plan:** Specific tests to validate SOUP behavior in the integrated system.
- **Risk Control:** Each hazard from ISO 14971 mapped to specific architectural isolation feature.

---

## 8. Conclusion

The RTOS/Linux partitioning strategy on QCS8550 provides a robust foundation for a next-generation medical device. By dedicating a specific core to safety-critical functions ("Safety Island"), we achieve the determinism required for Class C compliance while retaining the flexibility of Linux for advanced features. The defined IPC mechanisms, memory maps, and fault containment strategies ensure that the system remains safe even in the presence of software faults in the general-purpose domain.

### Next Steps

1. Finalize Device Tree bindings for QCS8550.
2. Develop prototype RTOS application for ISP control.
3. Implement RPMsg communication layer.
4. Execute preliminary timing analysis.
