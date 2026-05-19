# Compliance Checklist

This document provides phase-gated compliance checklists for medical device development using the SDK. Each checklist maps to specific regulatory requirements and includes artifact verification steps.

---

## Phase 1: Design Control (IEC 62304 §5.1-5.4, ISO 13485 §7.3)

### 1.1 Planning & Requirements

- [ ] **Software Development Plan (SDP)** documented and version-controlled
  - Artifact: `docs/planning/sdp_v1.0.pdf`
  - Review: Approved by QA and Regulatory Affairs
- [ ] **Problem Statement** clearly defined with intended use
  - Artifact: `docs/requirements/problem_statement.md`
  - Includes: Patient population, clinical environment, user profiles
- [ ] **Requirements Specification** with unique IDs and traceability
  - Artifact: `docs/requirements/sw_requirements.yaml`
  - Tool: `sdk-cli trace generate --input sw_requirements.yaml`
  - Coverage: 100% of user needs traced to software requirements
- [ ] **Risk Management Plan** initiated
  - Artifact: `docs/risk/risk_management_plan.md`
  - Includes: Risk acceptance criteria, hazard categories, review schedule

### 1.2 Architecture & Design

- [ ] **System Architecture Document** reviewed and approved
  - Artifact: `docs/design/system_architecture.md`
  - Includes: Block diagrams, interface definitions, data flow
  - Review: Architecture review board sign-off
- [ ] **Safety Class Determination** per IEC 62304
  - Artifact: `docs/risk/safety_class_justification.md`
  - Decision: Class A / Class B / Class C (with rationale)
- [ ] **Detailed Design Specifications** for all modules
  - Artifact: `docs/design/module_specs/*.md`
  - Includes: UML diagrams, state machines, sequence diagrams
  - Coverage: All Class C components require detailed design
- [ ] **Interface Control Documents (ICD)** for external systems
  - Artifact: `docs/design/icd/*.pdf`
  - Examples: DICOM network, HL7/FHIR API, device I/O protocols

### 1.3 SOUP Assessment

- [ ] **SOUP Inventory** complete with versions and licenses
  - Artifact: `docs/soup/soup_inventory.xlsx`
  - Tool: `sdk-cli sbom generate --output soup_inventory.json`
- [ ] **SOUP Risk Assessment** for each component
  - Artifact: `docs/soup/soup_risk_assessment.md`
  - Criteria: Known vulnerabilities, vendor support, community activity
- [ ] **Patch Management SLA** defined
  - Critical CVEs: <7 days
  - High CVEs: <30 days
  - Medium/Low: Quarterly review

---

## Phase 2: Implementation (IEC 62304 §5.5)

### 2.1 Coding Standards

- [ ] **Secure Coding Guidelines** adopted
  - Standard: CERT C/C++, MISRA C:2012 (for safety partitions)
  - Tool: Static analysis (SonarQube, CodeQL) integrated in CI
- [ ] **Code Review Process** documented
  - Requirement: All code reviewed before merge
  - Tool: GitHub/GitLab MR with ≥1 approver
  - Checklist: Security, safety, performance, maintainability
- [ ] **Unit Test Coverage** ≥90% (≥95% for Class C)
  - Tool: gcov/lcov reports in CI
  - Artifact: `reports/coverage/unit_coverage.html`
  - Enforcement: CI fails if coverage drops below threshold

### 2.2 Static Analysis & Quality Gates

- [ ] **Static Analysis** passes with zero critical/high issues
  - Tools: SonarQube, Cppcheck, clang-tidy
  - Artifact: `reports/static_analysis/q3_2024.pdf`
- [ ] **Memory Safety Checks** passed
  - Tools: Valgrind, AddressSanitizer, UndefinedBehaviorSanitizer
  - Artifact: `reports/memory_sanity/valgrind_log.txt`
- [ ] **Concurrency Analysis** completed
  - Tools: ThreadSanitizer, helgrind
  - Artifact: `reports/thread_safety/tsan_report.log`

### 2.3 Configuration Management

- [ ] **Version Control** strategy implemented
  - Branching: GitFlow or trunk-based with feature flags
  - Tagging: Semantic versioning (MAJOR.MINOR.PATCH)
- [ ] **Build Reproducibility** verified
  - Tool: Docker-based build environment
  - Test: Clean build from tagged commit matches release binary (hash verification)
- [ ] **Change Control Records** maintained
  - Tool: Jira/ADO linked to git commits
  - Artifact: `docs/change_control/ccr_*.md`

---

## Phase 3: Verification & Validation (IEC 62304 §5.6-5.7)

### 3.1 Integration Testing

- [ ] **Integration Test Plan** approved
  - Artifact: `docs/testing/integration_test_plan.md`
  - Coverage: All module interfaces tested
- [ ] **Hardware-in-the-Loop (HIL)** tests executed
  - Environment: Target hardware (QCS8550) + simulated peripherals
  - Artifact: `reports/hil/test_results_q3_2024.xlsx`
- [ ] **Cross-Platform Validation** (x86 mock → ARM target)
  - Test: Same test suite passes on x86 mock HAL and ARM production HAL
  - Artifact: `reports/cross_platform/validation_matrix.pdf`

### 3.2 System Testing

- [ ] **System Test Plan** aligned with requirements
  - Artifact: `docs/testing/system_test_plan.md`
  - Traceability: 100% of requirements covered by system tests
- [ ] **Performance Benchmarks** met
  - Boot time: <4 seconds (cold boot to UI ready)
  - AI inference latency: <15ms (95th percentile)
  - Video pipeline: ≤18ms frame-to-frame latency
  - Artifact: `reports/performance/benchmark_v2.0.pdf`
- [ ] **Stress & Soak Testing** completed
  - Duration: 72-hour continuous operation
  - Scenarios: Memory pressure, thermal throttling, network faults
  - Artifact: `reports/stress/soak_test_72h.log`

### 3.3 Clinical Validation

- [ ] **Clinical Validation Protocol** approved by IRB (if applicable)
  - Artifact: `docs/clinical/validation_protocol_v1.0.pdf`
- [ ] **Usability Testing** (formative + summative)
  - Standard: IEC 62366-1
  - Participants: ≥15 representative users
  - Artifact: `reports/usability/summative_study_report.pdf`
- [ ] **Clinical Performance Metrics** vs. endpoints
  - Sensitivity/Specificity (for AI modules)
  - Task completion rate, error rate
  - Artifact: `reports/clinical/performance_analysis.xlsx`

---

## Phase 4: Release & Post-Market (IEC 62304 §7, ISO 14971 §10)

### 4.1 Release Readiness

- [ ] **Verification & Validation Summary Report** complete
  - Artifact: `docs/release/vv_summary_report.pdf`
  - Sign-off: QA, RA, Engineering, Clinical
- [ ] **Residual Risk Assessment** updated
  - Artifact: `docs/risk/residual_risk_report_v1.0.pdf`
  - Review: Benefit-risk analysis acceptable
- [ ] **Unresolved Defects** documented with risk justification
  - Artifact: `docs/release/known_issues.md`
  - Criteria: No critical/high severity defects open
- [ ] **Release Notes** generated
  - Tool: `sdk-cli release notes --version 1.0.0`
  - Includes: New features, bug fixes, migration guide, compatibility matrix

### 4.2 Regulatory Submission Package

- [ ] **FDA 510(k) / De Novo** checklist complete
  - eSTAR template populated
  - Cybersecurity documentation (per FDA 2023 guidance)
  - Software validation summary (per IEC 62304)
  - Artifact: `/regulatory/fda/submission_package_v1.0/`
- [ ] **EU Technical File (MDR)** checklist complete
  - GSPR checklist with evidence references
  - Clinical Evaluation Report (CER)
  - Risk Management File (RMF)
  - PMS/PMCF plan
  - Artifact: `/regulatory/eu/technical_file_v1.0/`
- [ ] **SBOM** generated and attached
  - Format: CycloneDX + SPDX
  - Tool: `sdk-cli sbom export --format cyclonedx --output sbom.json`
  - Artifact: `/regulatory/sbom_release_1.0.0.json`

### 4.3 Post-Market Surveillance

- [ ] **PMS Plan** implemented
  - Artifact: `docs/pms/pms_plan_v1.0.md`
  - Includes: Complaint handling, adverse event reporting, trend analysis
- [ ] **Telemetry & Monitoring** enabled (opt-in for privacy)
  - Metrics: Crash reports, performance anomalies, error rates
  - Tool: Secure telemetry pipeline with PHI redaction
- [ ] **Vulnerability Monitoring** active
  - Sources: NVD, vendor advisories, security researcher reports
  - SLA: Critical CVEs patched within 7 days
- [ ] **Periodic Safety Update Report (PSUR)** schedule defined
  - Frequency: Annually (Class II), quarterly (Class III)
  - Artifact Template: `docs/pms/psur_template.docx`

---

## Pre-Submission Audit Checklist

Use this checklist 30-60 days before regulatory submission:

| Item | Status | Owner | Due Date | Notes |
|------|--------|-------|----------|-------|
| Design History File (DHF) complete | ☐ | Engineering | | All design reviews documented |
| Device Master Record (DMR) indexed | ☐ | QA | | Manufacturing procedures ready |
| Traceability Matrix validated | ☐ | RA | | 100% requirements → tests |
| Risk Management File audited | ☐ | RA | | Residual risk justified |
| Cybersecurity penetration test | ☐ | Security | | Independent lab report |
| Usability engineering file | ☐ | UX/RA | | Summative study complete |
| Software validation summary | ☐ | QA | | IEC 62304 compliance |
| Labeling & IFU reviewed | ☐ | RA/Marketing | | Regulatory compliant |
| eSTAR/Technical File dry run | ☐ | RA | | Mock audit passed |

---

## Checklist Maintenance

- **Review Frequency**: Quarterly or per major release
- **Owner**: Quality Assurance Manager
- **Approval**: Regulatory Affairs VP
- **Change Control**: All updates require RA/QA sign-off

**Document History:**

| Version | Date | Author | Changes | Approved By |
|---------|------|--------|---------|-------------|
| 1.0 | 2024-01-15 | QA Team | Initial release | QA Director |
| 1.1 | 2024-04-10 | QA Team | Added pre-submission audit checklist | RA VP |
| 2.0 | 2024-06-01 | QA Team | Expanded post-market surveillance section | QA Director |
