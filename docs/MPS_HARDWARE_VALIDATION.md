# HailoRT v4.24.0 MPS hardware validation

<!-- BEGIN GENERATED HAILORT RELEASE METADATA -->
**Fork release:** `v4.24.0-mps.1`
**Upstream HailoRT baseline:** `v4.24.0`
**HailoRT ABI/runtime:** `4.24.0`
**Modified component:** Host MPS client cleanup
**Hardware validation:** Raspberry Pi 5 ARM64, Hailo-8 only
**PCIe kernel driver:** Separate upstream `hailort-drivers` project
<!-- END GENERATED HAILORT RELEASE METADATA -->

## Environment

- Hardware: Raspberry Pi 5, full Hailo-8 M.2 accelerator
- Operating system: Ubuntu 26.04 (ARM64)
- HailoRT service, runtime library and firmware: 4.24.0
- Application: Frigate 0.18.2, running in Docker
- MPS: host-side `hailort_service`, Unix-domain socket
- Detector: one Hailo detector configured to use MPS

## Observed behavior before the patch

A containerized detector encountered `HAILO_NOT_FOUND(61)` after
configuration, during inference setup. Host MPS logs repeatedly reported
client disconnections. A later MPS native crash occurred while cleaning up
disconnected-client resources. These observations are consistent with the
PID namespace / host PID-check defect, but do not prove the native crash
has no other cause.

## Observed behavior after the patch

During the live test on 2026-11-20:

- Patched service built successfully for ARM64
- The staged executable resolved installed `libhailort.so.4.24.0`
- MPS service restarted successfully with the patched executable
- Frigate remained running with zero container restarts
- MPS remained active with zero service restarts
- Frigate exposed a live Hailo detector with measured inference
- Aggregate detection rate: 17.7 FPS
- Detector inference speed: 22.9 ms
- Accelerator temperature: 55.1 C
- No `HAILO_NOT_FOUND`, inference exceptions, repeated client
  disconnections, or MPS crashes observed in the verification window

These are single-session results from 2026-11-20, not a long-duration soak test.
The detector reported a live process and successful inference, rather
than merely the absence of errors.

## Follow-up regression coverage

Upstream maintainers should test:
1. Service in host PID namespace and inference client in a container PID
   namespace, with active keepalives and sustained inference.
2. An actual client termination, confirming resource reclamation after
   keepalive timeout.
3. Two concurrent MPS clients with distinct PID namespaces.
4. Startup and shutdown cycles, to cover configured network-group cleanup.
5. Native cleanup stability; investigate the separately observed crash.

No device identifiers, camera names, raw logs, or private infrastructure
addresses are included in this document.
