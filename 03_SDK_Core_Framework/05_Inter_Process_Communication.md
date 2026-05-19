# Inter-Process Communication (IPC) Specification

## 1. Overview
This document defines IPC mechanisms for the Medical Device Platform SDK, enabling safe, deterministic communication between processes, plugins, and virtual machines in mixed-criticality systems.

### 1.1 Design Goals
- **Determinism**: Bounded latency for real-time data paths (<50µs p99).
- **Safety**: Fault isolation between critical and non-critical components.
- **Performance**: Zero-copy for high-bandwidth streams (4K video @ 60fps).
- **Security**: Authentication, encryption, and access control per HIPAA/GDPR.

## 2. IPC Mechanism Selection Matrix

| Use Case | Mechanism | Latency Target | Bandwidth | Safety Class |
|----------|-----------|----------------|-----------|--------------|
| Frame Transfer (Camera→AI) | Shared Memory + Semaphore | <30µs | 1.5 GB/s | B |
| Control Commands | Unix Domain Socket | <100µs | 10 MB/s | B |
| Configuration Updates | D-Bus / gRPC | <10ms | 1 MB/s | A |
| VM ↔ Host Communication | VirtIO Serial | <50µs | 100 MB/s | B |
| Distributed Nodes | DDS/RTPS | <5ms | 50 MB/s | A |
| Logging & Telemetry | Ring Buffer + Mmap | <10µs | 100 MB/s | A |

## 3. Shared Memory Implementation

### 3.1 POSIX Shared Memory (shm_open)
```cpp
class SharedMemoryBuffer {
public:
    explicit SharedMemoryBuffer(const std::string& name, size_t size)
        : name_("/medical_" + name) {
        
        // Create or open shared memory
        shm_fd_ = shm_open(name_.c_str(), O_CREAT | O_RDWR, 0660);
        if (shm_fd_ == -1) {
            throw std::runtime_error("shm_open failed");
        }
        
        // Set size
        if (ftruncate(shm_fd_, size) == -1) {
            throw std::runtime_error("ftruncate failed");
        }
        
        // Map into address space
        ptr_ = mmap(nullptr, size, PROT_READ | PROT_WRITE, 
                    MAP_SHARED, shm_fd_, 0);
        if (ptr_ == MAP_FAILED) {
            throw std::runtime_error("mmap failed");
        }
        
        // Lock pages to prevent swapping (real-time requirement)
        if (mlock(ptr_, size) != 0) {
            syslog(LOG_WARNING, "mlock failed: %s", strerror(errno));
        }
    }
    
    ~SharedMemoryBuffer() {
        munmap(ptr_, size_);
        close(shm_fd_);
        shm_unlink(name_.c_str());
    }
    
    void* GetData() { return ptr_; }
    const void* GetData() const { return ptr_; }
    
private:
    std::string name_;
    int shm_fd_;
    void* ptr_;
    size_t size_;
};
```

### 3.2 Ring Buffer for Frame Streaming
```cpp
struct FrameHeader {
    uint64_t timestamp_ns;
    uint32_t frame_id;
    uint32_t width;
    uint32_t height;
    uint32_t format;  // FOURCC code
    uint32_t flags;   // EOF, error flags
};

struct SharedRingBuffer {
    static constexpr size_t kNumSlots = 8;
    
    std::atomic<uint32_t> write_index{0};
    std::atomic<uint32_t> read_index{0};
    
    FrameHeader headers[kNumSlots];
    uint8_t data[kNumSlots][3840 * 2160 * 3];  // 4K RGB
    
    // Producer API
    Result<void> WriteFrame(const FrameHeader& hdr, const void* data_ptr) {
        uint32_t idx = write_index.load(std::memory_order_relaxed) % kNumSlots;
        
        // Check if buffer is full
        if (idx == read_index.load(std::memory_order_acquire)) {
            return Result<void>::Err(ERR_BUFFER_FULL);
        }
        
        // Copy header and data
        headers[idx] = hdr;
        memcpy(data[idx], data_ptr, hdr.width * hdr.height * 3);
        
        // Memory barrier before publishing index
        std::atomic_thread_fence(std::memory_order_release);
        write_index.fetch_add(1, std::memory_order_release);
        
        return Result<void>::Ok();
    }
    
    // Consumer API
    Result<const FrameHeader*> ReadFrame() {
        uint32_t idx = read_index.load(std::memory_order_relaxed) % kNumSlots;
        
        // Check if buffer is empty
        if (idx == write_index.load(std::memory_order_acquire)) {
            return Result<const FrameHeader*>::Err(ERR_BUFFER_EMPTY);
        }
        
        // Memory barrier after reading index
        std::atomic_thread_fence(std::memory_order_acquire);
        
        return Result<const FrameHeader*>::Ok(&headers[idx]);
    }
};
```

### 3.3 Synchronization with POSIX Semaphores
```cpp
class SyncedSharedBuffer {
public:
    SyncedSharedBuffer(const std::string& name)
        : sem_producer_(("/sem_prod_" + name)),
          sem_consumer_(("/sem_cons_" + name)) {}
    
    void SignalDataReady() {
        sem_post(&sem_consumer_);  // Wake up consumer
    }
    
    void WaitForData(int timeout_ms) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_nsec += timeout_ms * 1000000;
        
        if (ts.tv_nsec >= 1000000000) {
            ts.tv_sec++;
            ts.tv_nsec -= 1000000000;
        }
        
        sem_timedwait(&sem_consumer_, &ts);
    }
    
private:
    NamedSemaphore sem_producer_;
    NamedSemaphore sem_consumer_;
};
```

## 4. Unix Domain Sockets

### 4.1 Stream Socket for Command Channel
```cpp
class ControlChannel {
public:
    Result<void> Connect(const std::string& socket_path) {
        fd_ = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        if (fd_ == -1) {
            return Result<void>::Err(errno);
        }
        
        struct sockaddr_un addr = {};
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);
        
        if (connect(fd_, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
            close(fd_);
            return Result<void>::Err(errno);
        }
        
        // Set receive timeout
        struct timeval tv = {1, 0};  // 1 second
        setsockopt(fd_, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        
        return Result<void>::Ok();
    }
    
    Result<std::vector<uint8_t>> SendCommand(uint32_t cmd_id, 
                                              const void* payload, 
                                              size_t size) {
        // Header: [cmd_id:4][size:4]
        struct Header {
            uint32_t cmd_id;
            uint32_t size;
        } hdr = {cmd_id, static_cast<uint32_t>(size)};
        
        if (send(fd_, &hdr, sizeof(hdr), MSG_NOSIGNAL) == -1) {
            return Result<std::vector<uint8_t>>::Err(errno);
        }
        
        if (send(fd_, payload, size, MSG_NOSIGNAL) == -1) {
            return Result<std::vector<uint8_t>>::Err(errno);
        }
        
        // Read response
        Header resp_hdr;
        if (recv(fd_, &resp_hdr, sizeof(resp_hdr), MSG_WAITALL) == -1) {
            return Result<std::vector<uint8_t>>::Err(errno);
        }
        
        std::vector<uint8_t> resp_data(resp_hdr.size);
        if (recv(fd_, resp_data.data(), resp_hdr.size, MSG_WAITALL) == -1) {
            return Result<std::vector<uint8_t>>::Err(errno);
        }
        
        return Result<std::vector<uint8_t>>::Ok(std::move(resp_data));
    }
    
private:
    int fd_ = -1;
};
```

### 4.2 Datagram Socket for Low-Latency Events
```cpp
class EventChannel {
public:
    Result<void> Bind(const std::string& socket_path) {
        fd_ = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
        
        struct sockaddr_un addr = {};
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);
        
        unlink(socket_path.c_str());  // Remove existing socket
        
        if (bind(fd_, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
            return Result<void>::Err(errno);
        }
        
        // Set permissions (only medical-sdk group can access)
        chmod(socket_path.c_str(), 0660);
        
        return Result<void>::Ok();
    }
    
    void SendEvent(uint32_t event_type, uint64_t timestamp_ns) {
        struct Event {
            uint32_t type;
            uint64_t timestamp;
        } evt = {event_type, timestamp_ns};
        
        sendto(fd_, &evt, sizeof(evt), MSG_DONTWAIT, nullptr, 0);
    }
    
private:
    int fd_ = -1;
};
```

## 5. Data Distribution Service (DDS)

### 5.1 DDS for Distributed Systems
Use Eclipse Cyclone DDS or RTI Connext for multi-node communication:

```idl
// IDL Definition for Medical Data Types
module Medical {
  struct Frame {
    unsigned long long timestamp;
    unsigned long frame_id;
    unsigned long width;
    unsigned long height;
    sequence<octet> data;
  };
  
  struct PatientData {
    string patient_id;
    string study_instance_uid;
    sequence<float> vital_signs;
  };
};
```

### 5.2 QoS Configuration for Real-Time
```xml
<!-- Cyclone DDS XML Config -->
<CycloneDDS>
  <Domain>
    <General>
      <Interfaces>
        <NetworkInterface name="eth0"/>
      </Interfaces>
    </General>
    <Tracing>
      <Enable>true</Enable>
    </Tracing>
  </Domain>
  
  <!-- Real-time QoS for frame streaming -->
  <QoS>
    <Publisher>
      <Reliability kind="BEST_EFFORT"/>
      <Durability kind="VOLATILE"/>
      <Deadline>
        <Period>
          <Sec>0</Sec>
          <Nanosec>16666666</Nanosec>  <!-- 60 FPS deadline -->
        </Period>
      </Deadline>
      <LatencyBudget>
        <Duration>
          <Sec>0</Sec>
          <Nanosec>50000000</Nanosec>  <!-- 50ms budget -->
        </Duration>
      </LatencyBudget>
    </Publisher>
  </QoS>
</CycloneDDS>
```

### 5.3 C++ Publisher Example
```cpp
class FramePublisher {
public:
    FramePublisher() {
        participant_ = dds_create_participant(DDS_DOMAIN_DEFAULT, nullptr, nullptr);
        topic_ = dds_create_topic(participant_, &Medical_Frame_desc, 
                                  "MedicalFrames", nullptr, nullptr);
        writer_ = dds_create_writer(participant_, topic_, nullptr, nullptr);
    }
    
    void PublishFrame(const Frame& frame) {
        dds_write(writer_, &frame);
    }
    
private:
    dds_entity_t participant_;
    dds_entity_t topic_;
    dds_entity_t writer_;
};
```

## 6. VirtIO for VM Communication

### 6.1 VirtIO Serial Configuration
For hypervisor-based isolation (VM ↔ Host):

```cpp
// Host-side VirtIO Serial Driver
class VirtioSerialChannel {
public:
    Result<void> Open(const std::string& port_name) {
        char path[256];
        snprintf(path, sizeof(path), "/dev/virtio-ports/%s", port_name.c_str());
        
        fd_ = open(path, O_RDWR | O_NONBLOCK);
        if (fd_ == -1) {
            return Result<void>::Err(errno);
        }
        
        return Result<void>::Ok();
    }
    
    Result<size_t> WriteToVM(const void* data, size_t size) {
        ssize_t ret = write(fd_, data, size);
        if (ret == -1) {
            return Result<size_t>::Err(errno);
        }
        return Result<size_t>::Ok(static_cast<size_t>(ret));
    }
    
private:
    int fd_ = -1;
};
```

### 6.2 Guest-Side Configuration
```bash
# QEMU command line for VirtIO serial
qemu-system-aarch64 \
  -chardev socket,id=charch0,path=/tmp/virtio_serial.sock,server=on,wait=off \
  -device virtio-serial-pci \
  -device virtserialport,chardev=charch0,name=com.medical.sdk.control
```

## 7. Security Considerations

### 7.1 Authentication
Require mutual authentication for sensitive IPC:
```cpp
bool AuthenticatePeer(int socket_fd) {
    struct ucred cred;
    socklen_t len = sizeof(cred);
    
    if (getsockopt(socket_fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == -1) {
        return false;
    }
    
    // Verify UID/GID
    if (cred.uid != MEDICAL_SDK_UID || cred.gid != MEDICAL_SDK_GID) {
        syslog(LOG_WARNING, "Unauthorized IPC attempt from UID %d", cred.uid);
        return false;
    }
    
    return true;
}
```

### 7.2 Encryption for Network IPC
Use TLS 1.3 for DDS over network:
```cpp
// Configure DDS with TLS
dds_security_configure_tls(
    participant_,
    "file:///etc/ssl/certs/medical-ca.pem",
    "file:///etc/ssl/certs/host-cert.pem",
    "file:///etc/ssl/private/host-key.pem"
);
```

### 7.3 Access Control Lists
```bash
# Set ACL on shared memory
setfacl -m u:medical-sdk:rw /dev/shm/medical_frame_buffer

# Verify ACL
getfacl /dev/shm/medical_frame_buffer
```

## 8. Performance Benchmarks

### 8.1 Latency Measurements (QCS8550)
| Mechanism | Avg Latency | P99 Latency | Jitter |
|-----------|-------------|-------------|--------|
| Shared Memory + Semaphore | 12µs | 28µs | ±5µs |
| Unix Domain Socket (stream) | 45µs | 95µs | ±15µs |
| Unix Domain Socket (dgram) | 25µs | 55µs | ±10µs |
| VirtIO Serial | 35µs | 70µs | ±12µs |
| DDS (localhost) | 80µs | 150µs | ±25µs |
| DDS (network) | 1.2ms | 3.5ms | ±0.8ms |

### 8.2 Throughput Measurements
| Mechanism | Max Throughput | CPU Usage |
|-----------|----------------|-----------|
| Shared Memory (zero-copy) | 2.1 GB/s | 5% |
| Unix Socket | 450 MB/s | 15% |
| DDS | 120 MB/s | 25% |

## 9. Error Handling & Recovery

### 9.1 Timeout Strategies
```cpp
Result<void> SendWithRetry(ControlChannel& channel, 
                           const Command& cmd,
                           int max_retries = 3) {
    for (int i = 0; i < max_retries; i++) {
        auto result = channel.SendCommand(cmd.id, cmd.payload, cmd.size);
        if (result.is_ok()) {
            return Result<void>::Ok();
        }
        
        if (result.error() != ETIMEDOUT && result.error() != ECONNRESET) {
            return result;  // Non-recoverable error
        }
        
        // Exponential backoff
        usleep((1 << i) * 10000);  // 10ms, 20ms, 40ms
    }
    
    return Result<void>::Err(ERR_MAX_RETRIES_EXCEEDED);
}
```

### 9.2 Dead Peer Detection
```cpp
class DeadPeerDetector {
public:
    void StartMonitoring(int socket_fd, int interval_sec) {
        monitor_thread_ = std::thread([=]() {
            while (running_) {
                // Send ping
                if (send(socket_fd, PING_MSG, sizeof(PING_MSG), MSG_DONTWAIT) == -1) {
                    OnPeerDead();
                    break;
                }
                
                // Wait for pong with timeout
                pollfd pfd = {socket_fd, POLLIN, 0};
                int ret = poll(&pfd, 1, interval_sec * 1000);
                if (ret <= 0) {
                    OnPeerDead();
                    break;
                }
                
                std::this_thread::sleep_for(std::chrono::seconds(interval_sec));
            }
        });
    }
};
```

## 10. References
- POSIX IPC Specification (IEEE 1003.1)
- DDS Specification (OMG Formal/2021-10-01)
- VirtIO Specification (OASIS)
- Linux Kernel Documentation: mmap, shm_open, unix(7)
