# API Endpoint Specifications

This document provides detailed specifications for the 7 core endpoint categories of the MD_Platform_SDK2 API. Each category is designed with specific safety classifications, data criticality levels, and compliance requirements per IEC 62304 and ISO 14971.

## 1. `/system` - Device Lifecycle & Safety Core

**Safety Class:** IEC 62304 Class C (Highest Risk)  
**Purpose:** Controls fundamental device states, boot sequences, health monitoring, self-tests, and safe-mode transitions.

### 1.1 Endpoints

#### `POST /system/boot`
Initiates controlled boot sequence with pre-boot safety checks.

**Request:**
```json
{
  "boot_mode": "normal|safe|diagnostic|recovery",
  "force": false,
  "checksum_verify": true
}
```

**Response:**
```json
{
  "status": "initiated|running|completed|failed",
  "boot_id": "uuid",
  "estimated_duration_ms": 5000,
  "safety_checks": {
    "memory_integrity": "pass",
    "sensor_calibration": "pass",
    "power_stability": "pass"
  }
}
```

**Safety Controls:**
- Requires dual-key authentication for `recovery` mode
- Automatic rollback if boot exceeds timeout
- Watchdog timer integration (hardware + software)
- State machine enforcement (cannot boot if already running)

#### `GET /system/health`
Real-time device health status with component-level diagnostics.

**Response:**
```json
{
  "overall_status": "healthy|degraded|critical|failed",
  "uptime_seconds": 86400,
  "components": {
    "cpu": {"usage_percent": 45, "temperature_c": 42.5, "status": "normal"},
    "memory": {"used_mb": 512, "total_mb": 2048, "ecc_errors": 0},
    "storage": {"used_percent": 65, "wear_level": 98, "bad_sectors": 0},
    "sensors": {"active_count": 8, "failed_count": 0, "calibration_due": false},
    "network": {"link_status": "up", "packet_loss_percent": 0.01}
  },
  "last_self_test": "2024-01-15T10:30:00Z",
  "next_maintenance_due": "2024-02-15T00:00:00Z"
}
```

#### `POST /system/self-test`
Executes comprehensive diagnostic suite with configurable depth.

**Request:**
```json
{
  "test_level": "quick|standard|comprehensive",
  "components": ["all", "sensors", "memory", "storage", "network"],
  "interrupt_patient_care": false
}
```

**Response (Streaming):**
```json
{
  "test_id": "uuid",
  "status": "running",
  "progress_percent": 45,
  "current_test": "memory_ecc_check",
  "results_so_far": {
    "sensor_connectivity": "pass",
    "adc_calibration": "pass",
    "memory_quick": "pass"
  }
}
```

**Final Response:**
```json
{
  "test_id": "uuid",
  "status": "completed",
  "overall_result": "pass|fail|warning",
  "duration_ms": 12500,
  "detailed_results": [...],
  "recommendations": ["Replace battery in 30 days", "Recalibrate SpO2 sensor"]
}
```

#### `POST /system/safe-mode`
Transitions device to restricted functionality state for maintenance or emergency.

**Request:**
```json
{
  "reason": "maintenance|emergency|calibration|software_update",
  "duration_minutes": 30,
  "preserve_patient_data": true,
  "notify_connected_systems": true
}
```

**Safety Controls:**
- Requires confirmation if patient monitoring is active
- Automatic exit after duration expires (unless extended)
- Logs all safe-mode entries/exits to audit trail
- Disables non-essential services only

---

## 2. `/patient` - Context & Safety Limits

**Safety Class:** IEC 62304 Class B/C (Context-dependent)  
**Purpose:** Manages patient identity, demographic data, and safety envelopes with hard/soft limit enforcement.

### 2.1 Endpoints

#### `POST /patient/session`
Creates new patient monitoring session with safety context.

**Request:**
```json
{
  "patient_id": "MRN123456",
  "patient_demographics": {
    "age_years": 65,
    "weight_kg": 75.5,
    "gender": "M|F|O",
    "neonatal": false,
    "pediatric": false
  },
  "safety_profile": "adult_standard|pediatric|neonatal|custom",
  "attending_clinician_id": "DR789",
  "location": "ICU-Bed-3"
}
```

**Response:**
```json
{
  "session_id": "uuid",
  "created_at": "2024-01-15T14:30:00Z",
  "expires_at": "2024-01-15T20:30:00Z",
  "active_limits": {
    "heart_rate": {"min": 50, "max": 120, "source": "adult_standard"},
    "spo2": {"min": 90, "max": 100, "source": "adult_standard"},
    "bp_systolic": {"min": 90, "max": 180, "source": "adult_standard"}
  },
  "session_token": "jwt_token"
}
```

**Safety Controls:**
- Session binding required for all `/acquisition` and `/processing` calls
- Automatic timeout after 6 hours of inactivity
- Cannot create overlapping sessions for same patient
- Demographics validation against age-specific limits

#### `PUT /patient/{session_id}/limits`
Modifies alarm limits with role-based access control.

**Request:**
```json
{
  "parameter": "heart_rate",
  "limit_type": "hard_min|hard_max|soft_min|soft_max",
  "value": 55,
  "reason": "patient_specific_condition",
  "clinician_id": "DR789",
  "expiry_minutes": 120
}
```

**Response:**
```json
{
  "limit_id": "uuid",
  "previous_value": 50,
  "new_value": 55,
  "effective_until": "2024-01-15T16:30:00Z",
  "requires_confirmation": false,
  "audit_entry_id": "audit_uuid"
}
```

**Safety Controls:**
- Hard limits require senior clinician approval (dual authentication)
- Changes outside standard ranges trigger confirmation dialog
- All modifications logged with reason and clinician ID
- Automatic reversion to default after expiry

#### `GET /patient/{session_id}/context`
Retrieves current patient context and active safety parameters.

**Response:**
```json
{
  "session_id": "uuid",
  "patient_id": "MRN123456",
  "session_start": "2024-01-15T14:30:00Z",
  "current_limits": {...},
  "active_alarms": [],
  "recent_events": [
    {"timestamp": "...", "type": "limit_change", "details": "..."}
  ],
  "data_quality": {
    "signal_quality_score": 0.95,
    "artifact_detected": false,
    "sensor_contact": "good"
  }
}
```

#### `DELETE /patient/{session_id}`
Terminates patient session with data archival.

**Request:**
```json
{
  "archive_data": true,
  "export_format": "dicom|hl7|pdf",
  "destination": "PACS_SERVER_ID",
  "reason": "discharge|transfer|procedure_complete"
}
```

**Safety Controls:**
- Warns if active alarms exist
- Requires confirmation if session < 5 minutes old
- Triggers automatic data export to EMR
- Maintains audit trail for 7+ years

---

## 3. `/acquisition` - Raw Data Ingestion

**Safety Class:** IEC 62304 Class B  
**Purpose:** High-throughput sensor data streaming with precise timestamping and backpressure management.

### 3.1 Endpoints

#### `POST /acquisition/stream`
Initiates real-time data stream from specified sensors.

**Request:**
```json
{
  "session_id": "uuid",
  "channels": ["ecg_lead_ii", "spo2", "nibp", "resp"],
  "sample_rates_hz": {
    "ecg_lead_ii": 250,
    "spo2": 100,
    "nibp": 1,
    "resp": 50
  },
  "format": "json|binary|protobuf",
  "compression": "none|gzip|lz4",
  "websocket_url": "wss://device.local/ws/acquisition"
}
```

**WebSocket Message Format:**
```json
{
  "stream_id": "uuid",
  "timestamp_ns": 1705329000123456789,
  "channel": "ecg_lead_ii",
  "unit": "mV",
  "values": [0.125, 0.130, 0.128, ...],
  "quality_flags": ["good_signal", "no_artifact"],
  "sequence_number": 12345
}
```

**Safety Controls:**
- Sequence number validation to detect packet loss
- Timestamp synchronization via PTP/NTP (±1ms accuracy)
- Backpressure signaling when buffer > 80%
- Automatic stream termination on session expiry

#### `GET /acquisition/batch`
Retrieves historical data within specified time window.

**Request:**
```json
{
  "session_id": "uuid",
  "channels": ["ecg_lead_ii"],
  "start_time": "2024-01-15T14:30:00Z",
  "end_time": "2024-01-15T14:35:00Z",
  "downsample_hz": 50,
  "format": "csv|json|dicom_waveform"
}
```

**Response:**
```json
{
  "query_id": "uuid",
  "total_samples": 75000,
  "duration_seconds": 300,
  "data_url": "https://device.local/data/batch/uuid",
  "metadata": {
    "channel_info": {...},
    "quality_summary": {...}
  }
}
```

#### `POST /acquisition/channel-config`
Dynamically configures sensor channel parameters.

**Request:**
```json
{
  "session_id": "uuid",
  "channel": "ecg_lead_ii",
  "gain": 1000,
  "filter": {
    "highpass_hz": 0.5,
    "lowpass_hz": 40,
    "notch_hz": 50
  },
  "mask": false
}
```

**Safety Controls:**
- Gain changes require signal quality verification
- Filter changes validated against clinical requirements
- Channel masking logged and time-limited
- Cannot disable all channels simultaneously

---

## 4. `/processing` - Medical Algorithms & AI

**Safety Class:** IEC 62304 Class B/C (Algorithm-dependent)  
**Purpose:** Clinical parameter computation with version locking and deterministic execution guarantees.

### 4.1 Endpoints

#### `POST /processing/compute`
Executes specified medical algorithm on input data.

**Request:**
```json
{
  "session_id": "uuid",
  "algorithm": "heart_rate_detection|arrhythmia_analysis|spo2_calculation",
  "algorithm_version": "2.3.1",
  "input_data_ref": "stream_id_or_batch_id",
  "parameters": {
    "window_size_seconds": 10,
    "overlap_percent": 50
  },
  "output_format": "immediate|batch"
}
```

**Response:**
```json
{
  "computation_id": "uuid",
  "status": "completed",
  "execution_time_ms": 45,
  "results": {
    "heart_rate_bpm": 72,
    "rhythm_classification": "normal_sinus",
    "confidence_score": 0.98,
    "beat_annotations": [...]
  },
  "algorithm_metadata": {
    "version": "2.3.1",
    "validation_date": "2023-12-01",
    "regulatory_status": "FDA_cleared"
  }
}
```

**Safety Controls:**
- Algorithm version locking (cannot use unvalidated versions)
- Execution time monitoring (timeout if > guaranteed max)
- Fallback to simpler algorithm if primary fails
- Results validation against physiological plausibility

#### `GET /processing/algorithms`
Lists available algorithms with validation status.

**Response:**
```json
{
  "algorithms": [
    {
      "id": "heart_rate_detection",
      "name": "Heart Rate Detection",
      "versions": [
        {"version": "2.3.1", "status": "active", "cleared_by": "FDA", "cleared_date": "2023-12-01"},
        {"version": "2.2.0", "status": "deprecated", "sunset_date": "2024-06-01"}
      ],
      "input_requirements": {"ecg_channel": "required", "minimum_duration_s": 5},
      "output_specification": {...},
      "performance_metrics": {
        "sensitivity": 0.995,
        "specificity": 0.998,
        "latency_ms": 50
      }
    }
  ]
}
```

#### `POST /processing/ai-inference`
Executes AI/ML model inference with explainability output.

**Request:**
```json
{
  "session_id": "uuid",
  "model_id": "afib_detection_v3",
  "input_data_ref": "stream_id",
  "explainability": true,
  "confidence_threshold": 0.85
}
```

**Response:**
```json
{
  "inference_id": "uuid",
  "prediction": "atrial_fibrillation",
  "confidence": 0.92,
  "explanation": {
    "key_features": ["irregular_rr_intervals", "absent_p_waves"],
    "feature_importance": [0.65, 0.28],
    "similar_cases_count": 1247
  },
  "fallback_triggered": false,
  "model_version": "3.1.0",
  "regulatory_clearance": "FDA_de_novo"
}
```

**Safety Controls:**
- Confidence threshold enforcement
- Mandatory fallback logic for low-confidence predictions
- Explainability required for Class C decisions
- Model drift monitoring and alerts

---

## 5. `/alarms` - Critical Notifications

**Safety Class:** IEC 62304 Class C + IEC 60601-1-8  
**Purpose:** Alarm management with priority inheritance, auditable silencing, and multi-channel notification.

### 5.1 Endpoints

#### `GET /alarms/active`
Retrieves all currently active alarms with priority classification.

**Response:**
```json
{
  "active_alarms": [
    {
      "alarm_id": "uuid",
      "priority": "high|medium|low|advisory",
      "type": "physiological|technical|system",
      "parameter": "heart_rate",
      "condition": "bradycardia",
      "value": 42,
      "limit_violated": "hard_min",
      "triggered_at": "2024-01-15T15:22:30Z",
      "duration_seconds": 15,
      "acknowledged": false,
      "silenced": false,
      "escalation_level": 1
    }
  ],
  "summary": {
    "high_priority_count": 1,
    "medium_priority_count": 0,
    "total_active": 1
  }
}
```

#### `POST /alarms/{alarm_id}/acknowledge`
Acknowledges alarm with clinician identification.

**Request:**
```json
{
  "clinician_id": "NURSE456",
  "action_taken": "assessing_patient",
  "notes": "Patient sleeping, vitals stable"
}
```

**Response:**
```json
{
  "alarm_id": "uuid",
  "acknowledged_at": "2024-01-15T15:23:00Z",
  "acknowledged_by": "NURSE456",
  "status": "acknowledged_active",
  "auto_resolve_timeout_seconds": 300
}
```

#### `POST /alarms/{alarm_id}/silence`
Temporarily silences alarm with strict controls.

**Request:**
```json
{
  "clinician_id": "DR789",
  "duration_seconds": 120,
  "reason": "known_artifact|procedure_in_progress",
  "requires_witness": false
}
```

**Response:**
```json
{
  "alarm_id": "uuid",
  "silenced_until": "2024-01-15T15:25:00Z",
  "silenced_by": "DR789",
  "remaining_silence_seconds": 120,
  "audit_entry_id": "audit_uuid",
  "reactivation_condition": "time_expiry|condition_resolved"
}
```

**Safety Controls:**
- Maximum silence duration enforced (typically 120s for high priority)
- High-priority alarms require senior clinician for silencing
- All silence events logged with reason and clinician ID
- Automatic re-silence prevention (cooldown period)

#### `WS /alarms/stream`
WebSocket stream for real-time alarm notifications.

**Message Format:**
```json
{
  "event_type": "alarm_triggered|alarm_acknowledged|alarm_silenced|alarm_resolved",
  "alarm_id": "uuid",
  "timestamp": "2024-01-15T15:22:30Z",
  "priority": "high",
  "details": {...}
}
```

#### `POST /alarms/config`
Configures alarm behavior and notification routing.

**Request:**
```json
{
  "session_id": "uuid",
  "parameter": "heart_rate",
  "notification_channels": ["device_display", "nurse_station", "mobile_app"],
  "escalation_policy": {
    "level_1_delay_s": 0,
    "level_2_delay_s": 30,
    "level_3_delay_s": 120
  },
  "audio_enabled": true,
  "visual_enabled": true
}
```

---

## 6. `/connectivity` - Interoperability

**Safety Class:** IEC 62304 Class B  
**Purpose:** Hospital network integration with DICOM, HL7, and FHIR support.

### 6.1 Endpoints

#### `POST /connectivity/dicom/send`
Sends DICOM objects to PACS or other DICOM nodes.

**Request:**
```json
{
  "destination_ae_title": "PACS_MAIN",
  "destination_host": "10.0.1.50",
  "destination_port": 104,
  "data_type": "waveform|image|report",
  "data_ref": "batch_id_or_session_id",
  "study_instance_uid": "uuid",
  "priority": "normal|high"
}
```

**Response:**
```json
{
  "transmission_id": "uuid",
  "status": "queued|sending|completed|failed",
  "dicom_status_code": "0000",
  "bytes_sent": 524288,
  "duration_ms": 1250
}
```

**Safety Controls:**
- Store-and-forward capability for network interruptions
- Retry logic with exponential backoff
- Encryption in transit (TLS 1.3 mandatory)
- Audit log of all DICOM transactions

#### `POST /connectivity/hl7/send`
Sends HL7 v2.x messages to HIS/EMR systems.

**Request:**
```json
{
  "message_type": "ORM^O01|ORU^R01|ADT^A01",
  "destination_host": "10.0.1.100",
  "destination_port": 2575,
  "payload": "MSH|^~\\&|DEVICE|HOSPITAL|EMR|HOSPITAL|202401151530||ORU^R01|MSG123|P|2.5...",
  "ack_required": true,
  "timeout_seconds": 30
}
```

**Response:**
```json
{
  "message_id": "MSG123",
  "status": "sent|ack_received|failed",
  "hl7_ack_code": "AA",
  "response_message": "MSA|AA|MSG123|...",
  "round_trip_ms": 145
}
```

#### `GET /connectivity/fhir/patient/{patient_id}`
Retrieves patient data from FHIR server.

**Response:**
```json
{
  "resourceType": "Patient",
  "id": "MRN123456",
  "name": [{"family": "Smith", "given": ["John"]}],
  "birthDate": "1958-05-15",
  "gender": "male",
  "extension": [...]
}
```

#### `POST /connectivity/fhir/observation`
Posts clinical observations to FHIR server.

**Request:**
```json
{
  "resourceType": "Observation",
  "status": "final",
  "category": [{"coding": [{"system": "...", "code": "vital-signs"}]}],
  "code": {"coding": [{"system": "http://loinc.org", "code": "8867-4", "display": "Heart rate"}]},
  "subject": {"reference": "Patient/MRN123456"},
  "effectiveDateTime": "2024-01-15T15:30:00Z",
  "valueQuantity": {"value": 72, "unit": "beats/minute", "system": "...", "code": "/min"}
}
```

#### `GET /connectivity/status`
Reports connectivity status to all configured systems.

**Response:**
```json
{
  "connections": [
    {
      "system_type": "PACS",
      "ae_title": "PACS_MAIN",
      "status": "connected",
      "last_successful_transaction": "2024-01-15T15:28:00Z",
      "latency_ms": 45
    },
    {
      "system_type": "EMR",
      "protocol": "HL7",
      "status": "disconnected",
      "last_error": "connection_refused",
      "retry_in_seconds": 30
    }
  ]
}
```

---

## 7. `/audit` - Compliance & Traceability

**Safety Class:** IEC 62304 Class B (Supporting)  
**Purpose:** Immutable logging with WORM architecture and cryptographic integrity verification.

### 7.1 Endpoints

#### `GET /audit/events`
Queries audit log with filtering and pagination.

**Request:**
```json
{
  "start_time": "2024-01-15T00:00:00Z",
  "end_time": "2024-01-15T23:59:59Z",
  "event_types": ["alarm_silenced", "limit_changed", "user_login"],
  "user_ids": ["DR789", "NURSE456"],
  "severity": ["critical", "warning"],
  "page": 1,
  "page_size": 100
}
```

**Response:**
```json
{
  "total_count": 247,
  "page": 1,
  "page_size": 100,
  "events": [
    {
      "event_id": "uuid",
      "timestamp": "2024-01-15T15:23:00Z",
      "event_type": "alarm_silenced",
      "severity": "warning",
      "user_id": "DR789",
      "description": "High priority heart rate alarm silenced",
      "context": {
        "alarm_id": "uuid",
        "duration_seconds": 120,
        "reason": "procedure_in_progress"
      },
      "integrity_hash": "sha256_abc123..."
    }
  ],
  "integrity_verification": {
    "chain_valid": true,
    "first_event_hash": "...",
    "last_event_hash": "..."
  }
}
```

#### `POST /audit/export`
Exports audit logs in regulatory-compliant format.

**Request:**
```json
{
  "start_time": "2024-01-01T00:00:00Z",
  "end_time": "2024-01-15T23:59:59Z",
  "format": "pdf|csv|xml",
  "include_integrity_proof": true,
  "destination": "local|secure_server",
  "encryption_key_id": "key_uuid"
}
```

**Response:**
```json
{
  "export_id": "uuid",
  "status": "processing|completed|failed",
  "file_url": "https://device.local/audit/exports/uuid.pdf",
  "file_size_bytes": 5242880,
  "record_count": 15420,
  "integrity_manifest_url": "...",
  "expiry_time": "2024-01-16T15:30:00Z"
}
```

#### `GET /audit/integrity`
Verifies cryptographic integrity of audit log chain.

**Response:**
```json
{
  "verification_status": "valid|compromised|unknown",
  "chain_length": 50000,
  "first_event_timestamp": "2023-01-01T00:00:00Z",
  "last_event_timestamp": "2024-01-15T15:30:00Z",
  "root_of_trust": "device_serial_number_hash",
  "last_verified_at": "2024-01-15T15:30:05Z",
  "verification_method": "hash_chain_with_timestamp_tokens"
}
```

#### `POST /audit/tamper-alert`
Manual trigger for integrity investigation (auto-triggered on detection).

**Request:**
```json
{
  "reported_by": "SYSTEM_MONITOR",
  "suspected_event_id": "uuid",
  "reason": "hash_mismatch_detected",
  "evidence_refs": ["log_segment_123", "backup_copy_456"]
}
```

**Response:**
```json
{
  "alert_id": "uuid",
  "status": "investigating",
  "quarantine_initiated": true,
  "forensic_mode_enabled": true,
  "notification_sent_to": ["security_officer", "quality_manager"],
  "case_number": "INC-2024-0115-001"
}
```

**Safety Controls:**
- Write-once-read-many (WORM) storage enforcement
- Cryptographic hash chaining (each event includes previous hash)
- Tamper detection with immediate alerting
- Retention policy enforcement (7+ years typical)
- Role-based access (read-only for most users)
- Export encryption and access logging

---

## Cross-Cutting Concerns

### Authentication & Authorization
All endpoints require:
- mTLS certificate for device-to-device communication
- OAuth 2.0 bearer token for user-facing operations
- Role-based access control (RBAC) with least-privilege principle
- Session binding for patient-specific operations

### Error Handling
Standard error response format:
```json
{
  "error_code": "MD_API_001",
  "error_type": "validation_error|safety_interlock|system_error",
  "message": "Human-readable description",
  "details": {...},
  "remediation": "Suggested corrective action",
  "timestamp": "2024-01-15T15:30:00Z",
  "request_id": "uuid"
}
```

Medical-specific error codes:
- `MD_API_001`: Validation error (invalid parameter)
- `MD_API_002`: Safety interlock (operation blocked by safety system)
- `MD_API_003`: Session expired or invalid
- `MD_API_004`: Patient context mismatch
- `MD_API_005`: Alarm silence limit exceeded
- `MD_API_006`: Algorithm execution timeout
- `MD_API_007`: Regulatory compliance violation
- `MD_API_008`: Audit log integrity failure

### Rate Limiting
- Standard endpoints: 100 requests/minute per client
- High-throughput streaming: negotiated bandwidth allocation
- Critical alarms: no rate limiting (always delivered)
- Audit queries: 10 requests/minute (resource-intensive)

### Versioning
- URL versioning: `/api/v1/system/health`
- Backward compatibility maintained for 2 major versions
- Deprecation notices 12 months in advance
- Version negotiation via Accept header

### Documentation Deliverables
Each endpoint must have:
- OpenAPI 3.0 specification
- Example request/response pairs
- Safety classification justification
- Risk control measures documentation
- Test case references
- Performance benchmarks
