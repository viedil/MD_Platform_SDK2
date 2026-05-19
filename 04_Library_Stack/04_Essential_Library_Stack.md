# Essential Library Stack

## Computer Vision & Image Processing

* **OpenCV 4.9**: `opencv_contrib` (medical modules)
* **ITK 5.4**: `SimpleITK` for Python, GPU-accelerated filters
* **Adaptation**: DICOM pixel data parsing, GSDF LUT, zero-copy DMA-BUF

## Visualization & Rendering

* **Qt6**: `QtQuick`, `Qt3D`, `QtCharts`
* **VTK 9.3**: Hardware rendering, DICOM volume, stereo/AR
* **Open3D**: Point cloud, mesh, registration

## Networking & Interoperability

* **Fast DDS**: Real-time pub/sub, TSN sync
* **gRPC**: Service mesh, streaming
* **DCMTK + HAPI FHIR**: DICOM/FHIR parsers, IHE profiles
* **TLS 1.3**: Mutual auth, certificate rotation

## AI & Inference Runtime

* **ONNX Runtime**: CPU/NPU abstraction
* **SNPE/HTP**: Qualcomm native
* **TensorRT**: NVIDIA Orin PCIe add-on
* **Abstraction**: `medai::Engine` interface

## Security & Cryptography

* **OpenSSL 3.x**: TLS, AES, RSA
* **TEE API**: Key management, attestation
* **spdlog + auditd**: Structured logging, WORM
* **libspdm**: Secure device messaging
