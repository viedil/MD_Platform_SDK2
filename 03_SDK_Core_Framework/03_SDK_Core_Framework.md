# SDK Core Framework

## Build System & Meta-Layer

* **Distro**: `medsdk-rt` (Yocto Kirkstone-based)
* **Layers**: `meta-qcom`, `meta-preempt-rt`, `meta-medcore`, `meta-medmodules`
* **Image**: `medsdk-base-image` (minimal), `medsdk-full-image` (dev + tools)
* **Update**: OSTree + `rpm-ostree` for atomic upgrades

## Configuration & Device Tree

* `medsdk-config.yaml`: Global platform config
* `medsdk-peripherals.yaml`: Hardware mapping
* `medsdk-modules.yaml`: Enable/disable modules
* CLI: `medsdk-cli configure --target=devkit --mode=production`

## API Design Principles

* **Language**: C++17 core, Python 3.11 bindings, C for safety bridge
* **Memory**: RAII, `std::unique_ptr`, lock-free queues for RT paths
* **Error Handling**: `medsdk::Status` (enum + message + trace)
* **Threading**: `SCHED_FIFO` for RT, thread pools for UI/AI/network
* **Logging**: `spdlog` + structured JSON + cryptographic audit

## Module Registry & Plugin System

* **Registry**: YAML + runtime discovery via D-Bus
* **Plugin**: `libmedplugin` (versioned ABI, hot-reload safe)
* **Lifecycle**: `init() → configure() → start() → monitor() → stop() → cleanup()`
* **Validation**: Plugin must pass `medsdk-cli validate-plugin <path>`
