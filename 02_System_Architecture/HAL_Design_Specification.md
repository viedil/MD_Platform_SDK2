# Hardware Abstraction Layer (HAL) Design Specification

## 1. Overview
This document defines the Hardware Abstraction Layer (HAL) architecture for the Medical Device Platform SDK, enabling seamless development on x86 Linux hosts and deployment on Qualcomm QCS8550 ARM targets.

**Design Goal**: Write once, run anywhere - 90% of code runs unmodified on both architectures.

## 2. HAL Architecture

### 2.1 Layered Design
```
+---------------------------------------------------------------+
|                    Application Layer                          |
|  (Medical Algorithms, UI, Business Logic)                     |
|  - NO direct hardware access                                  |
|  - Uses HAL APIs exclusively                                  |
+---------------------------------------------------------------+
|                    HAL Interface Layer                        |
|  (Pure virtual C++ interfaces / C function pointers)          |
|  - camera_interface.h                                         |
|  - ai_accelerator_interface.h                                 |
|  - gpio_interface.h                                           |
|  - watchdog_interface.h                                       |
+---------------------------------------------------------------+
|                    HAL Implementation Layer                   |
|  +---------------------------+  +---------------------------+ |
|  |   x86 Mock Implementation |  |  QCS8550 ARM Implementation| |
|  |                           |  |                           | |
|  |  - v4l2loopback (camera)  |  |  - libcamera (ISP)        | |
|  |  - ONNX Runtime CPU       |  |  - QNN DSP/NPU            | |
|  |  - sysfs GPIO mock        |  |  - PMIC GPIO              | |
|  |  - Software watchdog      |  |  - Hardware WDT           | |
|  +---------------------------+  +---------------------------+ |
+---------------------------------------------------------------+
|                    Operating System Layer                     |
|  +---------------------------+  +---------------------------+ |
|  |   Ubuntu/Fedora (x86_64)  |  |  Yocto Linux (ARM64)      | |
|  +---------------------------+  +---------------------------+ |
+---------------------------------------------------------------+
|                    Hardware Layer                             |
|  +---------------------------+  +---------------------------+ |
|  |   Intel/AMD CPU + Webcam  |  |  QCS8550 SoC + Sensors    | |
|  +---------------------------+  +---------------------------+ |
+---------------------------------------------------------------+
```

### 2.2 Key Design Principles
1. **Interface Segregation**: Each hardware component has a dedicated interface
2. **Dependency Injection**: Implementations injected at runtime/build time
3. **Fail-Safe Defaults**: Mock implementations return safe values on error
4. **Deterministic Behavior**: Real-time constraints documented per API
5. **Testability**: All interfaces support unit testing with mocks

## 3. Core HAL Interfaces

### 3.1 Camera Interface

#### Interface Definition (`camera_interface.h`)
```cpp
#pragma once

#include <cstdint>
#include <functional>
#include <memory>

namespace md_sdk {
namespace hal {

enum class CameraFormat {
    RAW8,
    RAW10,
    RAW12,
    YUV420,
    YUV422,
    RGB888
};

struct CameraConfig {
    uint32_t width;
    uint32_t height;
    uint32_t fps;
    CameraFormat format;
    bool hdr_enabled;
};

struct ImageFrame {
    uint8_t* data;
    size_t size;
    uint32_t width;
    uint32_t height;
    CameraFormat format;
    int64_t timestamp_ns;  // Nanosecond precision
    uint32_t frame_id;
};

class ICamera {
public:
    virtual ~ICamera() = default;
    
    // Lifecycle
    virtual bool initialize(const CameraConfig& config) = 0;
    virtual void shutdown() = 0;
    
    // Capture
    virtual bool startCapture() = 0;
    virtual void stopCapture() = 0;
    virtual bool captureFrame(ImageFrame& frame, int timeout_ms) = 0;
    
    // Callbacks (for async operation)
    using FrameCallback = std::function<void(const ImageFrame&)>;
    virtual void setFrameCallback(FrameCallback callback) = 0;
    
    // Diagnostics
    virtual bool isHealthy() const = 0;
    virtual int getTemperature() const = 0;  // Celsius, if available
};

// Factory function (implemented per platform)
extern "C" std::unique_ptr<ICamera> createCameraInstance();

}  // namespace hal
}  // namespace md_sdk
```

#### x86 Mock Implementation Details
- **Backend**: v4l2loopback kernel module + ffmpeg
- **Video Source**: Pre-recorded medical imagery or synthetic test patterns
- **Timestamp Simulation**: Uses `clock_gettime(CLOCK_MONOTONIC)`
- **Error Injection**: Configurable via environment variables for testing
  ```bash
  export MOCK_CAMERA_DROP_RATE=0.01  # 1% frame drop
  export MOCK_CAMERA_LATENCY_MS=50   # Simulate 50ms latency
  ```

#### QCS8550 Implementation Details
- **Backend**: libcamera + Qualcomm ISP drivers
- **Pipeline**: Sensor → ISP → Memory (zero-copy)
- **DMA**: IOMMU-enabled for secure memory access
- **Performance**: Target < 30ms end-to-end latency at 60 FPS

---

### 3.2 AI Accelerator Interface

#### Interface Definition (`ai_accelerator_interface.h`)
```cpp
#pragma once

#include <vector>
#include <string>
#include <memory>

namespace md_sdk {
namespace hal {

struct ModelConfig {
    std::string model_path;
    std::vector<std::string> input_names;
    std::vector<std::string> output_names;
    std::vector<std::vector<int64_t>> input_shapes;
};

struct InferenceResult {
    std::vector<std::vector<float>> outputs;
    int64_t inference_time_us;  // Microseconds
    bool success;
    std::string error_message;
};

class IAIAccelerator {
public:
    virtual ~IAIAccelerator() = default;
    
    // Lifecycle
    virtual bool initialize() = 0;
    virtual void shutdown() = 0;
    
    // Model Management
    virtual bool loadModel(const ModelConfig& config) = 0;
    virtual void unloadModel() = 0;
    
    // Inference
    virtual InferenceResult runInference(
        const std::vector<std::vector<float>>& inputs) = 0;
    
    // Batch Inference (for throughput optimization)
    virtual std::vector<InferenceResult> runBatchInference(
        const std::vector<std::vector<std::vector<float>>>& inputs) = 0;
    
    // Diagnostics
    virtual bool isHealthy() const = 0;
    virtual float getUtilization() const = 0;  // 0.0 - 1.0
    virtual int getPowerConsumption() const = 0;  // Milliwatts
};

// Factory function
extern "C" std::unique_ptr<IAIAccelerator> createAIAcceleratorInstance();

}  // namespace hal
}  // namespace md_sdk
```

#### x86 Mock Implementation Details
- **Backend**: ONNX Runtime (CPU backend)
- **Optimization**: AVX2/AVX-512 vectorization enabled
- **Threading**: Configurable intra-op parallelism
- **Fallback**: If model uses unsupported ops, emit warning and approximate

#### QCS8550 Implementation Details
- **Backend**: Qualcomm QNN (Qualcomm Neural Network) SDK
- **Execution Providers**: 
  - DSP (Hexagon): For convolution-heavy models
  - NPU: For transformer-based models
  - GPU: Fallback for unsupported layers
- **Memory**: Zero-copy from camera ISP to AI accelerator
- **Performance Target**: < 15ms inference for ResNet-50

---

### 3.3 GPIO Interface

#### Interface Definition (`gpio_interface.h`)
```cpp
#pragma once

#include <cstdint>
#include <string>

namespace md_sdk {
namespace hal {

enum class GPIODirection {
    INPUT,
    OUTPUT
};

enum class GPIOValue {
    LOW = 0,
    HIGH = 1
};

class IGPIO {
public:
    virtual ~IGPIO() = default;
    
    // Configuration
    virtual bool configure(uint32_t pin, GPIODirection direction) = 0;
    
    // Read/Write
    virtual GPIOValue read(uint32_t pin) = 0;
    virtual bool write(uint32_t pin, GPIOValue value) = 0;
    
    // Advanced Features
    virtual bool setPullResistor(uint32_t pin, bool enable_pullup) = 0;
    virtual bool setDriveStrength(uint32_t pin, uint32_t ma) = 0;
    
    // Interrupts (optional, for input pins)
    using InterruptCallback = std::function<void(uint32_t pin, GPIOValue value)>;
    virtual bool enableInterrupt(uint32_t pin, bool rising_edge, 
                                  bool falling_edge, InterruptCallback cb) = 0;
    virtual void disableInterrupt(uint32_t pin) = 0;
    
    // Diagnostics
    virtual bool isHealthy() const = 0;
};

// Factory function
extern "C" std::unique_ptr<IGPIO> createGPIOInstance();

}  // namespace hal
}  // namespace md_sdk
```

#### x86 Mock Implementation Details
- **Backend**: File-based mock system in `/tmp/mock_gpio/`
- **Persistence**: GPIO state survives process restart (for testing)
- **Logging**: All operations logged to syslog for debugging
- **Example**:
  ```bash
  $ echo "1" > /tmp/mock_gpio/pin_5/value  # Simulate button press
  $ cat /tmp/mock_gpio/pin_12/value         # Read LED state
  ```

#### QCS8550 Implementation Details
- **Backend**: Linux sysfs GPIO (/sys/class/gpio) or libgpiod
- **Pin Mapping**: Board-specific pinout defined in device tree
- **Real-Time**: GPIO toggling latency < 5 µs
- **Safety**: Critical pins (e.g., therapy enable) use hardware interlocks

---

### 3.4 Watchdog Interface

#### Interface Definition (`watchdog_interface.h`)
```cpp
#pragma once

#include <cstdint>

namespace md_sdk {
namespace hal {

class IWatchdog {
public:
    virtual ~IWatchdog() = default;
    
    // Configuration
    virtual bool configure(uint32_t timeout_ms) = 0;
    
    // Lifecycle
    virtual bool start() = 0;
    virtual void stop() = 0;
    
    // Kick (pet) the watchdog
    virtual bool kick() = 0;
    
    // Status
    virtual bool isRunning() const = 0;
    virtual bool hasExpired() const = 0;  // Check if expired since last kick
    
    // Debug (development only)
    virtual void forceExpire() = 0;  // Test reset functionality
};

// Factory function
extern "C" std::unique_ptr<IWatchdog> createWatchdogInstance();

}  // namespace hal
}  // namespace md_sdk
```

#### x86 Mock Implementation Details
- **Backend**: Userspace timer thread
- **Behavior**: Logs warnings when not kicked, does NOT reset system
- **Testing**: `forceExpire()` triggers SIGABRT for crash handler testing
- **Configuration**:
  ```bash
  export MOCK_WDT_ACTION=log  # Options: log, abort, ignore
  ```

#### QCS8550 Implementation Details
- **Backend**: Hardware watchdog timer (QCOM WDT)
- **Cascade Strategy**:
  - Level 1: Soft reset (application restart) at 500ms
  - Level 2: Hard reset (full system reboot) at 2s
- **Safe Mode**: If watchdog expires 3x in 1 minute, boot to safe mode
- **Integration**: Kicked by main control loop (must run at ≥ 10 Hz)

## 4. Build System Integration

### 4.1 CMake Configuration
```cmake
# Detect target architecture
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64")
    set(HAL_PLATFORM "x86_mock")
    message(STATUS "Building x86 Mock HAL")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(HAL_PLATFORM "qcs8550")
    message(STATUS "Building QCS8550 HAL")
else()
    message(FATAL_ERROR "Unsupported architecture")
endif()

# Add HAL implementation
add_subdirectory(hal/${HAL_PLATFORM})

# Link against HAL
target_link_libraries(my_app PRIVATE hal_core hal_${HAL_PLATFORM})
```

### 4.2 Runtime Detection (Optional)
For hybrid binaries that auto-detect platform:
```cpp
std::unique_ptr<hal::ICamera> createCamera() {
    struct utsname buf;
    uname(&buf);
    
    if (strstr(buf.machine, "x86_64")) {
        return std::make_unique<hal::MockCamera>();
    } else if (strstr(buf.machine, "aarch64")) {
        return std::make_unique<hal::QCSCamera>();
    }
    throw std::runtime_error("Unknown platform");
}
```

## 5. Testing Strategy

### 5.1 Unit Tests (x86)
- **Framework**: GoogleTest + GoogleMock
- **Coverage**: 100% branch coverage on HAL interfaces
- **Example**:
  ```cpp
  TEST(CameraTest, CaptureFrame_Success) {
      auto camera = hal::createCameraInstance();
      ASSERT_TRUE(camera->initialize(config));
      
      hal::ImageFrame frame;
      EXPECT_TRUE(camera->captureFrame(frame, 1000));
      EXPECT_GT(frame.size, 0);
  }
  ```

### 5.2 Hardware-in-the-Loop (HIL) Tests (ARM)
- **Setup**: QCS8550 dev board + automated test jig
- **Tests**: Timing validation, thermal performance, power consumption
- **Automation**: Jenkins CI triggers HIL tests nightly

### 5.3 Performance Validation
| API | x86 Target | QCS8550 Target | Measurement Method |
|-----|------------|----------------|-------------------|
| Camera capture | < 100 ms | < 30 ms | Oscilloscope + timestamps |
| AI inference | < 50 ms | < 15 ms | `clock_gettime()` |
| GPIO toggle | < 10 µs | < 5 µs | Logic analyzer |
| Watchdog kick | < 1 ms | < 100 µs | Tracing |

## 6. Migration Checklist (x86 → ARM)

Before deploying to QCS8550 hardware:

- [ ] All HAL interfaces implemented and tested on ARM
- [ ] Performance benchmarks meet targets (see Section 5.3)
- [ ] Error handling validated (simulate hardware failures)
- [ ] Power consumption measured under worst-case load
- [ ] Thermal testing completed (no throttling at max load)
- [ ] Watchdog integration verified (system recovers from hangs)
- [ ] Secure boot validates HAL binaries
- [ ] SBOM generated for all HAL dependencies

## 7. Documentation & Traceability
- **Requirements**: SYS-REQ-HAL-001 through SYS-REQ-HAL-025
- **Risk Controls**: RC-SAF-006 (hardware abstraction), RC-SAF-007 (mock testing)
- **Test Reports**: TR-HAL-001 (HAL Validation Report)

---
**Document Control**
- Version: 1.0
- Status: Released
- Author: System Architecture Team
- Review Date: 2024-Q2
