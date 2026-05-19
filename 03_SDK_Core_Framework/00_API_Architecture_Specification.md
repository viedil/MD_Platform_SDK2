# API Architecture Specification

## 1. Overview

This document defines the RESTful API architecture for the Medical Device Platform SDK. The API exposes core platform functions while maintaining strict compliance with IEC 62304 (Class B/C), ISO 14971, and FDA cybersecurity guidelines.

### 1.1 Design Principles

- **Safety First**: All endpoints enforce safety limits and validation before execution
- **Statelessness**: No session state maintained on server; client provides full context
- **Idempotency**: Critical operations (alarms, commands) support safe retry
- **Versioning**: Strict semantic versioning (`/api/v1/`) with deprecation policies
- **Auditability**: Every request logged with timestamp, user, action, and outcome
- **Zero-Trust Security**: Mutual TLS authentication, role-based access control (RBAC)

### 1.2 API Layers

```
┌─────────────────────────────────────────┐
│         Client Applications             │
│  (Dashboard, Mobile, EMR, Third-party) │
└──────────────┬──────────────────────────┘
               │ HTTPS / mTLS
┌──────────────▼──────────────────────────┐
│         API Gateway Layer               │
│  - Authentication & Authorization       │
│  - Rate Limiting & Throttling           │
│  - Request Validation & Sanitization    │
│  - Audit Logging                        │
└──────────────┬──────────────────────────┘
               │ Internal RPC / Message Queue
┌──────────────▼──────────────────────────┐
│       Safety Wrapper Layer              │
│  - Range Validation                     │
│  - Interlock Checks                     │
│  - Emergency Stop Logic                 │
└──────────────┬──────────────────────────┘
               │ Direct Function Calls
┌──────────────▼──────────────────────────┐
│        Core Logic Layer                 │
│  (Validated Medical Algorithms)         │
│  - Signal Processing                    │
│  - AI Inference                         │
│  - DICOM Handling                       │
└─────────────────────────────────────────┘
```

---

## 2. Endpoint Organization

Endpoints are organized by clinical function and data criticality:

| Category | Base Path | Description | Safety Class |
|----------|-----------|-------------|--------------|
| System | `/api/v1/system` | Device lifecycle, health, configuration | Class C |
| Patient | `/api/v1/patient` | Patient context, demographics, limits | Class B |
| Acquisition | `/api/v1/acquisition` | Raw data ingestion, streaming | Class B |
| Processing | `/api/v1/processing` | Medical algorithms, calculations | Class C |
| Alarms | `/api/v1/alarms` | Critical notifications, alerts | Class C |
| Connectivity | `/api/v1/connectivity` | HL7, FHIR, DICOM networking | Class B |
| Audit | `/api/v1/audit` | Compliance logs, traceability | Class B |

---

## 3. Authentication & Authorization

### 3.1 Authentication Methods

- **Mutual TLS (mTLS)**: Required for all production deployments
- **OAuth 2.0 / OIDC**: For user-facing applications
- **API Keys**: For service-to-service communication (restricted scopes)

### 3.2 Role-Based Access Control (RBAC)

| Role | Permissions | Use Case |
|------|-------------|----------|
| `clinician` | Read patient data, acknowledge alarms | Clinical workflow |
| `engineer` | Configuration, calibration, diagnostics | Maintenance |
| `admin` | User management, audit log export | Administration |
| `service` | Limited API access for specific modules | Integration |

### 3.3 Token Structure

```json
{
  "sub": "user_12345",
  "role": "clinician",
  "device_id": "MD-2024-001",
  "permissions": ["patient:read", "alarm:acknowledge"],
  "exp": 1735689600,
  "iat": 1735603200
}
```

---

## 4. Endpoint Specifications

### 4.1 System Endpoints (`/api/v1/system`)

#### `GET /health`
Device health status and self-test results.

**Response:**
```json
{
  "status": "operational",
  "uptime_seconds": 86400,
  "self_test": {
    "memory": "pass",
    "storage": "pass",
    "sensors": "pass",
    "last_run": "2024-01-15T08:00:00Z"
  },
  "warnings": []
}
```

#### `POST /shutdown`
Initiate controlled shutdown sequence.

**Request:**
```json
{
  "reason": "scheduled_maintenance",
  "delay_seconds": 60,
  "authorized_by": "admin_user"
}
```

**Safety Checks:**
- Verify no active patient monitoring session
- Confirm backup power availability
- Log shutdown event to audit trail

---

### 4.2 Patient Endpoints (`/api/v1/patient`)

#### `POST /context`
Set active patient context for monitoring session.

**Request:**
```json
{
  "patient_id": "MRN-123456",
  "demographics": {
    "age_years": 45,
    "weight_kg": 70.5,
    "sex": "M"
  },
  "safety_limits": {
    "hr_min_bpm": 50,
    "hr_max_bpm": 120,
    "spo2_min_percent": 90
  }
}
```

**Response:**
```json
{
  "session_id": "sess_abc123",
  "status": "active",
  "validated_limits": {
    "hr_min_bpm": 50,
    "hr_max_bpm": 120,
    "spo2_min_percent": 90
  }
}
```

#### `GET /limits`
Retrieve current safety limits for active patient.

**Response:**
```json
{
  "patient_id": "MRN-123456",
  "limits": {
    "hr": {"min": 50, "max": 120, "unit": "bpm"},
    "spo2": {"min": 90, "max": 100, "unit": "%"},
    "bp_systolic": {"min": 90, "max": 180, "unit": "mmHg"}
  },
  "source": "manual_override",
  "set_by": "clinician_001",
  "timestamp": "2024-01-15T09:30:00Z"
}
```

---

### 4.3 Acquisition Endpoints (`/api/v1/acquisition`)

#### `POST /start`
Start data acquisition from specified channels.

**Request:**
```json
{
  "channels": ["ecg_lead_ii", "spo2", "nibp"],
  "sample_rate_hz": 250,
  "duration_seconds": 3600,
  "storage_mode": "ring_buffer"
}
```

#### `GET /stream`
WebSocket endpoint for real-time data streaming.

**Protocol:** WebSocket over WSS
**Message Format:**
```json
{
  "timestamp": "2024-01-15T10:00:00.123Z",
  "channel": "ecg_lead_ii",
  "value": 0.85,
  "unit": "mV",
  "quality": "good"
}
```

---

### 4.4 Processing Endpoints (`/api/v1/processing`)

#### `POST /analyze/ecg`
Run ECG analysis algorithm on provided data.

**Request:**
```json
{
  "data": "base64_encoded_signal",
  "sample_rate_hz": 250,
  "algorithm_version": "v2.1.0"
}
```

**Response:**
```json
{
  "analysis_id": "ana_xyz789",
  "results": {
    "heart_rate_bpm": 72,
    "rhythm": "normal_sinus",
    "qt_interval_ms": 410,
    "st_elevation_mm": 0.1
  },
  "confidence": 0.95,
  "flags": [],
  "algorithm_version": "v2.1.0"
}
```

#### `POST /ai/infer`
Execute AI/ML inference on medical image or signal.

**Request:**
```json
{
  "model_id": "arrhythmia_detector_v3",
  "input_type": "ecg_12lead",
  "data": "base64_encoded_dicom_or_signal",
  "parameters": {
    "threshold": 0.85
  }
}
```

**Safety Constraints:**
- Model must be validated and approved for clinical use
- Output includes confidence score and uncertainty bounds
- Results flagged if input quality below threshold

---

### 4.5 Alarm Endpoints (`/api/v1/alarms`)

#### `GET /active`
List all active alarms with priority and details.

**Response:**
```json
{
  "alarms": [
    {
      "alarm_id": "alm_001",
      "priority": "high",
      "type": "tachycardia",
      "message": "Heart rate exceeded upper limit",
      "value": 135,
      "limit": 120,
      "unit": "bpm",
      "timestamp": "2024-01-15T10:15:00Z",
      "acknowledged": false
    }
  ],
  "total_count": 1,
  "highest_priority": "high"
}
```

#### `POST /acknowledge`
Acknowledge an active alarm.

**Request:**
```json
{
  "alarm_id": "alm_001",
  "acknowledged_by": "clinician_001",
  "notes": "Patient repositioned, monitoring"
}
```

#### `POST /silence`
Temporarily silence alarm (time-limited).

**Request:**
```json
{
  "alarm_id": "alm_001",
  "duration_seconds": 120,
  "authorized_by": "clinician_001",
  "reason": "procedural_interference"
}
```

**Safety Constraints:**
- Maximum silence duration: 120 seconds
- High-priority physiological alarms cannot be silenced > 60s
- Automatic re-alarm after silence period expires

---

### 4.6 Connectivity Endpoints (`/api/v1/connectivity`)

#### `POST /dicom/send`
Send DICOM study to configured PACS.

**Request:**
```json
{
  "study_instance_uid": "1.2.840.113619.2.123...",
  "destination_ae_title": "PACS_MAIN",
  "priority": "routine"
}
```

#### `POST /hl7/send`
Send HL7 v2.x message to EMR system.

**Request:**
```json
{
  "message_type": "ORU^R01",
  "payload": "MSH|^~\\&|DEVICE|HOSPITAL|EMR|HOSPITAL|202401151000||ORU^R01|MSG001|P|2.5...",
  "destination": "EMR_INTERFACE"
}
```

#### `GET /fhir/patient/{id}`
Fetch patient data from FHIR server.

**Response:** FHIR R4 Patient resource

---

### 4.7 Audit Endpoints (`/api/v1/audit`)

#### `GET /logs`
Query audit log entries with filters.

**Query Parameters:**
- `start_time`: ISO 8601 timestamp
- `end_time`: ISO 8601 timestamp
- `event_type`: e.g., `alarm`, `configuration_change`, `user_login`
- `user_id`: Filter by specific user

**Response:**
```json
{
  "entries": [
    {
      "event_id": "evt_12345",
      "timestamp": "2024-01-15T10:15:00Z",
      "event_type": "alarm_acknowledge",
      "user_id": "clinician_001",
      "details": {
        "alarm_id": "alm_001",
        "previous_state": "active",
        "new_state": "acknowledged"
      },
      "device_id": "MD-2024-001",
      "integrity_hash": "sha256:abc123..."
    }
  ],
  "total_count": 1,
  "query_time_ms": 45
}
```

#### `POST /export`
Export audit logs for regulatory submission.

**Request:**
```json
{
  "format": "pdf",
  "date_range": {
    "start": "2024-01-01T00:00:00Z",
    "end": "2024-01-31T23:59:59Z"
  },
  "include_integrity_proof": true
}
```

---

## 5. Error Handling

### 5.1 Standard Error Response Format

```json
{
  "error": {
    "code": "ERR_INVALID_PARAMETER",
    "message": "Parameter 'sample_rate_hz' out of valid range",
    "details": {
      "parameter": "sample_rate_hz",
      "provided_value": 5000,
      "valid_range": [1, 1000],
      "unit": "Hz"
    },
    "timestamp": "2024-01-15T10:00:00Z",
    "request_id": "req_abc123"
  }
}
```

### 5.2 Medical-Specific Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `ERR_SAFETY_LIMIT_EXCEEDED` | 400 | Requested value violates safety constraints |
| `ERR_PATIENT_NOT_SET` | 400 | No active patient context for operation |
| `ERR_DEVICE_NOT_READY` | 503 | Device in unsafe state for requested operation |
| `ERR_CALIBRATION_REQUIRED` | 400 | Calibration expired or invalid |
| `ERR_INTERLOCK_ACTIVE` | 400 | Hardware interlock preventing operation |
| `ERR_ALGORITHM_VERSION_MISMATCH` | 400 | Requested algorithm version not available |

---

## 6. Versioning Strategy

### 6.1 URL Versioning

All endpoints include version in path: `/api/v1/...`

### 6.2 Deprecation Policy

- **Minor versions**: Backward compatible, no breaking changes
- **Major versions**: Breaking changes allowed with 12-month deprecation notice
- **End-of-Life**: Previous major version supported for 24 months after new major release

### 6.3 Version Negotiation

Clients can request specific version via header:
```
Accept-Version: v1.2
```

---

## 7. Rate Limiting & Throttling

| Endpoint Category | Rate Limit | Burst Limit |
|-------------------|------------|-------------|
| `/system` | 60 req/min | 10 req/sec |
| `/patient` | 120 req/min | 20 req/sec |
| `/acquisition/stream` | Unlimited (WebSocket) | N/A |
| `/processing` | 30 req/min | 5 req/sec |
| `/alarms` | 300 req/min | 50 req/sec |
| `/audit` | 60 req/min | 10 req/sec |

**Response Headers:**
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1735603260
Retry-After: 60
```

---

## 8. Data Validation & Schema Enforcement

### 8.1 JSON Schema Validation

All request/response bodies validated against strict JSON schemas.

**Example Schema (Patient Context):**
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["patient_id", "safety_limits"],
  "properties": {
    "patient_id": {
      "type": "string",
      "pattern": "^MRN-[0-9]{6}$"
    },
    "demographics": {
      "type": "object",
      "properties": {
        "age_years": {"type": "integer", "minimum": 0, "maximum": 120},
        "weight_kg": {"type": "number", "minimum": 0.5, "maximum": 300}
      }
    },
    "safety_limits": {
      "type": "object",
      "required": ["hr_min_bpm", "hr_max_bpm"],
      "properties": {
        "hr_min_bpm": {"type": "integer", "minimum": 30, "maximum": 100},
        "hr_max_bpm": {"type": "integer", "minimum": 80, "maximum": 200}
      },
      "additionalProperties": false
    }
  }
}
```

### 8.2 Unit Validation

All numerical values must include explicit units where applicable. Default units documented per endpoint.

---

## 9. Security Considerations

### 9.1 Transport Security

- **TLS 1.3** required for all connections
- **Certificate Pinning** recommended for embedded clients
- **Perfect Forward Secrecy** enforced

### 9.2 Input Sanitization

- SQL injection prevention (parameterized queries)
- XSS prevention (output encoding)
- Command injection prevention (input validation)

### 9.3 Audit Requirements

Every API request logged with:
- Timestamp (synchronized via NTP)
- User identity and role
- Request method, path, and parameters
- Response status code
- Device identifier
- Integrity hash (SHA-256)

---

## 10. Implementation Roadmap

### Phase 1: Core API Foundation (Weeks 1-4)
- [ ] Implement API gateway with authentication
- [ ] Define JSON schemas for all endpoints
- [ ] Build `/system` and `/patient` endpoints
- [ ] Integrate audit logging

### Phase 2: Data & Processing (Weeks 5-8)
- [ ] Implement `/acquisition` streaming endpoints
- [ ] Build `/processing` algorithm wrappers
- [ ] Add WebSocket support for real-time data
- [ ] Performance optimization and load testing

### Phase 3: Safety & Compliance (Weeks 9-12)
- [ ] Implement `/alarms` with safety interlocks
- [ ] Add RBAC and enhanced authorization
- [ ] Complete `/audit` export functionality
- [ ] Regulatory documentation and validation

### Phase 4: Integration & Certification (Weeks 13-16)
- [ ] Build `/connectivity` (DICOM, HL7, FHIR)
- [ ] Third-party integration testing
- [ ] Cybersecurity penetration testing
- [ ] Final regulatory submission package

---

## 11. Testing Requirements

### 11.1 Unit Tests
- All endpoint handlers with mock dependencies
- Schema validation tests
- Error handling coverage (>95%)

### 11.2 Integration Tests
- End-to-end workflow testing
- Database and external service mocking
- Concurrent request handling

### 11.3 Safety Tests
- Boundary condition testing
- Fault injection and recovery
- Interlock verification

### 11.4 Performance Tests
- Load testing (peak capacity)
- Stress testing (beyond capacity)
- Latency benchmarks (<100ms for critical endpoints)

### 11.5 Security Tests
- Penetration testing
- OWASP Top 10 verification
- Certificate and token validation

---

## 12. Documentation Deliverables

- [ ] OpenAPI 3.0 specification (YAML)
- [ ] Interactive API documentation (Swagger UI)
- [ ] Postman collection for testing
- [ ] SDK client libraries (Python, C#, JavaScript)
- [ ] Integration guide for third-party developers
- [ ] Security implementation guide

---

## 13. Compliance Mapping

| Requirement | IEC 62304 | ISO 14971 | FDA Cybersecurity | API Implementation |
|-------------|-----------|-----------|-------------------|-------------------|
| Software Architecture | §5.1 | - | - | Layered design with safety wrapper |
| Risk Control Measures | §5.2 | §6.3 | - | Input validation, interlocks |
| Verification Testing | §5.6 | §7.2 | - | Comprehensive test suite |
| Traceability | §5.7 | §8.3 | - | Audit logs with integrity hashes |
| Cybersecurity | - | - | §5.3 | mTLS, RBAC, input sanitization |
| Incident Response | - | §9.3 | §6.2 | Real-time alarm endpoints |

---

## 14. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2024-01-15 | SDK Team | Initial API architecture specification |

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **mTLS** | Mutual Transport Layer Security - bidirectional certificate authentication |
| **RBAC** | Role-Based Access Control - permissions assigned to roles, not individuals |
| **SOUP** | Software Of Unknown Provenance - third-party components requiring validation |
| **SaMD** | Software as a Medical Device - software intended for medical purposes |
| **HL7** | Health Level Seven - healthcare data exchange standards |
| **FHIR** | Fast Healthcare Interoperability Resources - modern HL7 standard |
| **DICOM** | Digital Imaging and Communications in Medicine - medical imaging standard |

## Appendix B: Example cURL Commands

### Start Patient Monitoring Session
```bash
curl -X POST https://device.local/api/v1/patient/context \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "patient_id": "MRN-123456",
    "demographics": {
      "age_years": 45,
      "weight_kg": 70.5
    },
    "safety_limits": {
      "hr_min_bpm": 50,
      "hr_max_bpm": 120
    }
  }'
```

### Get Active Alarms
```bash
curl -X GET https://device.local/api/v1/alarms/active \
  -H "Authorization: Bearer <token>"
```

### Stream ECG Data (WebSocket)
```bash
wscat -c wss://device.local/api/v1/acquisition/stream \
  -H "Authorization: Bearer <token>"
```

### Export Audit Logs
```bash
curl -X POST https://device.local/api/v1/audit/export \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "format": "pdf",
    "date_range": {
      "start": "2024-01-01T00:00:00Z",
      "end": "2024-01-31T23:59:59Z"
    }
  }'
```
