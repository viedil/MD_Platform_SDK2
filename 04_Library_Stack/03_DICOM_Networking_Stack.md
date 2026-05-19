# DICOM Networking Stack Specification

## 1. Overview
Defines the integration of **DCMTK** and **Orthanc** for DICOM communication, storage, and networking compliance with HIPAA and GDPR requirements.

## 2. Library Selection

| Component | Library | Version | Role | License |
|-----------|---------|---------|------|---------|
| DICOM Toolkit | DCMTK | 3.6.7 | Encoding/Decoding, SCP/SCU | BSD-like |
| DICOM Server | Orthanc | 1.12.1 | REST API, Storage, Routing | AGPL v3 |
| Alternative | GDCM | 3.0.21 | Parsing only (fallback) | BSD 2-Clause |

## 3. Security Configuration (HIPAA Compliance)

### 3.1 TLS/SSL Setup
- **Minimum Protocol**: TLS 1.2 (TLS 1.3 recommended).
- **Cipher Suites**: Restrict to AEAD ciphers (AES-GCM, ChaCha20-Poly1305).
- **Certificate Validation**: Enforce strict peer verification; no self-signed certs in production.

**DCMTK Configuration (`dcmnet.cfg`):**
```ini
NetworkTLS = YES
TLSCertificateFile = /etc/ssl/certs/device.crt
TLSPrivateKeyFile = /etc/ssl/private/device.key
TLSMinProtocolVersion = TLSv1.2
TLSCipherSuite = TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
RequirePeerVerification = YES
```

### 3.2 Authentication & Authorization
- **AE Title Whitelisting**: Only accept associations from known Application Entity Titles.
- **IP Filtering**: Restrict connections to specific subnets (e.g., hospital LAN).
- **User Authentication**: Orthanc REST API requires Basic Auth or JWT tokens.

## 4. Integration Patterns

### 4.1 Embedded SCU (Storage Commitment)
```cpp
#include "dcmtk/dcmnet/dimse.h"

T_ASC_Association *assoc;
T_ASC_Parameters *params;

// Initialize association
ASC_initializeAssociation(NET_REQUESTOR, port, "CALLING_AE", "CALLED_AE", ...);

// Send C-STORE request
DIMSE_storeUser(assoc, priority, dataset, fileName, ..., callback);

// Wait for Storage Commitment
DIMSE_waitForCommitment(assoc, timeout);
```

### 4.2 Orthanc Plugin for Custom Logic
```lua
-- Orthanc Lua script for auto-routing
function OnReceivedInstance(origin, instance)
    if instance.Modality == "CT" then
        Orthanc:MoveTo("PACS_SERVER", instance.ID)
    end
end
```

## 5. Performance Benchmarks

| Operation | Image Size | Latency (LAN) | Throughput | Target |
|-----------|------------|---------------|------------|--------|
| C-ECHO | N/A | < 10 ms | N/A | < 50 ms |
| C-STORE (CT) | 512x512x200 | 1.2 s | 85 MB/s | < 2 s |
| C-FIND | 1000 records | 150 ms | N/A | < 500 ms |
| WADO-RS | 10 MB series | 400 ms | 25 MB/s | < 1 s |

## 6. Validation Tests
1.  **Conformance Testing**: Pass ACR/NEMA DICOM validation suite.
2.  **Stress Test**: Handle 100 concurrent C-STORE requests without dropping packets.
3.  **Failover Test**: Verify graceful reconnection after network interruption.

## 7. References
- [DICOM Standard](https://www.dicomstandard.org/)
- [DCMTK Documentation](https://support.dcmtk.org/docs/)
- [Orthanc Book](https://book.orthanc-server.com/)
