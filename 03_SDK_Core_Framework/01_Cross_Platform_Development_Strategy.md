# Cross-Platform Development Strategy: x86 Linux → Qualcomm QCS8550

## 1. Overview

This document defines the strategy for designing, developing, and testing the Medical Device Platform SDK on **Intel x86_64 Linux** hosts before porting to the **Qualcomm QCS8550 (ARM64)** target. This approach maximizes developer productivity, enables rapid iteration, and ensures robust CI/CD pipelines while maintaining strict compatibility with the final embedded target.

### Core Philosophy: "Develop on x86, Validate on ARM"
- **90% of development** (logic, algorithms, UI, unit tests) happens on x86.
- **10% of development** (hardware acceleration, BSP integration, thermal/power tuning) happens on QCS8550.
- **Binary Compatibility** is enforced via cross-compilation and containerized build environments.

---

## 2. Architecture Abstraction Layers

To ensure code portability, the SDK must be designed with strict abstraction layers. Code touching hardware-specific APIs must be isolated.

### 2.1 The Abstraction Stack

```text
+---------------------------------------------------------------+
|  Application Layer (Module Plugins, Clinical Apps)            |
|  (Pure C++ / Python / Qt - 100% Portable)                     |
+---------------------------------------------------------------+
|  SDK Core Framework (Service Bus, Logging, Config)            |
|  (Pure C++ - 100% Portable)                                   |
+---------------------------------------------------------------+
|  Hardware Abstraction Layer (HAL)                             |
|  +----------------+  +----------------+  +----------------+   |
|  | Camera HAL     |  | AI Inference   |  | GPIO/IO        |   |
|  | (Interface)    |  | (Interface)    |  | (Interface)    |   |
|  +-------+--------+  +-------+--------+  +-------+--------+   |
|          |                   |                   |            |
|  +-------v--------+  +-------v--------+  +-------v--------+   |
|  | V4L2 (x86/ARM) |  | ONNX/QNN     |  | Sysfs/GPIO     |   |
|  | Mock Driver    |  | Mock Runtime |  | Mock Driver    |   |
|  +----------------+  +----------------+  +----------------+   |
+---------------------------------------------------------------+
|  OS Kernel (Ubuntu x86_64  vs  Linux ARM64 QCS8550)           |
+---------------------------------------------------------------+
```

### 2.2 Implementation Rules
1.  **No Direct Hardware Calls in Core Logic**: Application code must never call `ioctl`, `mmap`, or vendor-specific libraries (e.g., `libqnn.so`) directly.
2.  **Interface-First Design**: Define pure virtual C++ interfaces or C function pointers for all hardware interactions.
3.  **Mock Implementations**: Provide "Null" or "Mock" implementations for every HAL interface that run on x86 using simulated data.

---

## 3. Development Environment Setup (x86 Host)

### 3.1 Prerequisites
- **OS**: Ubuntu 22.04 LTS or 24.04 LTS (matches target rootfs).
- **Toolchain**: GCC 11+, Clang 14+, CMake 3.24+.
- **Containerization**: Docker/Podman (mandatory for consistent sysroot).

### 3.2 Directory Structure
```text
sdk-root/
├── build_x86/              # Native x86 build artifacts
├── build_arm64/            # Cross-compiled ARM64 artifacts
├── docker/                 # Build container definitions
│   ├── Dockerfile.x86      # Dev environment
│   └── Dockerfile.cross    # Cross-compile environment
├── src/
│   ├── core/               # Portable core logic
│   ├── hal/                # Hardware Abstraction Layer
│   │   ├── interface/      # Pure abstract headers
│   │   ├── mock/           # x86 simulation implementations
│   │   └── qcs8550/        # Qualcomm specific implementations
│   └── modules/            # Clinical modules
├── tests/
│   ├── unit/               # GoogleTest (runs on x86)
│   └── integration/        # Runs in Docker or on Target
└── tools/
    ├── simulate_camera.py  # Generates test video streams
    └── inject_ai_data.sh   # Feeds mock tensor data
```

### 3.3 CMake Configuration Strategy
Use a unified `CMakeLists.txt` that detects the architecture and swaps HAL implementations.

```cmake
# CMakeLists.txt snippet
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
    message(STATUS "Building for x86_64 (Mock HAL)")
    set(HAL_IMPL_SRC 
        src/hal/mock/camera_mock.cpp
        src/hal/mock/ai_engine_mock.cpp
        src/hal/mock/gpio_mock.cpp
    )
    add_definitions(-DPLATFORM_X86)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
    message(STATUS "Building for ARM64 (QCS8550 HAL)")
    set(HAL_IMPL_SRC 
        src/hal/qcs8550/camera_v4l2_qcom.cpp
        src/hal/qcs8550/ai_engine_qnn.cpp
        src/hal/qcs8550/gpio_sysfs.cpp
    )
    add_definitions(-DPLATFORM_QCS8550)
endif()

add_library(sdk_hal ${HAL_IMPL_SRC})
```

---

## 4. Simulation & Mocking Strategy

Since x86 lacks the Qualcomm Hexagon DSP, specific camera ISPs, and medical-grade IO, you must simulate them.

### 4.1 Camera Subsystem Simulation
- **Challenge**: QCS8550 uses specific ISP pipelines; x86 has standard UVC webcams or none.
- **Solution**: `v4l2loopback` driver.
  1.  Install `v4l2loopback-dkms`.
  2.  Create a virtual device: `sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="MedCam_Mock"`.
  3.  Feed pre-recorded DICOM/RAW video sequences (from `testdata/`) into `/dev/video10` using `ffmpeg`.
  4.  SDK reads `/dev/video10` exactly as it would read the real MIPI CSI camera on QCS8550.

```bash
# Loop a high-res medical video stream
ffmpeg -re -i sample_ct_scan.mp4 -f v4l2 /dev/video10
```

### 4.2 AI Accelerator Simulation
- **Challenge**: No Hexagon DSP on x86.
- **Solution**: Backend Swapping via ONNX Runtime.
  - **Target (ARM)**: Uses `QNN EP` (Qualcomm Neural Network Execution Provider).
  - **Dev (x86)**: Uses `CPU EP` or `OpenVINO EP` (Intel).
  - **Code**: The SDK loads the model via a generic `InferenceEngine` interface. The backend is selected via config.

```json
// config.json (x86)
{
  "ai_backend": "onnx_cpu",
  "model_path": "models/lung_nodule_detector.onnx",
  "threads": 8
}
```

```json
// config.json (QCS8550)
{
  "ai_backend": "qnn_dsp",
  "model_path": "models/lung_nodule_detector.qnn",
  "dsp_priority": "high"
}
```

### 4.3 GPIO & Safety IO Simulation
- **Challenge**: No physical E-Stop or foot pedal inputs on dev laptop.
- **Solution**: File-based Mock GPIO.
  - Map GPIO reads/writes to files in `/tmp/mock_gpio/`.
  - Tooling allows developers to "toggle" switches by writing to these files.

```cpp
// Mock GPIO Implementation
bool MockGpio::read(int pin) {
    std::ifstream file("/tmp/mock_gpio/pin_" + std::to_string(pin));
    int val; file >> val;
    return val == 1;
}
```

---

## 5. Cross-Compilation Workflow

When code passes x86 tests, build for ARM64 to verify compilation and linkage against QCS8550 libraries.

### 5.1 Toolchain Setup
Use the Linaro GCC toolchain or Qualcomm's provided SDK toolchain.

```dockerfile
# Dockerfile.cross
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    cmake qemu-user-static
# Copy QCS8550 Sysroot (libraries, headers)
COPY sysroot_qcs8550 /opt/qcs8550-sysroot
```

### 5.2 Build Command
```bash
cmake -B build_arm64 \
  -DCMAKE_TOOLCHAIN_FILE=toolchains/aarch64-linux-gnu.cmake \
  -DSYSROOT_PATH=/opt/qcs8550-sysroot \
  -DENABLE_QNN_LIBS=ON
cmake --build build_arm64
```

### 5.3 Static Analysis (Architecture Agnostic)
Run these on x86 to catch errors before cross-compiling:
- **clang-tidy**: Enforce coding standards.
- **cppcheck**: Detect memory leaks.
- **sonarqube**: Technical debt tracking.

---

## 6. Testing Strategy Matrix

| Test Type | Environment | Frequency | Tools | Goal |
| :--- | :--- | :--- | :--- | :--- |
| **Unit Tests** | x86 Native | Every Commit | GoogleTest, Catch2 | Verify logic, algorithms, math. |
| **Integration Tests** | x86 (Docker) | Nightly | GTest, Python Scripts | Verify module interaction, Mock HALs. |
| **Performance Profiling** | x86 Native | Weekly | perf, Valgrind, Callgrind | Identify algorithmic bottlenecks (ignoring HW accel). |
| **Cross-Compile Check** | x86 Host | Every PR | CMake, Ninja | Ensure code compiles for ARM. |
| **Hardware-in-Loop (HIL)** | QCS8550 Board | Nightly / Pre-Release | CTest, Custom Harness | Verify DSP offload, Thermal, Real Camera. |
| **Regulatory Verification** | QCS8550 Board | Milestone | Traceability Matrix | Final validation for FDA/CE. |

---

## 7. CI/CD Pipeline Design

The pipeline runs entirely on x86 servers (e.g., GitHub Actions, GitLab CI, Jenkins) except for the final HIL stage.

```mermaid
graph TD
    A[Code Commit] --> B{Static Analysis};
    B -->|Fail| C[Reject];
    B -->|Pass| D[Build x86 Debug];
    D --> E[Run Unit Tests (Mock HAL)];
    E -->|Fail| C;
    E -->|Pass| F[Cross-Compile ARM64];
    F -->|Fail| C;
    F -->|Pass| G[Deploy to QCS8550 Lab];
    G --> H[Run Hardware Integration Tests];
    H -->|Fail| I[Alert Engineers];
    H -->|Pass| J[Generate Artifacts & SBOM];
```

### 7.1 Emulation (Optional Advanced Step)
For basic sanity checks without hardware:
- Use **QEMU User Mode** to run ARM64 binaries on x86.
- *Limitation*: Cannot test actual DSP instructions or hardware drivers, only user-space logic.

```bash
# Run ARM binary on x86 via QEMU
qemu-aarch64 -L /opt/qcs8550-sysroot ./build_arm64/bin/sdk_app --test-mode
```

---

## 8. Porting Checklist: Moving to QCS8550

When ready to port to the actual board, follow this sequence:

1.  **Board Bring-up**: Ensure Yocto/Buildroot image is running with basic networking.
2.  **Sysroot Sync**: Extract headers/libs from board to x86 (`rsync` or SDK manager).
3.  **HAL Swap**: Switch CMake flag to `PLATFORM_QCS8550`.
4.  **Library Linking**: Ensure `libqnn.so`, `libion.so`, and vendor blobs are in the linker path.
5.  **Permission Tuning**: Configure udev rules for camera/DSP access (`/dev/ion`, `/dev/video*`).
6.  **Thermal/Power Profiles**: Enable `thermald` and GPU/DSP frequency governors.
7.  **Real Data Validation**: Replace mock video streams with real camera input.
8.  **Latency Measurement**: Re-run benchmarks (expect different numbers than x86).

---

## 9. Common Pitfalls & Mitigations

| Pitfall | Impact | Mitigation |
| :--- | :--- | :--- |
| **Endianness Assumptions** | Data corruption on ARM | Use `htons`, `ntohs`, and fixed-width types (`uint32_t`). Never assume `int` size. |
| **Alignment Issues** | SIGBUS crashes on ARM | Use `__attribute__((packed))` carefully. Align structs to 64-bit boundaries for DSP. |
| **Floating Point Math** | Slight result variations | Avoid strict equality checks (`==`) in tests. Use epsilon comparison. |
| **Hardcoded Paths** | Build failures | Use CMake variables and environment offsets. |
| **Timing Dependencies** | Race conditions | x86 is often faster/slower differently than ARM. Use proper mutexes/semaphores, not `sleep()`. |

---

## 10. References
- **CMake Cross Compiling**: https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html
- **QNN SDK Documentation**: Qualcomm Developer Network
- **V4L2 Loopback**: https://github.com/umlaeute/v4l2loopback
- **ONNX Runtime Execution Providers**: https://onnxruntime.ai/docs/execution-providers/
