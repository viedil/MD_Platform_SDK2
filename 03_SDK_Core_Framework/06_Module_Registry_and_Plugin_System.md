## Module Registry and Plugin System

## Registry Service

* D-Bus based discovery
* YAML config-driven enablement
* Health probing every 5s

## Plugin Lifecycle

1. Load: Validate ABI, signature, dependencies
2. Init: Allocate resources, register callbacks
3. Start: Enter operational state
4. Monitor: Heartbeat, error reporting
5. Stop: Graceful teardown
6. Unload: Free memory, deregister

## Security

* Signed plugins only (RSA-3072)
* Sandboxed via cgroups + seccomp
* Audit log on load/unload/start/stop 


