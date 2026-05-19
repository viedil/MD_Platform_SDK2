# Security and Cryptography Libraries Specification

## 1. Overview
Defines the cryptographic primitives and security libraries used for data protection, secure communication, and device authentication in compliance with FDA cybersecurity guidance and FIPS 140-2 requirements.

## 2. Library Selection

| Library | Version | License | FIPS Mode | Usage |
|---------|---------|---------|-----------|-------|
| **OpenSSL** | 3.0.10 | Apache 2.0 | ✅ Yes (3.0+) | TLS, X.509, General Crypto |
| **mbedTLS** | 3.5.0 | Apache 2.0 | ⏳ Pending | Embedded lightweight crypto |
| **Libsodium** | 1.0.18 | ISC | ❌ No | Modern AEAD, Key Exchange |

## 3. Configuration for Medical Devices

### 3.1 OpenSSL FIPS 140-2 Enablement
To achieve FIPS compliance, OpenSSL 3.0 must be built and configured with the FIPS module:

```bash
# Build configuration
./config enable-fips no-ssl3 no-comp -DOPENSSL_TLS_SECURITY_LEVEL=2

# Runtime configuration (openssl.cnf)
[provider_sect]
default = default_sect
fips = fips_sect

[fips_sect]
activate = 1
conditional-error-links = 1
```

### 3.2 TLS Hardening Profile
Enforce strict cipher suites and protocol versions for all network communications:

```cpp
SSL_CTX *ctx = SSL_CTX_new(TLS_method());

// Enforce TLS 1.2 minimum
SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);

// Restrict to secure ciphers only
SSL_CTX_set_cipher_list(ctx, 
    "TLS_AES_256_GCM_SHA384:"
    "TLS_CHACHA20_POLY1305_SHA256:"
    "ECDHE-RSA-AES256-GCM-SHA384:"
    "ECDHE-RSA-CHACHA20-POLY1305"
);

// Enable Perfect Forward Secrecy
SSL_CTX_set_options(ctx, SSL_OP_SINGLE_DH_USE);
```

## 4. Key Management Strategy

### 4.1 Secure Storage
- **Hardware Root of Trust**: Store private keys in QCS8550 Secure Environment (SE) or TPM.
- **Software Fallback**: Encrypt keys at rest using AES-256-GCM with device-unique derived keys.

### 4.2 Key Derivation
Use HKDF (HMAC-based Key Derivation Function) for deriving session keys:
```cpp
unsigned char *okm;
size_t okm_len;
HKDF(EVP_sha256(), ikm, ikm_len, salt, salt_len, info, info_len, okm, okm_len);
```

## 5. Data Integrity & Signing

### 5.1 Firmware Signing
- **Algorithm**: RSA-4096 or ECDSA P-384.
- **Hash**: SHA-384.
- **Workflow**: Sign boot images and SDK modules during CI/CD; verify signature at runtime before execution.

### 5.2 Audit Log Integrity
- Append-only logs signed with HMAC-SHA256.
- Chain log entries using hash pointers (blockchain-style) to detect tampering.

## 6. Validation Requirements
1.  **FIPS Validation**: Use pre-validated OpenSSL FIPS Object Module (or document self-validation plan).
2.  **Penetration Testing**: Perform annual pentests focusing on TLS implementation and key storage.
3.  **Vulnerability Scanning**: Integrate `openssl CVE` checks into CI pipeline.

## 7. References
- [OpenSSL FIPS User Guide](https://docs.openssl.org/master/man7/fips_module/)
- [NIST FIPS 140-3](https://csrc.nist.gov/publications/detail/fips/140/3/final)
- [FDA Cybersecurity Guidance 2023](https://www.fda.gov/media/165726/download)
