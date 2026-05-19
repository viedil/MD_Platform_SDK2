# Performance Benchmarks and Thermal

## Targets

| Metric                        | Target          | Measurement                          |
| ----------------------------- | --------------- | ------------------------------------ |
| Video Pipeline Latency (4K60) | ≤18 ms          | DMA-BUF timestamp diff, oscilloscope |
| AI Inference (CADe)           | ≤28 ms/frame    | ONNX/SNPE profiler, CPU/GPU/NPU util |
| Safety Bridge IPC Latency     | ≤85 µs          | CAN-FD/TSN timestamp, logic analyzer |
| UI Frame Consistency          | ≤16.6 ms/jitter | Qt perf tool, frame drop counter     |
| Boot to Ready (Clinical)      | ≤15 s           | Systemd-analyze, secure boot chain   |

## Thermal Profiles

* **Active**: Fan + heatsink, full NPU/GPU load
* **Passive**: DVFS limit, AI fallback to CPU, reduced FPS
* **Guard API**: `thermal.set_policy(Passive)` triggers graceful degradation 
