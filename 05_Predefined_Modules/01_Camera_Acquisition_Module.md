# 01_Camera_Acquisition_Module

## 1. Purpose & Scope
Captures raw video frames from medical imaging sensors (endoscopy, ultrasound probe, microscopy) and delivers processed frames to the media pipeline. Supports multiple sensor formats (MIPI CSI-2, USB3 Vision, SDI).

## 2. Safety Classification: **IEC 62304 Class B**
**Justification**: Software failure could cause incorrect diagnosis (e.g., dropped frames during critical procedure) but not direct patient harm. Requires risk controls for frame loss detection.

## 3. Interface Definition

### Input Contracts
```cpp
struct CameraConfig {
    uint32_t width;          // e.g., 1920, 3840
    uint32_t height;         // e.g., 1080, 2160
    uint32_t fps;            // Target framerate (30, 60)
    PixelFormat format;      // NV12, RGB24, RAW12
    int exposure_time_us;    // Manual exposure control
    int gain_db;             // Sensor gain
};
```

### Output Contracts
```cpp
struct VideoFrame {
    uint64_t timestamp_ns;   // Monotonic capture time
    uint32_t sequence_num;   // Frame counter for gap detection
    std::shared_ptr<uint8_t[]> data;  // Zero-copy shared memory
    size_t data_size;
    FrameStatus status;      // OK, DROPPED, CORRUPTED
};
```

## 4. Performance Budgets
| Metric | Requirement | Measurement Method |
|--------|-------------|-------------------|
| End-to-End Latency | <16ms (60fps) | Timestamp delta (sensor → user space) |
| Jitter | <1ms stddev | Inter-frame arrival variance |
| Frame Drop Rate | <0.01% | Sequence number gap analysis |
| CPU Usage | <15% (1 core) | `top`/`perf` during capture |

## 5. Error Handling

### Failure Modes & Safe States
| Fault | Detection | Safe State | Recovery |
|-------|-----------|------------|----------|
| Sensor disconnect | GPIO interrupt | Last frame hold + overlay warning | Auto-reconnect (max 3 attempts) |
| Buffer overflow | Ring buffer full flag | Drop oldest frame | Increase buffer pool |
| Corruption (CRC fail) | Hardware CRC check | Discard frame | Request keyframe |
| Overtemperature | Thermal sensor >85°C | Reduce FPS by 50% | Active cooling trigger |

### State Machine
```
INIT → STANDBY → CAPTURING → [ERROR] → RECOVERING → CAPTURING
                      ↓
                 STOPPED
```

## 6. x86 Development Strategy (Mock HAL)

### Implementation: `CameraHAL_Mock.cpp`
```cpp
// Uses v4l2loopback kernel module to create virtual camera devices
// Example: /dev/video10 becomes a mock camera source

class CameraHAL_Mock : public ICameraHAL {
public:
    void init(const CameraConfig& config) override {
        // Open /dev/video10 (created by: modprobe v4l2loopback devices=1)
        // Feed pre-recorded medical video loop via ffmpeg:
        // ffmpeg -re -i sample_endoscopy.mp4 -f v4l2 /dev/video10
    }
    
    VideoFrame capture() override {
        // Read from v4l2 device with non-blocking I/O
        // Inject synthetic noise/corruption for fault testing
    }
};
```

### Testing on x86
```bash
# 1. Install v4l2loopback
sudo apt install v4l2loopback-dkms
sudo modprobe v4l2loopback devices=1 card_label="MockCam"

# 2. Feed test video stream
ffmpeg -re -i test_medical_video.mp4 -f v4l2 -pix_fmt nv12 /dev/video10

# 3. Run unit tests with mock backend
./build_x86/tests/camera_test --mock-backend --test-fault-injection
```

## 7. QCS8550 Implementation (Production HAL)

### Hardware-Specific Optimizations
- **ISP Integration**: Use Qualcomm Spectra ISP for auto-exposure, denoise, color correction
- **DMA Direct**: Zero-copy from ISP to shared memory (ION buffers)
- **Device Tree**: Configure MIPI CSI-2 lanes (4-lane, 2.5Gbps/lane)
- **V4L2 Drivers**: `qcom_cam_v4l2` with real-time priority patches

### Code Structure
```
drivers/media/platform/qcom/camera/
├── msm_camera.c      // Main V4L2 driver
├── csi_phy.c         // MIPI PHY configuration
├── isp_config.xml    // ISP tuning parameters (AE/AWB/AF)
└── ion_allocator.cpp // Shared memory allocation
```

## 8. Verification Plan

### Unit Tests (x86 Mock)
- [ ] Frame format validation (resolution, pixel format)
- [ ] Sequence number continuity (no gaps in 1M frames)
- [ ] Timestamp monotonicity
- [ ] Fault injection (disconnect, corruption, overflow)

### Integration Tests (ARM Target)
- [ ] End-to-end latency measurement (camera → display)
- [ ] Multi-camera synchronization (stereo rigs)
- [ ] Thermal throttling behavior

### HIL Validation
- [ ] Real sensor integration (Sony IMX series)
- [ ] EMI/EMC interference testing
- [ ] Long-duration soak test (72h continuous capture)

## 9. Regulatory Traceability

| Risk ID | Hazard | Control Measure | Test Case |
|---------|--------|-----------------|-----------|
| R-001 | Lost frame during surgery | Sequence number monitoring + alarm | TC-CAM-007 |
| R-002 | Incorrect color reproduction | ISP calibration + color chart validation | TC-CAM-012 |
| R-003 | Latency >100ms causes motion sickness | Real-time scheduling + priority boosting | TC-CAM-005 |

## 10. References
- **MIPI CSI-2 Specification v3.0**
- **V4L2 API Documentation**: https://www.kernel.org/doc/html/v4l2/
- **Qualcomm Spectra ISP Programming Guide** (NDA)
- **IEC 62304 Clause 5.1.1**: Software Item Requirements
