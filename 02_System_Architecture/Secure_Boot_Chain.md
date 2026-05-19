# Secure Boot Chain Specification

## 1. Overview
This document defines the secure boot chain for the Medical Device Platform SDK, ensuring integrity and authenticity from power-on to application execution. Compliant with IEC 62304 Class C requirements and FDA cybersecurity guidance.

## 2. Chain of Trust Architecture

### 2.1 Boot Stages
```
+-------------+    +-------------+    +-------------+    +-------------+    +-------------+
|   SoC ROM   | -> |  U-Boot SPL | -> | ARM Trusted | -> |   U-Boot    | -> |   Linux     |
|  (Immutable)|    |   (Signed)  |    |  Firmware   |    |  (Signed)   |    |  Kernel     |
|             |    |             |    |   (ATF)     |    |             |    |  (Signed)   |
+-------------+    +-------------+    +-------------+    +-------------+    +-------------+
       |                  |                  |                  |                  |
       v                  v                  v                  v                  v
   Hardware          Verify SPL         Verify ATF        Verify DTB/      Verify Kernel
   Root of           Signature          Signature        Initramfs        & Modules
   Trust             (RSA-4096)         (RSA-4096)       (SHA-256)        (RSA-4096)
```

### 2.2 Security Requirements
| Stage | Component | Cryptographic Algorithm | Key Size | Storage |
|-------|-----------|------------------------|----------|---------|
| ROM | Boot ROM | RSA-PSS | 4096-bit | Fuses (eFuse) |
| SPL | u-boot-spl.bin | RSA-PSS + SHA-256 | 4096-bit | QSPI Flash |
| ATF | bl31.bin | RSA-PSS + SHA-256 | 4096-bit | QSPI Flash |
| U-Boot | u-boot.itb | RSA-PSS + SHA-256 | 4096-bit | QSPI Flash |
| Kernel | Image + dtb | RSA-PSS + SHA-256 | 4096-bit | eMMC/UFS |

## 3. Implementation Details

### 3.1 Key Management
- **Root of Trust**: Public key hash burned into SoC eFuses during manufacturing
- **Key Rotation**: Support for dual-key slots (active/rollback) for firmware updates
- **Key Storage**: HSM-backed key generation, never expose private keys off secure facility

### 3.2 Image Signing Process
```bash
# Example: Sign U-Boot image
openssl pkeyutl -sign -in u-boot.bin \
  -inkey private_key.pem -out u-boot.sig \
  -pkeyopt rsa_padding_mode:pss -pkeyopt rsa_pss_saltlen:32

# Create FIT image with signature
mkimage -f u-boot.its u-boot.itb
```

### 3.3 Rollback Protection
- **Anti-Rollback Counter**: Monotonically increasing counter in eFuse
- **Verification**: Bootloader rejects images with security version < current fuse value
- **Emergency Recovery**: JTAG-based recovery mode (factory use only, disabled in production)

## 4. Failure Modes & Recovery

| Failure Scenario | Detection Point | Recovery Action | User Impact |
|------------------|-----------------|-----------------|-------------|
| Corrupted SPL | ROM verification | Boot to USB recovery mode | Device unbootable, requires service |
| Signature Mismatch | SPL/U-Boot/Kernel | Halt boot, display error code | Device unbootable, requires SD card recovery |
| Rollback Attempt | All stages | Permanent lockout, error logged | Device bricked (security feature) |
| Watchdog Timeout | Any stage | Reset to last known good image | Brief interruption (<2s) |

## 5. Development vs Production

### 5.1 Development Mode
- **Secure Boot**: Disabled (JTAG strap pin)
- **Unsigned Images**: Allowed for rapid iteration
- **Debug Interfaces**: JTAG/SWD enabled
- **Warning**: Never ship devices in dev mode

### 5.2 Production Mode
- **Secure Boot**: Enforced (fuse blown)
- **Unsigned Images**: Rejected immediately
- **Debug Interfaces**: Permanently disabled
- **Audit Trail**: All boot attempts logged to secure storage

## 6. Verification & Validation

### 6.1 Test Cases
1. **TC-SB-01**: Verify signed image boots successfully
2. **TC-SB-02**: Verify tampered image is rejected
3. **TC-SB-03**: Verify rollback attempt is blocked
4. **TC-SB-04**: Verify recovery mode functions correctly
5. **TC-SB-05**: Measure boot time impact (<500ms overhead)

### 6.2 Tool Qualification
- **Signing Tools**: OpenSSL, mkimage (qualified per IEC 62304)
- **Test Equipment**: Logic analyzer, JTAG debugger (calibrated annually)

## 7. Documentation & Traceability
- **Requirements**: SYS-REQ-SEC-001 through SYS-REQ-SEC-010
- **Risk Controls**: RC-CYB-001 (tamper detection), RC-CYB-002 (secure update)
- **Test Reports**: TR-SB-001 (Secure Boot Validation Report)

---
**Document Control**
- Version: 1.0
- Status: Released
- Author: System Architecture Team
- Review Date: 2024-Q2
