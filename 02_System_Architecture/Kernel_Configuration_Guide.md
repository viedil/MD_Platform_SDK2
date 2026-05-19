# Kernel Configuration Guide

## 1. Overview
This document specifies the Linux kernel configuration for the Medical Device Platform SDK, ensuring real-time performance, safety, and security compliance with IEC 62304 Class C requirements.

## 2. Kernel Version & Base
- **Base Kernel**: Linux 6.6 LTS (Long Term Support)
- **Real-Time Patch**: PREEMPT_RT (full real-time support)
- **Architecture Support**: 
  - Primary: ARM64 (Qualcomm QCS8550)
  - Development: x86_64 (Intel/AMD)
- **Maintenance**: Quarterly security updates, annual LTS upgrade

## 3. Core Configuration Options

### 3.1 Real-Time (PREEMPT_RT)
```config
CONFIG_PREEMPT_RT=y
CONFIG_NO_HZ_FULL=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_TIMER_STATS=n  # Disable for determinism
CONFIG_LATENCYTOP=y
CONFIG_PROVE_LOCKING=y
CONFIG_DEBUG_ATOMIC_SLEEP=y
```

**Performance Targets:**
- Maximum interrupt latency: < 50 µs
- Maximum scheduling latency: < 100 µs
- Worst-case execution time (WCET): Bounded and measured

### 3.2 Memory Management
```config
CONFIG_CGROUPS=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_CGROUP_MEMORY=y
CONFIG_CGROUP_PIDS=y
CONFIG_MEMCG_SWAP=n  # Disable swap for determinism
CONFIG_TRANSPARENT_HUGEPAGE=n  # Disable to prevent latency spikes
CONFIG_COMPACTION=y
CONFIG_MIGRATION=y
```

**Memory Partitioning:**
- Critical processes: Isolated via cgroups v2
- Memory locking: `mlockall()` enforced for real-time tasks
- OOM killer: Tuned to protect medical applications

### 3.3 Security Hardening
```config
CONFIG_SECURITY=y
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_APPARMOR=y
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_STRICT_DEVMEM=y
CONFIG_IO_STRICT_DEVMEM=y
CONFIG_REFCOUNT_FULL=y
CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y
CONFIG_INIT_ON_FREE_DEFAULT_ON=y
CONFIG_SLUB_DEBUG=y
CONFIG_PAGE_POISONING=y
CONFIG_RANDOMIZE_BASE=y
CONFIG_RANDOMIZE_MODULE_REGION_FULL=y
```

**Additional Hardening:**
- Kernel module signing: Enforced (`CONFIG_MODULE_SIG_FORCE=y`)
- Lockdown mode: Integrity mode in production
- KASLR: Enabled for all kernel regions

### 3.4 Device Drivers
```config
CONFIG_UIO=y
CONFIG_UIO_PDRV_GENIRQ=y
CONFIG_VFIO=y
CONFIG_VFIO_PCI=y
CONFIG_IOMMU_API=y
CONFIG_INTEL_IOMMU=y  # For x86 development
CONFIG_ARM_SMMU=y     # For ARM target
CONFIG_DMA_CMA=y
CONFIG_CONTIGUOUS_ALLOC=y
```

**Driver Requirements:**
- All medical device drivers: Must be mainline or well-audited out-of-tree
- Userspace drivers: Preferred via UIO/VFIO for isolation
- DMA: IOMMU-enabled for all DMA-capable devices

### 3.5 Networking
```config
CONFIG_NET=y
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_NETFILTER=y
CONFIG_NF_TABLES=y
CONFIG_CGROUP_NET_PRIO=y
CONFIG_NET_SCHED=y
CONFIG_NET_CLS_CGROUP=y
```

**Network Isolation:**
- Network namespaces: For containerized workloads
- Traffic prioritization: TC (Traffic Control) for QoS
- Firewall: nftables-based ruleset

### 3.6 Filesystems
```config
CONFIG_EXT4_FS=y
CONFIG_F2FS_FS=y
CONFIG_OVERLAY_FS=y
CONFIG_TMPFS=y
CONFIG_ECRYPT_FS=y
CONFIG_SQUASHFS=y
```

**Filesystem Requirements:**
- Root filesystem: Read-only SquashFS + OverlayFS
- Data partition: EXT4 with journaling
- Encryption: eCryptfs for sensitive patient data

## 4. Architecture-Specific Configurations

### 4.1 ARM64 (QCS8550 Target)
```config
CONFIG_ARM64=y
CONFIG_ARCH_QCOM=y
CONFIG_QCOM_GPI_DMA=y
CONFIG_QCOM_IOMMU=y
CONFIG_ARM_SCMI=y
CONFIG_ARM_SCPI_PROTOCOL=n
CONFIG_QCOM_SMEM=y
CONFIG_QCOM_SMD_RPM=y
CONFIG_QCOM_RPMH=y
CONFIG_QCOM_GLINK_SSR=y
```

**Qualcomm-Specific Features:**
- DSP offloading: Hexagon DSP drivers enabled
- Hardware accelerators: Video, AI, crypto drivers
- Power management: RPMh (Resource Power Manager)

### 4.2 x86_64 (Development Host)
```config
CONFIG_X86_64=y
CONFIG_ACPI=y
CONFIG_PCI=y
CONFIG_PCIEPORTBUS=y
CONFIG_INTEL_IOMMU_DEFAULT_ON=y
CONFIG_AMD_IOMMU=y
CONFIG_HPET_TIMER=y
CONFIG_X86_LOCAL_APIC=y
```

**Parity Requirements:**
- Feature parity: All medical-relevant features must work on x86
- Mock HAL: x86 uses software emulation for QCS8550-specific hardware
- Performance validation: x86 used for functional testing, ARM for timing validation

## 5. Boot Parameters

### 5.1 Required Kernel Command Line
```bash
# Real-time tuning
isolcpus=2-3 nohz_full=2-3 rcu_nocbs=2-3
intel_pstate=disable processor.max_cstate=1 pcie_aspm=off

# Memory tuning
cgroup_memory=nokmem transparent_hugepage=never

# Security
lockdown= integrity iommu=force

# Logging
loglevel=3 earlycon=uart8250,mmio32,0x00984000
```

### 5.2 Optional Debug Parameters (Development Only)
```bash
# Never enable in production!
debug_tracepoints=1 ftrace_dump_on_oops
kernelcore=mirror slub_debug=FZP
```

## 6. Verification & Validation

### 6.1 Configuration Validation Script
```bash
#!/bin/bash
# verify_kernel_config.sh

REQUIRED_CONFIGS=(
    "CONFIG_PREEMPT_RT=y"
    "CONFIG_HIGH_RES_TIMERS=y"
    "CONFIG_CGROUPS=y"
    "CONFIG_SECURITY_SELINUX=y"
    "CONFIG_MODULE_SIG_FORCE=y"
)

for config in "${REQUIRED_CONFIGS[@]}"; do
    if ! grep -q "$config" /proc/config.gz; then
        echo "FAIL: Missing $config"
        exit 1
    fi
done

echo "PASS: All required kernel configs present"
```

### 6.2 Test Cases
1. **TC-KC-01**: Verify PREEMPT_RT is active (`/sys/kernel/realtime`)
2. **TC-KC-02**: Measure interrupt latency (< 50 µs worst-case)
3. **TC-KC-03**: Verify cgroups v2 hierarchy is mounted
4. **TC-KC-04**: Confirm kernel modules are signed
5. **TC-KC-05**: Validate lockdown mode is enforced

### 6.3 Tool Qualification
- **Config Validation**: Custom script (qualified per IEC 62304)
- **Latency Measurement**: cyclictest, hwlatdetect (calibrated)
- **Security Scanning**: kconfig-hardened-check (verified version)

## 7. Documentation & Traceability
- **Requirements**: SYS-REQ-KER-001 through SYS-REQ-KER-015
- **Risk Controls**: RC-SAF-003 (deterministic scheduling), RC-SAF-004 (memory isolation)
- **Test Reports**: TR-KC-001 (Kernel Configuration Validation Report)

---
**Document Control**
- Version: 1.0
- Status: Released
- Author: System Architecture Team
- Review Date: 2024-Q2
