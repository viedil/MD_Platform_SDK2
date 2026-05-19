# Build System Specification

## 1. Overview
This document defines the build system architecture for the Medical Device Platform SDK, ensuring reproducible builds across x86 development hosts and ARM (QCS8550) targets.

### 1.1 Design Goals
- **Reproducibility**: Bit-for-bit identical builds across environments.
- **Cross-Architecture**: Seamless switching between x86 (mock) and ARM (target).
- **Compliance**: Support for SBOM generation and artifact signing per FDA/MDR.
- **Modularity**: Layered build system supporting custom board support packages (BSPs).

## 2. Build Architecture

### 2.1 Core Tools
| Component | Version | Purpose |
|-----------|---------|---------|
| CMake | ≥ 3.24 | Primary build orchestration |
| Yocto Project | Kirkstone (4.0) | Embedded Linux distribution |
| OpenEmbedded | Custom Layer | SDK-specific recipes |
| GCC | 12.x | Host compilation |
| Clang | 15.x | Static analysis + LTO |
| Linaro GCC | 12.2 | ARM cross-compilation |

### 2.2 Directory Structure
```
build/
├── host/           # x86 native builds (mock HAL)
├── target/         # ARM cross-compiled builds (QCS8550 HAL)
├── sysroots/       # Sysroot images for cross-compilation
└── artifacts/      # Final binaries, SBOMs, signatures
```

## 3. CMake Configuration

### 3.1 Presets
Use `CMakePresets.json` for standardized build configurations:

```json
{
  "version": 3,
  "configurePresets": [
    {
      "name": "x86-debug",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/host/debug",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "MEDICAL_PLATFORM_HAL": "mock",
        "MEDICAL_PLATFORM_ARCH": "x86_64"
      }
    },
    {
      "name": "arm-release",
      "generator": "Ninja",
      "toolchainFile": "${sourceDir}/cmake/toolchain-qcs8550.cmake",
      "binaryDir": "${sourceDir}/build/target/release",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Release",
        "MEDICAL_PLATFORM_HAL": "qcs8550",
        "MEDICAL_PLATFORM_ARCH": "aarch64"
      }
    }
  ]
}
```

### 3.2 HAL Swapping Logic
```cmake
if(MEDICAL_PLATFORM_HAL STREQUAL "mock")
  add_subdirectory(hal/mock)
  target_compile_definitions(sdk_core PUBLIC USE_MOCK_HAL)
elseif(MEDICAL_PLATFORM_HAL STREQUAL "qcs8550")
  add_subdirectory(hal/qcs8550)
  target_compile_definitions(sdk_core PUBLIC USE_QCS8550_HAL)
else()
  message(FATAL_ERROR "Invalid HAL: ${MEDICAL_PLATFORM_HAL}")
endif()
```

## 4. Yocto/OpenEmbedded Integration

### 4.1 Custom Layer: `meta-medical-sdk`
```
meta-medical-sdk/
├── conf/
│   ├── layer.conf
│   └── machine/
│       ├── qcs8550-medical.conf
│       └── x86-medical-mock.conf
├── recipes-core/
│   └── images/
│       └── medical-image.bb
├── recipes-medical/
│   └── sdk-core/
│       ├── sdk-core_git.bb
│       └── files/
│           └── signing.sh
└── scripts/
    └── setup-sdk-build.sh
```

### 4.2 Image Recipe Example
```bitbake
SUMMARY = "Medical Device Platform Image"
LICENSE = "MIT & Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=..."

IMAGE_INSTALL = " \
  packagegroup-medical-core \
  sdk-runtime \
  kernel-module-preempt-rt \
  hypervisor-config \
"

inherit core-image extrausers

# Enforce read-only rootfs for security
EXTRA_IMAGEFEATURES = "read-only-rootfs"

# Post-processing: Sign all binaries
IMAGE_POSTPROCESS_COMMAND += "sign_artifacts; "
```

## 5. Cross-Compilation Workflow

### 5.1 Toolchain Setup
```bash
# Download Linaro toolchain
wget https://snapshots.linaro.org/gnu-toolchain/12.2-2023.01/aarch64-linux-gnu/gcc-linaro-12.2.0-2023.01-x86_64_aarch64-linux-gnu.tar.xz

# Export via Yocto SDK
bitbake medical-image -c populate_sdk
```

### 5.2 Build Commands
```bash
# x86 Development (Mock HAL)
cmake --preset=x86-debug
cmake --build build/host/debug -j$(nproc)

# ARM Target (QCS8550 HAL)
cmake --preset=arm-release
cmake --build build/target/release -j$(nproc)

# Yocto Full Image Build
source setup-sdk-build.sh qcs8550-medical
bitbake medical-image
```

## 6. Artifact Management

### 6.1 Output Artifacts
| Artifact | Location | Description |
|----------|----------|-------------|
| SDK Libraries | `artifacts/lib/` | `.so` files with debug symbols stripped |
| Headers | `artifacts/include/` | Public API headers |
| SBOM | `artifacts/sbom/` | SPDX 2.3 format |
| Signatures | `artifacts/signatures/` | RSA-4096 signatures |
| Container Image | `artifacts/docker/` | Docker image for CI testing |

### 6.2 SBOM Generation
```bash
# Generate SBOM using Syft
syft dir:build/target/release -o spdx-json=artifacts/sbom/sdk-sbom.json

# Validate against vulnerability database
grype sbom:artifacts/sbom/sdk-sbom.json
```

### 6.3 Signing Process
```bash
# Sign all binaries with private key
for bin in artifacts/lib/*.so; do
  openssl dgst -sha384 -sign keys/private-key.pem -out ${bin}.sig $bin
done
```

## 7. Continuous Integration

### 7.1 CI Pipeline Stages
1. **Lint**: Code style, license headers
2. **Build x86**: Debug + Release
3. **Test x86**: Unit tests, integration tests
4. **Cross-Compile**: ARM build verification
5. **SBOM**: Generate and scan for vulnerabilities
6. **Sign**: Cryptographic signing
7. **Package**: Create deployable artifacts

### 7.2 GitLab CI Example
```yaml
build_arm:
  stage: build
  image: yocto/kirkstone
  script:
    - cmake --preset=arm-release
    - cmake --build build/target/release
  artifacts:
    paths:
      - build/target/release/
    expire_in: 1 week
```

## 8. Verification & Validation

### 8.1 Build Reproducibility Test
```bash
# Build twice and compare hashes
cmake --preset=arm-release && cmake --build build/target/release
sha256sum build/target/release/libsdk_core.so > hash1.txt

rm -rf build/target/release
cmake --preset=arm-release && cmake --build build/target/release
sha256sum build/target/release/libsdk_core.so > hash2.txt

diff hash1.txt hash2.txt  # Must be identical
```

### 8.2 Tool Qualification
Per IEC 62304, build tools must be qualified:
- **CMake**: Verified via checksum + test build suite
- **GCC/Linaro**: Vendor-provided qualification reports
- **Yocto**: Layer validation via `oe-selftest`

## 9. Troubleshooting

| Issue | Solution |
|-------|----------|
| ARM build fails with "undefined reference" | Verify sysroot is correctly populated |
| Mock HAL tests fail on x86 | Ensure `v4l2loopback` module is loaded |
| SBOM generation timeout | Increase memory limit for Syft process |

## 10. References
- CMake Documentation: https://cmake.org/cmake/help/latest/
- Yocto Project Dev Manual: https://docs.yoctoproject.org/dev-manual/index.html
- SPDX Specification: https://spdx.github.io/spdx-spec/v2.3/
