# Plugin Architecture Specification

## 1. Overview
This document defines the plugin architecture for the Medical Device Platform SDK, enabling third-party module integration while maintaining safety, security, and regulatory compliance.

### 1.1 Design Goals
- **Modularity**: Hot-swappable modules without system restart.
- **Isolation**: Fault containment to prevent plugin crashes from affecting core system.
- **Compliance**: Support for qualification of plugins per IEC 62304.
- **Discovery**: Automatic plugin registration and version negotiation.

## 2. Plugin Interface Definition

### 2.1 Core Interface: `IMedicalModule`
All plugins must implement this C-style ABI interface for maximum compatibility:

```cpp
extern "C" {

typedef enum {
    MODULE_STATE_UNINITIALIZED = 0,
    MODULE_STATE_INITIALIZED = 1,
    MODULE_STATE_RUNNING = 2,
    MODULE_STATE_STOPPED = 3,
    MODULE_STATE_ERROR = 4
} ModuleState;

typedef struct {
    const char* name;
    const char* version;
    const char* vendor;
    uint32_t api_version;  // SDK API compatibility
    uint32_t min_sdk_version;
    uint32_t max_sdk_version;
} ModuleInfo;

// Lifecycle Functions
int module_init(const char* config_path);
int module_start(void);
int module_stop(void);
int module_shutdown(void);

// State Query
ModuleState module_get_state(void);
const ModuleInfo* module_get_info(void);

// Health Check (called every 100ms by supervisor)
int module_health_check(void);

}  // extern "C"
```

### 2.2 Lifecycle State Machine
```
[UNINITIALIZED] --init()--> [INITIALIZED]
     ^                          |
     | shutdown()               | start()
     |                          v
[ERROR] <--fault-- [RUNNING] --stop()--> [STOPPED]
                             |              |
                             | fault        | start()
                             v              v
                           [ERROR] <-------+
```

### 2.3 Return Code Convention
```cpp
#define MEDICAL_SUCCESS         0
#define MEDICAL_ERR_GENERAL    -1
#define MEDICAL_ERR_TIMEOUT    -2
#define MEDICAL_ERR_INVALID    -3
#define MEDICAL_ERR_RESOURCE   -4
#define MEDICAL_ERR_PERMISSION -5
```

## 3. Plugin Discovery & Loading

### 3.1 Directory Structure
```
/opt/medical-sdk/plugins/
├── camera/
│   ├── libcamera_qcs8550.so
│   ├── libcamera_mock.so
│   └── camera.manifest
├── ai/
│   ├── libai_onnx.so
│   ├── libai_tensorrt.so
│   └── ai.manifest
└── dicom/
    └── ...
```

### 3.2 Manifest Format (JSON)
```json
{
  "name": "camera_qcs8550",
  "version": "1.2.0",
  "vendor": "Qualcomm",
  "api_version": 3,
  "sdk_compatibility": {
    "min": "2.0.0",
    "max": "3.0.0"
  },
  "dependencies": [
    {"name": "hal_core", "version": ">=1.0.0"}
  ],
  "capabilities": [
    "video_capture",
    "hardware_trigger",
    "low_latency"
  ],
  "safety_class": "B",
  "qualification_id": "QUAL-CAM-2024-001",
  "sha256": "abc123..."
}
```

### 3.3 Loading Process
```cpp
class PluginManager {
public:
    Result<void> LoadPlugin(const std::string& path) {
        // 1. Verify signature
        auto sig_result = VerifySignature(path);
        if (!sig_result.is_ok()) return sig_result;
        
        // 2. Load shared library
        void* handle = dlopen(path.c_str(), RTLD_LAZY | RTLD_LOCAL);
        if (!handle) {
            return Result<void>::Err(MEDICAL_ERR_RESOURCE);
        }
        
        // 3. Resolve symbols
        auto init_fn = (decltype(&module_init))dlsym(handle, "module_init");
        if (!init_fn) {
            dlclose(handle);
            return Result<void>::Err(MEDICAL_ERR_INVALID);
        }
        
        // 4. Validate manifest
        auto manifest = LoadManifest(path + ".manifest");
        if (!CheckCompatibility(manifest)) {
            dlclose(handle);
            return Result<void>::Err(MEDICAL_ERR_VERSION);
        }
        
        // 5. Register in registry
        plugins_.push_back({handle, init_fn, manifest});
        return Result<void>::Ok();
    }
};
```

## 4. Sandboxing & Isolation

### 4.1 Process Isolation (Recommended)
Run untrusted plugins in separate processes:
```cpp
// Supervisor spawns plugin as child process
pid_t pid = fork();
if (pid == 0) {
    // Child: Drop privileges, load plugin
    capng_clear(CAPNG_SELECT_BOTH);
    capng_apply(CAPNG_SELECT_BOTH);
    
    // Load plugin in child
    module_init(config);
    module_start();
    
    // Event loop with health checks
    while (running) {
        if (module_health_check() != 0) exit(1);
        sleep(1);
    }
} else {
    // Parent: Monitor child via pipe/socket
    monitor_process(pid);
}
```

### 4.2 Resource Limits
Enforce via cgroups v2:
```bash
# Limit plugin memory to 512MB
echo "512M" > /sys/fs/cgroup/plugins/plugin1/memory.max

# Limit CPU to 2 cores
echo "0-1" > /sys/fs/cgroup/plugins/plugin1/cpuset.cpus

# Limit file descriptors
echo "100" > /sys/fs/cgroup/plugins/plugin1/pids.max
```

### 4.3 Watchdog Integration
```cpp
class PluginWatchdog {
public:
    void StartMonitoring(const std::string& plugin_name, pid_t pid) {
        watchdog_thread_ = std::thread([=]() {
            while (running_) {
                // Check if process is alive
                if (kill(pid, 0) != 0) {
                    OnPluginCrash(plugin_name);
                    break;
                }
                
                // Check health via socket
                if (!SendHealthCheck(pid)) {
                    OnPluginHang(plugin_name);
                    kill(pid, SIGKILL);
                    break;
                }
                
                std::this_thread::sleep_for(100ms);
            }
        });
    }
};
```

## 5. Inter-Plugin Communication

### 5.1 Message Bus Architecture
Plugins communicate via a central message bus (DDS or ZeroMQ):

```cpp
// Publish-subscribe pattern
class MessageBus {
public:
    void Publish(const std::string& topic, const void* data, size_t size);
    void Subscribe(const std::string& topic, Callback cb);
};

// Example: Camera publishes frames, AI subscribes
camera_plugin->bus_->Publish("camera/frame", frame_ptr, frame_size);
ai_plugin->bus_->Subscribe("camera/frame", [](const void* data) {
    ProcessFrame(data);
});
```

### 5.2 Shared Memory for High-Bandwidth Data
```cpp
// Create shared memory region for zero-copy frame transfer
int shm_fd = shm_open("/medical_frame_buffer", O_CREAT | O_RDWR, 0660);
ftruncate(shm_fd, FRAME_BUFFER_SIZE);

// Map in both producer and consumer
void* buffer = mmap(NULL, FRAME_BUFFER_SIZE, PROT_READ | PROT_WRITE, 
                    MAP_SHARED, shm_fd, 0);
```

## 6. Versioning & Compatibility

### 6.1 API Version Policy
- **Major Version**: Breaking changes (incompatible)
- **Minor Version**: New features (backward compatible)
- **Patch Version**: Bug fixes only

### 6.2 Compatibility Matrix
| SDK Version | Plugin API v1 | Plugin API v2 | Plugin API v3 |
|-------------|---------------|---------------|---------------|
| SDK 1.x     | ✅            | ❌            | ❌            |
| SDK 2.x     | ✅            | ✅            | ❌            |
| SDK 3.x     | ⚠️ (deprecated)| ✅           | ✅            |

### 6.3 Migration Path
Provide shim layers for deprecated APIs:
```cpp
// Shim for old plugin API v1
if (plugin_api_version == 1) {
    WrapWithV2CompatibilityLayer(plugin_handle);
}
```

## 7. Security Requirements

### 7.1 Code Signing
All plugins must be signed:
```bash
# Sign plugin with private key
openssl dgst -sha384 -sign keys/plugin-key.pem \
  -out libcamera.so.sig libcamera.so

# Verify before loading
openssl dgst -sha384 -verify keys/plugin-key.pub.pem \
  -signature libcamera.so.sig libcamera.so
```

### 7.2 Capability Restrictions
Plugins run with minimal Linux capabilities:
```cpp
capng_clear(CAPNG_SELECT_BOTH);
capng_updatev(CAPNG_ADD, CAPNG_EFFECTIVE, CAP_NET_BIND_SERVICE, -1);
capng_apply(CAPNG_SELECT_BOTH);
```

### 7.3 Audit Logging
Log all plugin operations:
```cpp
void LogPluginEvent(const std::string& plugin, const std::string& event) {
    syslog(LOG_INFO, "[PLUGIN:%s] %s at %lu", 
           plugin.c_str(), event.c_str(), time(nullptr));
}
```

## 8. Qualification & Validation

### 8.1 Plugin Qualification Levels
| Level | Description | Testing Required |
|-------|-------------|------------------|
| Q0 | Internal dev | Unit tests only |
| Q1 | Alpha testing | Unit + integration |
| Q2 | Beta release | Full regression |
| Q3 | Production | Qualified per IEC 62304 |

### 8.2 Validation Checklist
- [ ] All lifecycle functions tested
- [ ] Error paths exercised (100% branch coverage)
- [ ] Memory leak detection (Valgrind clean)
- [ ] Thread safety verified (TSan clean)
- [ ] Real-time performance validated
- [ ] Security audit completed
- [ ] Documentation complete

### 8.3 Test Harness
```cpp
// Automated plugin test runner
class PluginTestHarness {
public:
    void RunAllTests(const std::string& plugin_path) {
        LoadPlugin(plugin_path);
        TestInit();
        TestStartStop();
        TestHealthCheck();
        TestErrorInjection();
        TestResourceLimits();
        UnloadPlugin();
    }
};
```

## 9. Deployment & Updates

### 9.1 Atomic Updates
Use A/B partition strategy for plugin updates:
```bash
# Install to inactive slot
install_plugin.sh libcamera.so --slot=B

# Verify signature and health
verify_plugin.sh --slot=B

# Switch active slot on next reboot
activate_slot.sh B
```

### 9.2 Rollback Mechanism
Automatic rollback on health check failure:
```cpp
if (plugin_health_check(new_version) == FAILED) {
    RollbackToPreviousVersion();
    NotifyOperator("Plugin update failed, rolled back");
}
```

## 10. References
- IEC 62304 Software Lifecycle
- ISO 14971 Risk Management
- Linux Capabilities Manual
- DDS Specification (OMG)
