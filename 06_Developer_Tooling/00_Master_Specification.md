# Developer Tooling & CI/CD Specification

## Overview
This section defines the toolchain, automation pipelines, and PC-based tools required for developing, testing, and certifying the Medical Device Platform SDK.

## Core Principles
1. **Single Source of Truth**: CMake generates both IDE projects and Yocto recipes.
2. **x86/ARM Parity**: All tools must run on x86 (mock) and ARM (target).
3. **Regulatory Evidence**: CI/CD pipelines automatically generate audit artifacts.

## Tool Categories

### 1. SDK CLI & Configurator
- **Purpose**: Command-line interface for device configuration, module management, and diagnostics.
- **Key Commands**: `sdk-cli config`, `sdk-cli module list`, `sdk-cli diag --mock`.
- **Mock Mode**: Supports `--mock` flag for x86 development without hardware.

### 2. Static Analysis & SCA
- **Tools**: Cppcheck, Clang-Tidy, SonarQube, Black Duck.
- **Rulesets**: MISRA C++14, CERT C++, CWE Top 25.
- **Quality Gates**: Zero critical/high defects allowed for release.

### 3. SBOM & Certification Packaging
- **Formats**: SPDX 2.3, CycloneDX.
- **Automation**: Generated at every build; included in regulatory submission pack.

### 4. CI/CD Pipeline
- **Stages**: Build (x86) → Test (x86) → Cross-Compile (ARM) → HIL Test (ARM) → Package.
- **Artifacts**: Test reports, coverage data, SBOM, binary signatures.

### 5. PC-Based Tools (New)
- **Qt Configurator**: Visual parameter editor with schema validation.
- **AI Model Workbench**: Model conversion (ONNX → TensorRT/QNN), accuracy profiling.
- **System Debug Suite**: Live trace viewer, memory monitor, remote GDB server.

## Regulatory Compliance
- **Tool Qualification**: Per IEC 62304 Section 7.1 (SOUP validation).
- **Audit Trail**: All tool versions and configurations logged in SBOM.

## Sub-Documents
- [01_SDK_CLI_and_Configurator.md](01_SDK_CLI_and_Configurator.md)
- [02_Static_Analysis_and_SCA.md](02_Static_Analysis_and_SCA.md)
- [03_SBOM_and_Certification_Packaging.md](03_SBOM_and_Certification_Packaging.md)
- [04_CI_CD_Pipeline.md](04_CI_CD_Pipeline.md)
- [05_PC_Based_Tools_Spec.md](05_PC_Based_Tools_Spec.md)
