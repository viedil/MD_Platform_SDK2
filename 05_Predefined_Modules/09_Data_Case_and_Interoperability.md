# 09 Data Case and Interoperability Module

## 1. Purpose
Manages structured patient data, study metadata, and ensures interoperability with Hospital Information Systems (HIS) and Picture Archiving and Communication Systems (PACS).

## 2. Safety Classification (IEC 62304)
- **Safety Class**: B (Data corruption could lead to wrong patient data association).
- **Critical Functions**: Patient ID matching, data integrity checksums, audit logging.

## 3. Data Model
- **Internal Schema**: SQLite/PostgreSQL database following FHIR Resource structure.
- **DICOM SR**: Structured Reporting for measurements and findings.
- **Export Formats**: DICOMDIR, XML, JSON (FHIR), CSV (for research export).

## 4. Interoperability Features
- **Worklist SCU**: Queries RIS for scheduled patients.
- **Modality Performed Procedure Step (MPPS)**: Reports exam status (IN PROGRESS, COMPLETED, DISCONTINUED).
- **Storage Commitment**: Confirms successful archival to PACS before local deletion.

## 5. x86 Mock Strategy
- **Embedded DB**: Uses file-based SQLite identical to target.
- **FHIR Simulator**: HAPI FHIR server running in Docker for integration tests.
- **Data Generators**: Synthetic patient data generators (Synthea) for load testing.

## 6. API Specification
```cpp
class IDataManager {
public:
    virtual Result<Patient> getPatient(const std::string& id) = 0;
    virtual Result<void> saveStudy(const Study& study) = 0;
    virtual Result<void> exportToFHIR(const std::string& studyId, const std::string& endpoint) = 0;
    virtual void purgeOldData(int days) = 0; // Respects retention policies
};
```

## 7. Verification Requirements
- [ ] Verify patient ID uniqueness across database.
- [ ] Verify MPPS messages are sent within 5s of state change.
- [ ] Verify data export includes all required DICOM tags (Type 1 & 2).
