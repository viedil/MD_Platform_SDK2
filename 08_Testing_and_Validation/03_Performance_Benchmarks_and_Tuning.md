# 11_Performance_Benchmarks_and_Tuning.md

# Performance Benchmarks, Optimization Guide, and Tuning Standards

**Priority:** P0 (Critical for Real-time Medical Applications)  
**Status:** Baseline Definition & Target Specifications  
**Target Hardware:** Qualcomm QCS8550 (8x Cortex-A720 + Adreno GPU + Hexagon NPU)

---

## 1. Executive Summary
Medical imaging and AI inference require deterministic performance. This document defines the mandatory performance baselines for the SDK, ensuring that any device built on this platform meets the rigorous latency and throughput requirements of Class II/III medical procedures (e.g., surgical guidance, real-time monitoring).

### 1.1 Key Performance Indicators (KPIs)
| Metric | Target Value | Critical Threshold | Measurement Method |
| :--- | :--- | :--- | :--- |
| **Cold Boot Time** | < 4.0 seconds | > 6.0 seconds | Power-on to UI Ready |
| **AI Inference Latency** | < 15ms (p99) | > 33ms (30fps drop) | End-to-End Pipeline |
| **Image Render Latency** | < 8ms (1080p) | > 16ms | Frame Presentation Time |
| **System Jitter** | < 50µs | > 1ms | Cyclictest (Real-time Kernel) |
| **Memory Footprint** | < 2GB (Idle) | > 4GB | PSS (Proportional Set Size) |

---

## 2. Benchmarking Methodology

### 2.1 Test Environment Setup
- **Hardware:** Qualcomm QCS8550 Reference Board (16GB LPDDR5X, 512GB UFS 4.0).
- **Cooling:** Active cooling maintained at 25°C ambient for baseline; thermal throttling tests at 45°C.
- **Software:** Linux Kernel 6.6 LTS with PREEMPT_RT patchset, Android HAL compatibility layer disabled for pure Linux mode.

### 2.2 Tooling Stack
| Domain | Tools |
| :--- | :--- |
| **System Profiling** | `perf`, `ftrace`, `systrace`, `Bootchart` |
| **Memory Analysis** | `valgrind`, `smem`, `pmap`, `memleak-bpfcc` |
| **GPU/NPU** | Snapdragon Profiler (Adreno), `qnn-net-run` (Hexagon) |
| **Network/IO** | `iperf3`, `fio`, `netperf` |
| **Real-time** | `cyclictest`, `oslat`, `hwlatdetect` |

---

## 3. Component-Specific Benchmarks

### 3.1 CPU & Scheduler Optimization
**Goal:** Minimize context switches and ensure high-priority medical threads are never starved.

- **Configuration:**
  - Isolate CPUs: `isolcpus=4-7` (Dedicated to real-time image processing).
  - Governor: `performance` mode for critical cores; `schedutil` for background.
- **Benchmark Targets:**
  - Context Switch Latency: < 5µs.
  - Thread Wakeup Latency: < 10µs (for RT priority threads).

### 3.2 GPU & Display Pipeline (Adreno)
**Goal:** Zero tearing, minimal latency for surgical overlays.

- **Pipeline:** Camera → ISP → Memory → GPU (Processing) → Display Controller.
- **Optimization Techniques:**
  - Use `AFBC` (Arm Frame Buffer Compression) for memory bandwidth savings.
  - Explicit Synchronization Fences (avoid implicit sync stalls).
  - VSync Phase Offsetting to align with camera frame arrival.
- **Benchmark Targets:**
  - Frame Rate Stability: Locked 60fps or 120fps (variance < 1%).
  - Composition Overhead: < 2ms per frame.

### 3.3 AI Acceleration (Hexagon NPU)
**Goal:** Maximize TOPS utilization for segmentation/detection models.

- **Runtime:** Qualcomm AI Engine Direct / QNN (Qualcomm Neural Network).
- **Model Optimization:**
  - Quantization: INT8 preferred (accuracy loss < 1%).
  - Layer Fusion: Conv + BN + ReLU fused operations.
- **Benchmark Targets:**
  - ResNet-50 Inference: < 3ms.
  - U-Net Segmentation (1080p): < 15ms.
  - Data Transfer (Host ↔ NPU): Overlapped with compute (Double buffering).

### 3.4 Storage & I/O (UFS 4.0)
**Goal:** Fast DICOM save and log writing without blocking UI.

- **Configuration:** 
  - Filesystem: `ext4` with `data=ordered` or `f2fs` for flash longevity.
  - Mount Options: `noatime`, `discard=async`.
- **Benchmark Targets:**
  - Sequential Write: > 1.5 GB/s.
  - Random Write (4K): > 200 MB/s.
  - DICOM Save (50MB image): < 100ms.

---

## 4. Thermal Management & Throttling Profiles

Medical devices often operate in enclosed carts or warm OR environments.

### 4.1 Thermal Zones
| Zone | Sensor Location | Throttle Trigger | Action |
| :--- | :--- | :--- | :--- |
| **SoC Core** | Internal PMIC | 85°C | Reduce CPU freq by 20% |
| **Camera Module** | Flex Cable Near Sensor | 60°C | Drop FPS to 15, warn user |
| **Battery/PSU** | Power Input Stage | 70°C | Disable Charging, Alert |

### 4.2 Mitigation Strategies
- **Dynamic Voltage Frequency Scaling (DVFS):** Aggressive ramp-down curves.
- **Workload Migration:** Move non-critical tasks (logging, network sync) to little cores during thermal events.
- **User Warning:** SDK must expose `thermal_event` signals to the application UI to alert clinicians.

---

## 5. Power Consumption Baselines

For portable/battery-operated medical devices.

| State | Target Power Draw | Notes |
| :--- | :--- | :--- |
| **Suspend (Sleep)** | < 50mW | RTC + Wake-on-LAN only |
| **Idle (UI On)** | < 1.5W | Display backlight @ 100 nits |
| **Active (AI Running)** | < 6.0W | Full NPU + CPU + Camera |
| **Peak Load** | < 9.0W | Stress test all rails |

---

## 6. Tuning Guide for Developers

### 6.1 Kernel Parameters (`/etc/sysctl.conf` & Cmdline)
```bash
# Real-time priorities
kernel.sched_rt_runtime_us = 950000
kernel.sched_rt_period_us = 1000000

# Memory overcommit (controlled for safety)
vm.overcommit_memory = 2
vm.overcommit_ratio = 80

# Network buffers (for high throughput DICOM streaming)
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
```

### 6.2 Cgroup Configuration
Isolate critical medical processes from background daemons.
```bash
# Create 'medical_rt' group
mkdir /sys/fs/cgroup/cpuset/medical_rt
echo 4-7 > /sys/fs/cgroup/cpuset/medical_rt/cpuset.cpus
echo $$ > /sys/fs/cgroup/cpuset/medical_rt/cgroup.procs
```

### 6.3 Common Pitfalls
- **Avoid:** `printf`/`logcat` in high-frequency loops (causes jitter).
- **Avoid:** Unbounded memory allocation in image processing chains.
- **Avoid:** Blocking I/O on the main rendering thread.

---

## 7. Continuous Performance Monitoring

Performance regression testing is part of the CI/CD pipeline (`06_Developer_Tooling_and_CI_CD.md`).

- **Nightly Runs:** Full benchmark suite on reference hardware.
- **Alerting:** Any degradation > 5% triggers a build failure.
- **Trend Analysis:** Long-term data stored in Grafana/Prometheus dashboard.

---

## 8. References
- `02_System_Architecture.md` (Kernel Config)
- `05_Predefined_Modules/06_AI_Inference_Engine.md` (NPU details)
- `08_Risk_Mitigation_and_Validation.md` (Thermal risks)
- Qualcomm QCS8550 Technical Reference Manual (NDA)
