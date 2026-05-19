# Essential Library Stack Specification

**Version:** 1.0  
**Status:** Approved for Implementation  
**Classification:** Medical Device SDK - SOUP (Software of Unknown Provenance)  
**Compliance:** IEC 62304 Section 7.1, ISO 14971, FDA Cybersecurity Guidance  

---

## Executive Summary

This document defines the third-party libraries integrated into the Medical Device Platform SDK. Each library is categorized, version-pinned, validated per IEC 62304 SOUP requirements, and optimized for both x86 development and ARM deployment.

**Total Libraries:** 25+ validated components  
**Validation Status:** All critical libraries require Class B/C validation  
**Update Policy:** Quarterly review with CVE monitoring  

---

## Library Categories

### 1. Computer Vision & Image Processing

| Library | Version | License | Validation Status | Usage | Optimization Notes |
|---------|---------|---------|-------------------|-------|-------------------|
| **OpenCV** | 4.9.0 | BSD 3-Clause | ✅ Validated | Image filtering, segmentation, feature detection | NEON/SVE on ARM, AVX2/AVX-512 on x86 |
| **ITK** | 5.4.0 | Apache 2.0 | ✅ Validated | Medical image registration, segmentation | GPU-accelerated filters via CUDA/OpenCL |
| **VTK** | 9.3.0 | BSD 3-Clause | 🔄 In Progress | 3D visualization, volume rendering | OpenGL ES 3.2 on Adreno GPU |
| **Open3D** | 0.17.0 | MIT | ⏳ Planned | Point cloud processing, mesh registration | CPU-only for initial release |

**Medical-Specific Adaptations:**
- DICOM pixel data parsing (16-bit grayscale, color LUT)
- GSDF (Grayscale Standard Display Function) calibration
- Zero-copy DMA-BUF buffers for camera pipeline
- Real-time denoising filters (bilateral, NLM)

---

### 2. Visualization & UI Framework

| Library | Version | License | Validation Status | Usage | Notes |
|---------|---------|---------|-------------------|-------|-------|
| **Qt 6** | 6.6.0 | LGPL v3 / Commercial | ✅ Validated | GUI framework, OpenGL integration | Commercial license required for medical devices |
| **Dear ImGui** | 1.90.0 | MIT | ⚠️ Internal Use Only | Debug overlays, developer tools | Not for clinical UI |
| **ImGuiPlot** | 1.2.0 | MIT | ⚠️ Internal Use Only | Real-time signal visualization | Developer tooling only |

**UI Performance Targets:**
- 60 fps rendering at 1080p
- <50ms input latency (touch/button)
- Hardware acceleration via Mali/Adreno GPU
- Multi-window support for multi-display setups

---

### 3. Networking & Clinical Interoperability

| Library | Version | License | Validation Status | Usage | Compliance |
|---------|---------|---------|-------------------|-------|------------|
| **DCMTK** | 3.6.8 | BSD-like | ✅ Validated | DICOM encoding/decoding, SCP/SCU | DICOM PS3 conformant |
| **Orthanc** | 1.12.1 | AGPL v3 | 🔄 In Progress | DICOM server, REST API, storage | Optional component |
| **HAPI FHIR** | 2.4.0 | Apache 2.0 | ✅ Validated | FHIR R4 resource parsing | HL7 FHIR R4 certified |
| **Fast DDS** | 2.10.0 | Apache 2.0 | ✅ Validated | Real-time pub/sub, TSN sync | DDS-RTPS 2.5 |
| **gRPC** | 1.59.0 | Apache 2.0 | ✅ Validated | Service mesh, streaming RPC | HTTP/2 + TLS 1.3 |

**IHE Profile Support:**
- Endoscopy (END)
- Patient Care Coordination (PCC)
- Cross-Enterprise Document Sharing for Imaging (XDS-I)
- Audit Trail and Node Authentication (ATNA)

---

### 4. AI & Inference Runtime

| Library | Version | License | Validation Status | Backend Support | Target Hardware |
|---------|---------|---------|-------------------|-----------------|-----------------|
| **ONNX Runtime** | 1.16.0 | MIT | ✅ Validated | CPU, GPU (CUDA), DSP (QNN) | Universal |
| **Qualcomm QNN** | 2.2.0 | Proprietary | 🔄 In Progress | Hexagon DSP, NPU | QCS8550 only |
| **TensorRT** | 8.6.0 | Proprietary | ⏳ Planned | GPU (CUDA) | NVIDIA Orin add-on |
| **OpenVINO** | 2023.3.0 | Apache 2.0 | ⏳ Planned | CPU, iGPU, VPU | x86 development |

**AI Abstraction Layer:**
```cpp
class medai::Engine {
public:
    virtual Status load_model(const std::string& path) = 0;
    virtual Status infer(const Tensor& input, Tensor& output) = 0;
    virtual Backend get_backend() const = 0;
    virtual double get_latency_p99() const = 0;
};
```

**Performance Targets:**
- Classification: <10ms p99 latency
- Detection: <30ms p99 latency  
- Segmentation: <50ms p99 latency

---

### 5. Security & Cryptography

| Library | Version | License | Validation Status | Usage | Certification |
|---------|---------|---------|-------------------|-------|---------------|
| **OpenSSL** | 3.0.12 | Apache 2.0 | ✅ Validated (FIPS mode) | TLS 1.3, certificate handling | FIPS 140-2 Level 1 |
| **Mbed TLS** | 3.5.0 | Apache 2.0 | ⏳ Planned | Lightweight crypto for embedded | PSA Certified |
| **libsodium** | 1.0.19 | ISC | ✅ Validated | Modern cryptography (ChaCha20, Ed25519) | N/A |
| **TEE Client API** | v1.1 | Proprietary | ✅ Validated | Key management, attestation | GlobalPlatform TEE |

**Security Features:**
- Hardware root of trust (QCS8550 Secure Boot)
- Encrypted storage (LUKS/dm-crypt)
- Certificate rotation with OCSP stapling
- Tamper-evident audit logging

---

### 6. Logging & Diagnostics

| Library | Version | License | Validation Status | Usage |
|---------|---------|---------|-------------------|-------|
| **spdlog** | 1.12.0 | MIT | ✅ Validated | High-performance structured logging |
| **fmt** | 10.1.0 | MIT | ✅ Validated | Type-safe formatting (spdlog dependency) |
| **backward-cpp** | 1.6.0 | MIT | ⚠️ Debug Only | Stack traces on crash |

**Logging Requirements:**
- Structured JSON format for audit trail
- Cryptographic integrity (HMAC-SHA256)
- WORM (Write Once Read Many) storage
- Configurable verbosity: ERROR, WARN, INFO, DEBUG, TRACE

---

## Integration Strategy

### Build System Integration

| Component | Linking Method | Rationale |
|-----------|---------------|-----------|
| OpenCV Core | Static | Real-time performance, deterministic behavior |
| ONNX Runtime | Static | CPU backend critical path |
| Qt Framework | Dynamic | Plugin architecture, theme customization |
| DCMTK Network | Dynamic | Optional component, reduces binary size |
| OpenSSL | Static (FIPS object) | FIPS boundary compliance |

### Version Pinning Strategy

All libraries must be pinned in `manifest.yaml`:
```yaml
libraries:
  opencv:
    version: "4.9.0"
    git_tag: "4.9.0"
    sha256: "a1b2c3d4..."
  onnxruntime:
    version: "1.16.0"
    git_tag: "v1.16.0"
    sha256: "e5f6g7h8..."
```

---

## SOUP Validation Requirements (IEC 62304 Section 7.1)

### Validation Checklist

For each SOUP component:

1. **Risk Assessment** ☐
   - Document hazards associated with library usage
   - Define risk controls (input validation, timeout, error handling)

2. **Verification Plan** ☐
   - Unit tests for wrapper functions
   - Integration tests in target context
   - Performance benchmarks

3. **Anomaly Tracking** ☐
   - Log all bugs/issues found in upstream
   - Track resolution status

4. **Change Control** ☐
   - Re-validate upon version upgrade
   - Impact assessment for API changes

### Validation Evidence Matrix

| Library | Risk Assessment | Test Report | Anomaly Log | Version Control |
|---------|-----------------|-------------|-------------|-----------------|
| OpenCV | VA-OPENCV-001 | TR-OPENCV-001 | AL-OPENCV-001 | ✅ |
| ITK | VA-ITK-001 | TR-ITK-001 | AL-ITK-001 | ✅ |
| DCMTK | VA-DCMTK-001 | TR-DCMTK-001 | AL-DCMTK-001 | ✅ |
| ONNX Runtime | VA-ONNX-001 | TR-ONNX-001 | AL-ONNX-001 | ✅ |
| OpenSSL | VA-OPENSSL-001 | TR-OPENSSL-001 | AL-OPENSSL-001 | ✅ |

---

## Platform-Specific Optimizations

### x86 Development Host

- Enable AVX2/AVX-512 instructions for OpenCV/ITK
- Use CUDA backend for ONNX Runtime (if NVIDIA GPU present)
- Full debug symbols enabled
- Sanitizers: ASan, UBSan, TSan for testing

### QCS8550 Target (ARM64)

- Enable NEON/SVE optimizations
- Offload AI inference to Hexagon DSP via QNN EP
- Strip debug symbols for release builds
- Separate symbol server for crash analysis
- ION shared memory for zero-copy pipelines

---

## Related Documents

- [AI Runtime Specification](./02_AI_Runtime_Specification.md)
- [DICOM Networking Stack](./03_DICOM_Networking_Stack.md)
- [OpenCV/ITK Integration](./04_OpenCV_ITK_Integration.md)
- [Security Crypto Libraries](./05_Security_Crypto_Libraries.md)
- [Visualization Framework](./06_Visualization_Framework.md)

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-05 | SDK Team | Initial release |
