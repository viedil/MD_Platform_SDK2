# Build System and Meta-Layer

## Yocto Structure

    meta-medcore/
    ├── conf/
    ├── recipes-core/
    ├── recipes-medmodules/
    ├── recipes-tools/
    └── classes/

## Key Classes

* `medsdk-sooup.bbclass`: SOUP tracking, license scanning, CVE check
* `medsdk-rt-kernel.bbclass`: PREEMPT_RT patching, config validation
* `medsdk-module.bbclass`: Plugin packaging, ABI versioning

## Build Commands

    repo init -u https://github.com/medsdk/manifest -b kirkstone-rt
    repo sync
    source setup-env --machine=qcs8550
    bitbake medsdk-full-image


