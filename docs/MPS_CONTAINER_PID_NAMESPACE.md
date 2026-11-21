# MPS client cleanup with container PID namespaces

<!-- BEGIN GENERATED HAILORT RELEASE METADATA -->
**Fork release:** `v4.24.0-mps.1`
**Upstream HailoRT baseline:** `v4.24.0`
**HailoRT ABI/runtime:** `4.24.0`
**Modified component:** Host MPS client cleanup
**Hardware validation:** Raspberry Pi 5 ARM64, Hailo-8 only
**PCIe kernel driver:** Separate upstream `hailort-drivers` project
<!-- END GENERATED HAILORT RELEASE METADATA -->

## Scope

HailoRT v4.24.0, `hailort_service`, and clients executing in a PID
namespace different from the namespace of the MPS service.

## Problem

`HailoRtRpcService::remove_disconnected_clients()` originally removed
clients when either their keepalive was stale **or** `OsUtils::is_pid_alive`
returned false. On POSIX systems, that liveness check uses `kill(pid, 0)`.

A PID reported by a containerized client is interpreted in the host MPS
daemon's PID namespace. It need not identify the client in that namespace.
Consequently, a live client with a current keepalive can have its MPS
resources released prematurely.

The observed workload produced `HAILO_NOT_FOUND(61)` during inference,
repeated `Client disconnected` messages from MPS, and a subsequent native
MPS crash during disconnected-client resource cleanup. The crash was observed
after inference had already failed; its independent cause is not established.

## Proposed fix

In `hailort/hailort_service/hailort_rpc_service.cpp`, remove the host-local
PID-existence alternative from the removal condition, leaving the existing
`HAILO_KEEPALIVE_INTERVAL` timeout in place.

This changes cleanup timing for genuinely terminated clients: resources are
released on keepalive expiration rather than by an immediate PID check.
Keepalive timeout behavior, PID reuse, and concurrent-client workloads deserve
additional upstream regression testing.

## Build and verification

Build the `hailort_service` target against the same v4.24.0 runtime library
as the installed service. Do not install the entire source tree or overwrite
drivers or firmware as part of this service-only test.

Run `scripts/test-mps-container-pid-namespace.sh` to verify the source
condition, or add `--runtime` to inspect an already running MPS and Frigate
installation. The runtime check reports process state and error indicators;
it does not create inference traffic.

Before deployment, ensure the service executable resolves the intended
installed version of `libhailort.so.4.24.0`, not a development build path.
Retain the original service executable for rollback.

See `MPS_BUILD_AND_CI.md` for reproducible local hooks, Gitleaks, CI,
and the service-only build procedure.

## Privacy

Do not attach raw logs, core dumps, camera names, local hostnames, network
addresses, device serial numbers, or personal filesystem paths to public
reports. Publish only redacted findings and aggregate performance metrics.
