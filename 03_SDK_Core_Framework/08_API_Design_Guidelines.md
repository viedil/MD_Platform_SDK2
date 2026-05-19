# API Design Guidelines

## 1. Overview
This document establishes coding standards and API design principles for the Medical Device Platform SDK, ensuring safety, reliability, and maintainability per IEC 62304 Class C requirements.

### 1.1 Scope
- Applies to all public SDK APIs, internal modules, and plugin interfaces.
- Mandates C++17/20 with strict subsets for safety-critical code.
- Defines error handling, memory management, and concurrency patterns.

## 2. Language Standards

### 2.1 C++ Version Policy
| Component | Standard | Rationale |
|-----------|----------|-----------|
| SDK Core | C++17 | Broad compiler support, mature features |
| AI Modules | C++20 | Concepts, ranges for ML pipelines |
| Safety-Critical | C++17 (restricted) | No exceptions, no RTTI |

### 2.2 Forbidden Features (Safety-Critical Code)
```cpp
// ❌ PROHIBITED in safety-critical paths
throw std::runtime_error("...");      // Use Result<T> instead
dynamic_cast<...>(...)                // Unpredictable timing
std::async(...)                       // Non-deterministic scheduling
new/delete                            // Use smart pointers only
goto                                  // Structured control flow only
```

### 2.3 Required Features
```cpp
// ✅ MANDATORY patterns
#include <memory>                     // Smart pointers only
#include <expected>                   // C++23 std::expected or custom Result<T>
#include <chrono>                     // Explicit time units
#include <span>                       // Bounds-checked views
```

## 3. Memory Management

### 3.1 Ownership Rules
- **No Raw Pointers**: All dynamic allocation must use `std::unique_ptr` or `std::shared_ptr`.
- **Stack Allocation Preferred**: Use `std::array` over `std::vector` for fixed-size data.
- **Custom Allocators**: Required for real-time paths to avoid heap fragmentation.

```cpp
// ✅ Correct: Stack allocation for fixed buffers
std::array<uint8_t, 4096> image_buffer;

// ✅ Correct: Smart pointer for dynamic data
auto frame = std::make_unique<CameraFrame>(width, height);

// ❌ Incorrect: Raw new/delete
CameraFrame* frame = new CameraFrame(...);  // VIOLATION
delete frame;
```

### 3.2 Zero-Copy Data Passing
Use `std::span` for passing buffer views without copying:
```cpp
void ProcessImage(std::span<const uint8_t> input, std::span<uint8_t> output);
```

### 3.3 Memory Pools
For real-time threads, pre-allocate pools:
```cpp
class FramePool {
public:
    std::unique_ptr<CameraFrame> acquire();
    void release(std::unique_ptr<CameraFrame> frame);
private:
    std::vector<std::unique_ptr<CameraFrame>> pool_;
};
```

## 4. Error Handling

### 4.1 Result<T> Pattern
Replace exceptions with explicit error types:
```cpp
template<typename T, typename E = std::error_code>
class Result {
public:
    static Result Ok(T value);
    static Result Err(E error);
    
    bool is_ok() const;
    T value() const;      // Panics if error
    E error() const;      // Panics if ok
};
```

### 4.2 Error Code Enumeration
```cpp
enum class MedicalErrorCode {
    Success = 0,
    CameraTimeout = 1001,
    AIModelNotFound = 2001,
    NetworkUnreachable = 3001,
    InvalidParameter = 4001,
    ResourceExhausted = 5001
};

// Usage
Result<ImageData> CaptureFrame() {
    if (!camera_->IsReady()) {
        return Result<ImageData>::Err(MedicalErrorCode::CameraTimeout);
    }
    // ...
}
```

### 4.3 Error Propagation
```cpp
Result<void> StartAcquisition() {
    auto cam_result = camera_->Initialize();
    if (!cam_result.is_ok()) {
        return Result<void>::Err(cam_result.error());  // Propagate
    }
    
    auto ai_result = ai_engine_->LoadModel();
    if (!ai_result.is_ok()) {
        camera_->Shutdown();  // Cleanup before return
        return Result<void>::Err(ai_result.error());
    }
    
    return Result<void>::Ok();
}
```

## 5. Concurrency & Thread Safety

### 5.1 Threading Model
- **Main Thread**: UI, configuration (non-real-time)
- **Acquisition Thread**: Camera capture (hard real-time, priority 90+)
- **Processing Thread**: AI inference (soft real-time, priority 50-80)
- **I/O Thread**: Network, storage (best-effort, priority 10-30)

### 5.2 Synchronization Primitives
| Primitive | Use Case | Header |
|-----------|----------|--------|
| `std::atomic` | Lock-free counters, flags | `<atomic>` |
| `std::mutex` | General protection | `<mutex>` |
| `std::condition_variable` | Producer-consumer | `<condition_variable>` |
| `std::latch` / `std::barrier` | Phase synchronization (C++20) | `<latch>` |

### 5.3 Real-Time Safe Patterns
```cpp
// ✅ RT-Safe: Lock-free queue for frame passing
struct FrameQueue {
    std::atomic<CameraFrame*> head{nullptr};
    
    void push(CameraFrame* frame) {
        CameraFrame* old_head = head.load(std::memory_order_relaxed);
        frame->next = old_head;
        while (!head.compare_exchange_weak(old_head, frame,
                                           std::memory_order_release,
                                           std::memory_order_relaxed));
    }
};

// ❌ NOT RT-Safe: std::mutex with priority inversion risk
std::mutex m;
m.lock();  // May block indefinitely
```

### 5.4 Thread Annotation Macros
```cpp
#define THREAD_SAFE __attribute__((annotate("thread_safe")))
#define REQUIRES_LOCK(mutex) __attribute__((requires_lock(mutex)))

class THREAD_SAFE CameraDriver {
public:
    void Start() REQUIRES_LOCK(init_mutex_);
private:
    std::mutex init_mutex_;
};
```

## 6. API Naming Conventions

### 6.1 Function Names
- **Verbs for Actions**: `Start()`, `Stop()`, `Capture()`, `Process()`
- **Get/Set for Properties**: `GetGain()`, `SetExposure()`
- **Is/Has for Booleans**: `IsReady()`, `HasFrame()`

### 6.2 Type Names
- **Classes/Structs**: PascalCase (`CameraFrame`, `AIEngine`)
- **Interfaces**: `I` prefix (`ICamera`, `IProcessor`)
- **Enums**: PascalCase with scoped values (`ErrorCode::Timeout`)

### 6.3 Constants
- **Global Constants**: `kMaxFrameSize`, `kDefaultTimeout`
- **Magic Numbers**: Never use; define named constants

## 7. Documentation Requirements

### 7.1 Doxygen Format
```cpp
/**
 * @brief Captures a single frame from the camera sensor.
 * 
 * @param timeout_ms Maximum time to wait for frame (milliseconds).
 * @return Result<CameraFrame> Ok(frame) on success, Err(error) on failure.
 * 
 * @pre Camera must be initialized via Initialize().
 * @post Frame buffer is owned by caller; must be released via ReleaseFrame().
 * 
 * @throws None (uses Result<T> pattern)
 * 
 * @note This function is thread-safe and real-time safe.
 * 
 * @example
 * ```cpp
 * auto result = camera->CaptureFrame(100);
 * if (result.is_ok()) {
 *     ProcessImage(result.value());
 * }
 * ```
 */
Result<CameraFrame> CaptureFrame(uint32_t timeout_ms);
```

### 7.2 Required Documentation Sections
Every public API must include:
- **Brief**: One-line summary
- **Parameters**: All input/output parameters
- **Return Value**: Success/failure semantics
- **Preconditions**: State requirements before call
- **Postconditions**: State guarantees after call
- **Thread Safety**: Explicit statement
- **Real-Time Safety**: RT-safe or non-RT-safe
- **Example**: Usage snippet

## 8. Versioning & Deprecation

### 8.1 Semantic Versioning
- **MAJOR**: Breaking API changes
- **MINOR**: Backward-compatible feature additions
- **PATCH**: Bug fixes, no API changes

### 8.2 Deprecation Policy
```cpp
// Mark deprecated with version and removal timeline
[[deprecated("Since v2.1; use SetGain(float) instead. Removed in v3.0")]]
void SetGain(int gain);

// Provide migration path in documentation
```

### 8.3 ABI Compatibility
- Maintain ABI stability within major versions.
- Use `extern "C"` for plugin interfaces to ensure C ABI stability.

## 9. Testing Requirements

### 9.1 Unit Test Coverage
- **Minimum 90%** line coverage for all public APIs.
- **100% branch coverage** for error handling paths.

### 9.2 Property-Based Testing
Use frameworks like RapidCheck for invariant validation:
```cpp
TEST(FrameBufferTest, SizeInvariant) {
    rapidcheck::forAll([](int w, int h) {
        RC_PRE(w > 0 && h > 0);
        CameraFrame frame(w, h);
        RC_ASSERT(frame.GetSize() == w * h * 3);  // RGB format
    });
}
```

## 10. References
- ISO/IEC 14882:2017 (C++17 Standard)
- MISRA C++:2008 Guidelines (adapted for medical)
- Google C++ Style Guide (with modifications)
- IEC 62304 Software Lifecycle Requirements
