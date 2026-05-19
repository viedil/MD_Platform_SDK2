# 00_Master_Specification: Predefined Medical Modules

## Overview
This directory contains specifications for 13 predefined medical device modules compliant with IEC 62304 Class B/C requirements. Each module follows a standardized template including safety classification, x86 mock strategy, QCS8550 implementation, and regulatory traceability.

## Module List

| ID | Module Name | Safety Class | Real-Time Req | Mock Strategy | Target HW |
|----|-------------|--------------|---------------|---------------|-----------|
| 01 | Camera Acquisition | B | <16ms latency | v4l2loopback + ffmpeg | QCS8550 ISP |
| 02 | AI Inference Engine | C | <30ms p99 | ONNX CPU backend | QNN DSP/NPU |
| 03 | DICOM Networking | B | Non-RT | Orthanc local | TLS Hardware |
| 04 | Ultrasound Beamforming | C | <5ms jitter | File replay | Hexagon DSP |
| 05 | ECG/Physio Monitoring | C | <1ms jitter | Signal generator | ADC HAT |
| 06 | Patient Data Mgmt | B | Non-RT | SQLite mock | eMMC Storage |
| 07 | Safety Watchdog | C | <100µs response | Timer mock | PMIC WDT |
| 08 | UI/Workflow Engine | A | <50ms render | Qt Desktop | Mali GPU |
| 09 | Visualization 3D | A | 60fps target | VTK Software | Adreno GPU |
| 10 | Recording/Storage | B | >100MB/s | /tmp ramdisk | NVMe/UFS |
| 11 | Security/Audit | B | Non-RT | Log file | TPM/HSM |
| 12 | Connectivity (HL7/FHIR) | B | Non-RT | REST mock | Ethernet/WiFi |
| 13 | Plugin Manager | A | <10ms load | dlopen mock | Secure Boot |

## Standard Module Template

Each module specification includes:
1. **Purpose & Scope**: Clinical function and boundaries
2. **Safety Classification**: IEC 62304 Class (A/B/C) with justification
3. **Interface Definition**: Input/output contracts, data types
4. **Performance Budgets**: Latency, jitter, throughput requirements
5. **Error Handling**: Failure modes, safe states, recovery procedures
6. **x86 Development Strategy**: Mock implementation for host testing
7. **QCS8550 Implementation**: Hardware-specific optimizations
8. **Verification Plan**: Unit tests, integration tests, HIL validation
9. **Regulatory Traceability**: Links to risk controls, user needs

## Sub-Specifications

- [01_Camera_Acquisition_Module.md](./01_Camera_Acquisition_Module.md) - Video pipeline from sensor to user space
- [02_AI_Inference_Module.md](./02_AI_Inference_Module.md) - Model loading, quantization, execution providers
- [03_DICOM_Networking_Module.md](./03_DICOM_Networking_Module.md) - SCP/SCU roles, TLS, storage commitment
- [04_Ultrasound_Beamforming_Module.md](./04_Ultrasound_Beamforming_Module.md) - Delay-and-sum, apodization, DSP offload
- [05_ECG_Physio_Monitoring_Module.md](./05_ECG_Physio_Monitoring_Module.md) - Analog front-end, filtering, arrhythmia detection
- [06_Patient_Data_Management.md](./06_Patient_Data_Management.md) - HL7 FHIR, database schema, privacy controls
- [07_Safety_Watchdog_Module.md](./07_Safety_Watchdog_Module.md) - Hardware/software watchdog hierarchy
- [08_UI_Workflow_Engine.md](./08_UI_Workflow_Engine.md) - State machine, user input handling
- [09_Visualization_3D_Module.md](./09_Visualization_3D_Module.md) - VTK pipeline, volume rendering, GPU acceleration
- [10_Recording_Streaming_Storage.md](./10_Recording_Streaming_Storage.md) - Ring buffers, compression, archival
- [11_Security_Audit_Module.md](./11_Security_Audit_Module.md) - ATNA compliance, tamper detection
- [12_Connectivity_HL7_FHIR.md](./12_Connectivity_HL7_FHIR.md) - REST APIs, message queuing
- [13_Plugin_Manager_Module.md](./13_Plugin_Manager_Module.md) - Dynamic loading, sandboxing, versioning

## Integration Guidelines

### Data Flow Architecture
- **Zero-Copy Pipeline**: Camera → ISP → Shared Memory → AI → Display
- **Priority Channels**: Critical data (ECG/AI alerts) use high-priority IPC queues
- **Backpressure Handling**: Drop frames vs. block based on safety class

### Cross-Platform Build
```bash
# x86 Development (Mock HAL)
cmake -B build_x86 -DPLATFORM=x86_64 -DMOCK_HAL=ON
cmake --build build_x86

# QCS8550 Target (Production HAL)
cmake -B build_arm -DCMAKE_TOOLCHAIN_FILE=aarch64-linux-gnu.cmake -DPLATFORM=qcs8550
cmake --build build_arm
```

### Testing Matrix
| Test Level | x86 Mock | ARM Target | HIL Required |
|------------|----------|------------|--------------|
| Unit Tests | ✅ Full coverage | ✅ Smoke test | ❌ |
| Integration | ✅ IPC mock | ✅ Real IPC | ❌ |
| Performance | ⚠️ Estimated | ✅ Measured | ✅ Validated |
| Safety/Fault | ✅ Simulated | ✅ Injected | ✅ Physical |

## Version History
- v0.1 (2024-05): Initial module definitions with safety classes
- v0.2 (2024-06): Added x86 mock strategies and performance budgets
