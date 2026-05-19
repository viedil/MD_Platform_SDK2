# 04 Library Stack Specification

## 1. Overview
This document defines the third-party libraries (SOUP - Software of Unknown Provenance) integrated into the Medical Device Platform SDK. Each library is categorized, version-pinned, and validated per IEC 62304 and ISO 14971 requirements.

## 2. Library Categories

### 2.1 Computer Vision & Image Processing
| Library | Version | License | Validation Status | Usage |
|---------|---------|---------|-------------------|-------|
| OpenCV | 4.8.0 | BSD 3-Clause | ✅ Validated (v1.0) | Image filtering, segmentation, feature detection |
| ITK | 5.3.0 | Apache 2.0 | ✅ Validated (v1.0) | Medical image registration, segmentation |
| VTK | 9.2.0 | BSD 3-Clause | 🔄 In Progress | 3D visualization, volume rendering |

### 2.2 AI/ML Inference
| Library | Version | License | Validation Status | Backend Support |
|---------|---------|---------|-------------------|-----------------|
| ONNX Runtime | 1.16.0 | MIT | ✅ Validated (v1.0) | CPU (x86/ARM), GPU (CUDA), DSP (QNN) |
| TensorRT | 8.6.0 | Proprietary | ⏳ Planned | GPU (NVIDIA only) |
| Qualcomm QNN | 2.2.0 | Proprietary | 🔄 In Progress | Hexagon DSP, NPU (QCS8550) |

### 2.3 Medical Imaging & Networking
| Library | Version | License | Validation Status | Usage |
|---------|---------|---------|-------------------|-------|
| DCMTK | 3.6.7 | BSD-like | ✅ Validated (v1.0) | DICOM encoding/decoding, network SCP/SCU |
| Orthanc | 1.12.1 | AGPL v3 | 🔄 In Progress | DICOM server, REST API, storage |
| GDCM | 3.0.21 | BSD 2-Clause | ⏳ Planned | DICOM file parsing (alternative to DCMTK) |

### 2.4 Visualization & UI
| Library | Version | License | Validation Status | Usage |
|---------|---------|---------|-------------------|-------|
| Qt | 6.5.2 | LGPL v3 / Commercial | ✅ Validated (v1.0) | GUI framework, OpenGL integration |
| ImGui | 1.89.0 | MIT | ⚠️ Use with Caution | Debug overlays, internal tools only |

### 2.5 Security & Cryptography
| Library | Version | License | Validation Status | Usage |
|---------|---------|---------|-------------------|-------|
| OpenSSL | 3.0.10 | Apache 2.0 | ✅ Validated (FIPS mode) | TLS, certificate handling |
| mbedTLS | 3.5.0 | Apache 2.0 | ⏳ Planned | Lightweight crypto for embedded |

## 3. Integration Strategy

### 3.1 Build System Integration
- **Static Linking**: Required for real-time critical components (OpenCV core, ONNX Runtime CPU).
- **Dynamic Linking**: Allowed for UI and non-critical services (Qt plugins, DCMTK network).
- **Version Pinning**: All libraries must be pinned to specific Git tags or commits in `manifest.yaml`.

### 3.2 SOUP Validation Requirements
Per IEC 62304 Section 7.1:
1.  **Risk Assessment**: Document hazards associated with each library.
2.  **Verification Plan**: Define test cases to validate library behavior in target context.
3.  **Anomaly Tracking**: Log all bugs/issues found in upstream libraries.
4.  **Change Control**: Re-validate upon any version upgrade.

## 4. Platform-Specific Optimizations

### 4.1 x86 Development Host
- Enable AVX2/AVX-512 instructions for OpenCV/ITK.
- Use CUDA backend for ONNX Runtime (if NVIDIA GPU present).
- Full debug symbols enabled.

### 4.2 QCS8550 Target (ARM64)
- Enable NEON/SVE optimizations.
- Offload AI inference to Hexagon DSP via QNN EP.
- Strip debug symbols for release builds; keep separate symbol server.

## 5. References
- [IEC 62304:2006 Section 7.1](https://webstore.iec.ch/publication/6765)
- [FDA Guidance on Cybersecurity](https://www.fda.gov/media/142643/download)
- Sub-documents: `OpenCV_ITK_Integration.md`, `AI_Runtime_Specification.md`, `DICOM_Networking_Stack.md`
