# 02. System Architecture Specification

**Version:** 1.0  
**Status:** Approved for Implementation  
**Classification:** Medical Device SDK - Core Architecture  
**Compliance:** IEC 62304 Class C, ISO 14971, FDA Cybersecurity Guidance  

---

## Executive Summary

This document defines the complete system architecture for the Medical Device Platform SDK, targeting **Qualcomm QCS8550** SoC with **Linux-based real-time OS**. The architecture ensures:

- **Deterministic Performance**: <50us interrupt latency, <4s cold boot
- **Safety Isolation**: Mixed-criticality workloads via Type-1 Hypervisor
- **Regulatory Compliance**: IEC 62304 Class C software lifecycle
- **Cross-Architecture Development**: Seamless x86 development to ARM deployment

---

## 1. Architecture Overview

### 1.1 High-Level Block Diagram

```
+---------------------------------------------------------------------+
|                     APPLICATION LAYER                                |
|  +-------------+  +-------------+  +-------------+                  |
|  |  UI / HMI   |  |  AI/ML Apps |  | Connectivity|                 |
|  |  (Qt/VTK)   |  | (ONNX/TFL)  |  | (DICOM/HL7) |                 |
|  +-------------+  +-------------+  +-------------+                  |
+---------------------------------------------------------------------+
|                     SDK FRAMEWORK LAYER                              |
|  +---------------------------------------------------------------+  |
|  |              Module Manager & Plugin System                   |  |
|  +-------------+-------------+-------------+-------------+        |  |
|  |  Imaging    |  AI Engine  |  Data Mgmt  |  Security   |        |  |
|  |  (OpenCV)   | (ONNX RT)   | (SQLite)    | (TLS/PKI)   |        |  |
|  +-------------+-------------+-------------+-------------+        |  |
+---------------------------------------------------------------------+
|                     HARDWARE ABSTRACTION LAYER (HAL)                 |
|  +---------------+---------------+---------------+                  |
|  |  x86 Mock HAL |  ARM QCS HAL  |  Test HAL     | <- Swappable   |
|  |  (v4l2loopback)| (QNN/DSP)    |  (Simulated)  |                 |
|  +---------------+---------------+---------------+                  |
+---------------------------------------------------------------------+
|                     SYSTEM SOFTWARE LAYER                            |
|  +---------------------------------------------------------------+  |
|  |            Type-1 Hypervisor (ACRN / Jailhouse)               |  |
|  +---------------------------------------------------------------+  |
|  |  Guest VM 1: Safety-Critical (PREEMPT_RT Linux)               |  |
|  |  Guest VM 2: General Purpose (Standard Linux)                 |  |
|  |  Guest VM 3: Android (Optional, for UI)                       |  |
|  +---------------------------------------------------------------+  |
+---------------------------------------------------------------------+
|                     KERNEL & DRIVERS                                 |
|  Linux 6.6 LTS + PREEMPT_RT Patch | Qualcomm BSP Drivers           |
|  - Camera (ISP)  - DSP (Hexagon)  - GPU (Adreno)  - NPU           |
+---------------------------------------------------------------------+
|                     HARDWARE (QCS8550)                               |
|  8x Cortex-A720 | Hexagon DSP | Adreno GPU | NPU | ISP | VPU      |
+---------------------------------------------------------------------+
```

### 1.2 Key Architectural Decisions

| Decision | Rationale | Alternative Considered |
|----------|-----------|------------------------|
| **Type-1 Hypervisor** | Hardware-enforced isolation between safety-critical and non-critical workloads | Containers (rejected: insufficient isolation for Class C) |
| **PREEMPT_RT Kernel** | Deterministic interrupt latency (<50us) required for patient monitoring | Standard kernel (rejected: non-deterministic) |
| **Swappable HAL** | Enable 90% development on x86, reduce ARM dependency | Native-only development (rejected: slow iteration) |
| **Microkernel IPC** | Message-passing between isolated domains for fault containment | Shared memory (rejected: single point of failure) |

---

## 2. Boot Chain & Security

### 2.1 Secure Boot Sequence

| Stage | Component | Verification Method | Time Budget |
|-------|-----------|---------------------|-------------|
| **PBL** | ROM Code (Immutable) | Hardware root of trust | 50ms |
| **SBL** | Secondary Bootloader | RSA-3072 signature check | 100ms |
| **ABL** | Android Bootloader | Verified Boot (AVB 2.0) | 200ms |
| **Hypervisor** | ACRN/Jailhouse | Signature + Hash verification | 300ms |
| **Kernel** | Linux + Initramfs | dm-verity integrity check | 1.5s |
| **Userspace** | SDK Services | Container image signing | 1.8s |
| **Application** | Medical Apps | Code signing certificate | 2.0s |

**Total Cold Boot Target**: <4.0 seconds (including POST and display init)

### 2.2 Chain of Trust

```
Hardware RoT (eFuse) 
  v verifies
SBL (Signed by OEM Key)
  v verifies
Hypervisor (Signed by Platform Key)
  v verifies
Kernel + Device Tree (Signed + dm-verity)
  v verifies
SDK Containers (Signed by Dev Key)
  v verifies
Application Binaries (Code Signing)
```

**Key Management**:
- **OEM Key**: Stored in HSM, used for production signing
- **Dev Key**: Isolated in CI/CD, used for debug builds
- **Recovery Key**: Escrowed for field recovery scenarios

---

## 3. Hypervisor Strategy

### 3.1 Mixed-Criticality Workload Isolation

The Type-1 hypervisor partitions hardware resources between safety-critical and general-purpose domains:

| Resource | Safety Domain (VM1) | General Domain (VM2) | UI Domain (VM3) |
|----------|---------------------|----------------------|-----------------|
| **CPU Cores** | 4x Dedicated (A720) | 3x Shared | 1x Shared |
| **Memory** | 4GB (Locked) | 2GB (Dynamic) | 2GB (Dynamic) |
| **GPU** | None (Software Render) | Full Access (Adreno) | Partial Access |
| **DSP/NPU** | Reserved for AI Inference | No Access | No Access |
| **Network** | Isolated VLAN | Full Access | Full Access |
| **Storage** | Encrypted Partition | Standard Partition | Cache Only |
| **Priority** | REALTIME (FIFO) | Best Effort | Best Effort |

### 3.2 Inter-VM Communication (IPC)

Safety-critical and general domains communicate via virtio-based message queues with strict validation:

```c
// Example: Safe IPC Message Structure
typedef struct {
    uint32_t magic;          // 0xDEADBEEF for validation
    uint32_t msg_id;         // Unique message identifier
    uint32_t source_vm;      // Source VM ID
    uint32_t dest_vm;        // Destination VM ID
    uint32_t payload_len;    // Max 4KB
    uint8_t  checksum;       // CRC8
    uint8_t  priority;       // 0=Highest (Safety), 3=Lowest
    uint8_t  reserved[2];
    uint8_t  payload[];      // Variable length
} safe_ipc_msg_t;

// Validation Rules:
// 1. Magic number check
// 2. CRC8 checksum verification
// 3. Source/Dest VM authorization
// 4. Payload size bounds check
// 5. Priority inversion prevention
```

**IPC Latency Budget**: <100us end-to-end (VM1 to VM2)

---

## 4. Kernel Configuration

### 4.1 Real-Time Requirements

The Linux kernel is configured with PREEMPT_RT patch for deterministic behavior:

```bash
# Critical Kernel Config Options (arch/arm64/configs/qcs8550_medical_defconfig)

CONFIG_PREEMPT_RT=y
CONFIG_NO_HZ_FULL=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_CPU_ISOLATION=y
CONFIG_RCU_EXPERT=y
CONFIG_RCU_NOCB_CPU=y

# Memory Locking
CONFIG_MEMCG=y
CONFIG_CGROUPS=y
CONFIG_BLK_CGROUP=y

# Watchdog & Safety
CONFIG_HARDLOCKUP_DETECTOR=y
CONFIG_SOFTLOCKUP_DETECTOR=y
CONFIG_DETECT_HUNG_TASK=y
CONFIG_PANIC_ON_OOPS=y
CONFIG_PANIC_TIMEOUT=5

# Security Hardening
CONFIG_STRICT_DEVMEM=y
CONFIG_DEBUG_RODATA=y
CONFIG_ARM64_SW_TTBR0_PAN=y
CONFIG_RANDOMIZE_BASE=y
```

### 4.2 Interrupt Latency Optimization

| Optimization | Technique | Expected Latency |
|--------------|-----------|------------------|
| **IRQ Thread Priorities** | FIFO 90-95 for critical IRQs | <20us |
| **CPU Isolation** | Isolcpus=4-7 (dedicated to RT) | <30us |
| **Timer Affinity** | Bind timers to isolated CPUs | <25us |
| **Memory Pre-allocation** | No dynamic alloc in IRQ path | <15us |
| **Disable C-States** | Force C0 (no sleep states) | <10us |

**Worst-Case Interrupt Latency**: <50us (measured at GPIO toggle to ISR execution)

---

## 5. Hardware Abstraction Layer (HAL)

### 5.1 HAL Interface Design

The HAL provides a unified interface for hardware access, swappable between x86 mock and ARM target:

```cpp
// Abstract HAL Interface (Portable Code)
class ICameraHAL {
public:
    virtual ~ICameraHAL() = default;
    
    // Initialization
    virtual bool initialize(const CameraConfig& config) = 0;
    
    // Frame Acquisition
    virtual FrameStatus captureFrame(FrameBuffer& buffer, 
                                     uint32_t timeout_ms) = 0;
    
    // Control
    virtual bool setExposure(float exposure_ms) = 0;
    virtual bool setGain(float gain_db) = 0;
    virtual bool setFocus(float distance_mm) = 0;
    
    // Diagnostics
    virtual CameraHealth getHealthStatus() const = 0;
};

// Factory Pattern for HAL Selection
std::unique_ptr<ICameraHAL> createCameraHAL() {
#ifdef TARGET_X86_MOCK
    return std::make_unique<MockCameraHAL>();  // v4l2loopback
#elif TARGET_QCS8550
    return std::make_unique<QCSCameraHAL>();   // Qualcomm ISP
#else
    #error "Unknown target platform"
#endif
}
```

### 5.2 Mock HAL Implementation (x86 Development)

| Hardware | Mock Implementation | Tool/Library |
|----------|---------------------|--------------|
| **Camera** | v4l2loopback + ffmpeg video stream | GStreamer test patterns |
| **DSP/NPU** | ONNX Runtime CPU backend | Intel OpenVINO (optional) |
| **GPIO** | File-based mock (/tmp/mock_gpio/) | Custom filesystem driver |
| **Sensors** | Simulated data generator | Python script to shared memory |
| **Display** | X11/Wayland window | Qt rendering |
| **Audio** | PulseAudio loopback | ALSA dummy driver |

**Mock Fidelity**: >95% API compatibility, timing within +/-10% of target

---

## 6. Performance Budgets

### 6.1 Timing Requirements

| Operation | Target | Worst-Case | Measurement Method |
|-----------|--------|------------|-------------------|
| **Cold Boot** | <4.0s | <5.0s | Power-on to UI ready |
| **Warm Boot** | <2.0s | <3.0s | Watchdog reset to app |
| **Interrupt Latency** | <30us | <50us | GPIO toggle to ISR |
| **Context Switch** | <5us | <10us | Cyclictest benchmark |
| **AI Inference** | <15ms | <25ms | Image input to result |
| **Image Processing** | <33ms | <50ms | 4K frame pipeline |
| **IPC Latency** | <50us | <100us | VM-to-VM message |
| **Display Refresh** | 60 FPS | 60 FPS | Tearing-free guarantee |

### 6.2 Resource Allocation

| Resource | Total Available | Safety Domain | General Domain | Headroom |
|----------|-----------------|---------------|----------------|----------|
| **CPU** | 8 cores | 4 dedicated | 4 shared | 20% |
| **Memory** | 8GB LPDDR5X | 4GB locked | 4GB dynamic | 10% |
| **Storage** | 256GB UFS | 64GB encrypted | 192GB standard | 15% |
| **Bandwidth** | 50GB/s | 20GB/s reserved | 30GB/s shared | 25% |

---

## 7. Safety & Security Boundaries

### 7.1 Fault Containment Regions (FCR)

The system is divided into Fault Containment Regions to prevent error propagation:

```
+-------------------------------------------------------------+
|  FCR-1: SAFETY CRITICAL                                      |
|  - Patient Monitoring                                        |
|  - Therapy Delivery Control                                  |
|  - Alarm System                                              |
|  Isolation: Hardware (Hypervisor) + Software (MPU)          |
+-------------------------------------------------------------+
|  FCR-2: DIAGNOSTIC & IMAGING                                 |
|  - Image Acquisition                                         |
|  - AI Analysis                                               |
|  - Report Generation                                         |
|  Isolation: Hypervisor VM                                    |
+-------------------------------------------------------------+
|  FCR-3: CONNECTIVITY                                         |
|  - DICOM Network                                             |
|  - HL7 Integration                                           |
|  - Remote Maintenance                                        |
|  Isolation: Firewall + Container                             |
+-------------------------------------------------------------+
|  FCR-4: USER INTERFACE                                       |
|  - Touch Display                                             |
|  - Audio Output                                              |
|  - USB Peripherals                                           |
|  Isolation: Sandboxed Application                            |
+-------------------------------------------------------------+
```

**Failure Propagation Prevention**:
- **Hardware**: MMU/IOMMU protection, hypervisor memory isolation
- **Software**: Exception handlers, watchdog timers, health monitoring
- **Communication**: Message validation, rate limiting, circuit breakers

### 7.2 Security Perimeter

```
                    INTERNET (Untrusted)
                           |
                    +------+------+
                    |  Firewall   | <- Stateful inspection
                    +------+------+
                           |
                    +------+------+
                    |   DMZ       | <- Connectivity Services
                    |  (FCR-3)    |
                    +------+------+
                           |
                    +------+------+
                    |  Internal   | <- HIPAA Encryption
                    |   Bus       |
                    +------+------+
           +---------------+---------------+
           |               |               |
    +------+------+ +------+------+ +------+------+
    |   FCR-1     | |   FCR-2     | |   FCR-4     |
    |  (Safety)   | | (Imaging)   | |   (UI)      |
    +-------------+ +-------------+ +-------------+
```

**Security Controls**:
- **Network Segmentation**: VLANs per FCR
- **Encryption**: TLS 1.3 for all external communication
- **Authentication**: Mutual TLS + Certificate Pinning
- **Audit Logging**: Immutable logs to secure partition

---

## 8. Development & Porting Workflow

### 8.1 x86 Development Environment

Developers work on standard Linux workstations with full SDK functionality:

```bash
# Development Host Requirements
OS: Ubuntu 22.04/24.04 LTS, Fedora 38+, Debian 12
CPU: 8+ cores (Intel i7/Ryzen 7 or better)
RAM: 32GB minimum, 64GB recommended
Storage: 500GB NVMe SSD
GPU: Optional (for visualization testing)

# Mock Hardware Setup
sudo modprobe v4l2loopback devices=1 card_label="MockCamera"
gst-launch-1.0 videotestsrc pattern=smpte ! video/x-raw,width=1920,height=1080,framerate=30/1 ! v4l2sink device=/dev/video0

# Build & Run
mkdir build && cd build
cmake .. -DTARGET_PLATFORM=x86_mock -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
./run_tests.sh  # Executes 100% of unit + integration tests
```

### 8.2 Porting to QCS8550 (8-Step Process)

1. **Cross-Compile Setup**: Configure Linaro toolchain (aarch64-linux-gnu-gcc)
2. **HAL Swap**: Rebuild with -DTARGET_PLATFORM=qcs8550
3. **RootFS Creation**: Generate minimal root filesystem with buildroot/Yocto
4. **Image Signing**: Sign kernel, DTB, and containers with production keys
5. **Deployment**: Flash to target via fastboot or A/B update mechanism
6. **Hardware Validation**: Run hardware-specific tests (camera, DSP, NPU)
7. **Performance Tuning**: Adjust CPU freq governors, IRQ priorities, memory locks
8. **Regulatory Testing**: Execute IEC 62304 verification suite

**Porting Success Criteria**:
- [x] All unit tests pass on target
- [x] Interrupt latency <50us (measured with oscilloscope)
- [x] Boot time <4s (cold start)
- [x] No memory leaks (72-hour stress test)
- [x] Thermal throttling not triggered under max load

---

## 9. Verification & Validation

### 9.1 Architecture Verification Checklist

| Requirement | Verification Method | Acceptance Criteria | Status |
|-------------|--------------------|--------------------|--------|
| Boot time <4s | Automated boot measurement | Average <3.5s, worst-case <4.0s | [ ] |
| Interrupt latency <50us | Oscilloscope + GPIO toggle | 99.9th percentile <50us | [ ] |
| Hypervisor isolation | Penetration testing | No cross-VM memory access possible | [ ] |
| HAL compatibility | x86 vs ARM test comparison | >95% API parity, <10% timing variance | [ ] |
| Fault containment | Fault injection testing | Single fault does not propagate beyond FCR | [ ] |
| Secure boot | Tamper testing | Unsigned code fails to boot | [ ] |

### 9.2 Tool Qualification

Per IEC 62304, development tools must be qualified:

| Tool | Qualification Level | Method |
|------|-------------------|---------|
| **GCC/Linaro** | T3 (Compiler) | Vendor certification + regression suite |
| **CMake** | T2 (Build System) | Configuration audit + output verification |
| **GTest** | T2 (Test Framework) | Known-answer tests + coverage analysis |
| **QEMU** | T3 (Emulator) | Comparison with hardware execution |
| **Static Analyzers** | T2 | Multiple tool cross-validation |

---

## 10. References

- **IEC 62304**: Medical Device Software Lifecycle
- **ISO 14971**: Risk Management for Medical Devices
- **FDA Cybersecurity Guidance**: Premarket Submissions
- **Qualcomm QCS8550 BSP Documentation**
- **ACRN Hypervisor Architecture Guide**
- **Linux PREEMPT_RT Documentation**

---

## Document Control

| Version | Date | Author | Changes | Approval |
|---------|------|--------|---------|----------|
| 0.1 | 2024-01-15 | Architecture Team | Initial draft | Pending |
| 0.5 | 2024-02-01 | Architecture Team | Added HAL spec, boot chain | Pending |
| 1.0 | 2024-03-01 | Chief Architect | Final release | Approved |

**Next Review Date**: 2024-09-01 (6 months)
