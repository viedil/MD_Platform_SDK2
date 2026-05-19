# Known Constraints and Workarounds

| Risk                            | Impact                  | Mitigation                                                               |
| ------------------------------- | ----------------------- | ------------------------------------------------------------------------ |
| QCS8550 hypervisor maturity     | Isolation stability     | Use Qualcomm reference Type-1 + fallback to PREEMPT_RT + cgroups         |
| Linux real-time limits (<100µs) | Hard safety loops       | Mandate external Cortex-R MCU + `SafetyBridge` with certified IPC        |
| AI model drift (Class III)      | Clinical accuracy       | PCCP shadow mode + continuous monitoring + rollback + physician override |
| Thermal throttling (passive)    | Performance degradation | Dynamic DVFS + workload prioritization + thermal guard API               |
| SOUP CVE exposure               | Compliance failure      | Automated SBOM + 30-day patch SLA + offline patch testing pipeline       |

* 


