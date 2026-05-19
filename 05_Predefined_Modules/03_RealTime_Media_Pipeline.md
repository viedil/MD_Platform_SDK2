# 03 Real-Time Media Pipeline Module

## 1. Purpose
Provides a high-throughput, low-latency pipeline for streaming media data from acquisition to processing/display with zero-copy memory management.

## 2. Safety Classification (IEC 62304)
- **Safety Class**: B (Data loss could delay diagnosis but not cause direct harm if redundant paths exist).
- **Critical Functions**: Frame timestamp integrity, buffer overflow protection.

## 3. Architecture
- **Graph-Based Engine**: Nodes (Source, Filter, Sink) connected by edges (Buffers).
- **Zero-Copy Buffers**: Uses `dma_buf` (Linux) for sharing between Camera ISP, AI NPU, and Display.
- **Scheduler**: Real-time thread priority inheritance for pipeline threads.

## 4. x86 Mock Strategy
- **Mock Pipeline**: Uses shared memory segments (`/dev/shm`) to simulate DMA buffers.
- **Latency Injection**: Configurable delay nodes to test timeout handling.
- **Test Data**: Pre-recorded YUV/RGB sequences looped indefinitely.

## 5. Performance Budgets
- **End-to-End Latency**: < 33ms (30fps) for Camera → AI → Display path.
- **Jitter**: < 1ms standard deviation.
- **Throughput**: Sustained 4K @ 60fps or 8K @ 30fps.

## 6. API Specification
```cpp
class IPipeline {
public:
    virtual Result<void> addNode(std::shared_ptr<INode> node) = 0;
    virtual Result<void> connect(const std::string& src, const std::string& dst) = 0;
    virtual Result<void> start() = 0;
    virtual void flush() = 0; // Critical for safety state reset
};
```

## 7. Verification Requirements
- [ ] Verify zero-copy path is active (no `memcpy` in hot path).
- [ ] Verify pipeline drains completely on `stop()` within 100ms.
- [ ] Verify frame timestamps are monotonic and synchronized to system clock.
