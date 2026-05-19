# 10 Recording, Streaming, and Storage Module

## 1. Purpose
Handles persistent storage of medical images/videos, real-time streaming to external devices, and lifecycle management of stored data.

## 2. Safety Classification (IEC 62304)
- **Safety Class**: B (Data loss could require repeat exam; corruption could lose diagnostic info).
- **Critical Functions**: Write verification, redundant storage, power-fail recovery.

## 3. Architecture
- **Ring Buffer**: Circular buffer in RAM for continuous pre-recording (crash-proof).
- **Async Writer**: Dedicated thread pool for flushing buffers to disk/network.
- **Storage Abstraction**: Unified API for local SSD, SD card, NFS, and Object Storage (S3).
- **Streaming Server**: Built-in RTSP/WebRTC server for live monitoring.

## 4. Data Integrity Features
- **Checksums**: SHA-256 hash calculated on write; verified on read.
- **Atomic Writes**: Temporary files renamed only after successful flush.
- **RAID-like Redundancy**: Optional mirroring to secondary partition/device.

## 5. x86 Mock Strategy
- **Filesystem Mock**: Uses tmpfs or loopback files to simulate slow SD cards.
- **Power Fail Sim**: Signal handler triggers abrupt shutdown to test recovery logic.
- **Load Gen**: Writes multi-GB datasets to verify GC and fragmentation handling.

## 6. API Specification
```cpp
class IStorageManager {
public:
    virtual Result<void> startRecording(const std::string& streamId, const Path& dest) = 0;
    virtual Result<void> stopRecording(const std::string& streamId) = 0;
    virtual Result<DataChunk> readChunk(const std::string& fileId, size_t offset, size_t len) = 0;
    virtual void setRetentionPolicies(const RetentionConfig& cfg) = 0;
};
```

## 7. Verification Requirements
- [ ] Verify no data loss during simulated power failure (last 2s buffer preserved).
- [ ] Verify write speed sustains > 100MB/s for 4K video recording.
- [ ] Verify checksum mismatch triggers alarm and blocks data usage.
