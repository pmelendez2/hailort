# MPS prematurely disconnects live clients across Docker PID namespaces

## Summary

In HailoRT v4.24.0, the host-side MPS service may discard a live client
running in a different PID namespace. The service assumes the client PID
is valid in the service's own namespace.

## Affected source

`hailort/hailort_service/hailort_rpc_service.cpp`,
`HailoRtRpcService::remove_disconnected_clients()`.

The original removal condition is:

```cpp
if ((duration > hailort::HAILO_KEEPALIVE_INTERVAL) ||
    (!OsUtils::is_pid_alive(client_pid))) {
```

On POSIX, `OsUtils::is_pid_alive(pid)` uses `kill(pid, 0)`. This checks a
PID in the caller's namespace, not in the client's container namespace.

## Reproduction outline

1. Run HailoRT v4.24.0 MPS on the host.
2. Connect a HailoRT v4.24.0 inference client from a container with its own
   PID namespace, through the MPS Unix-domain socket.
3. Configure a Hailo-8 inference model and run sustained inference.
4. Observe MPS client-disconnection logs and check for
   `HAILO_NOT_FOUND(61)` / detector failure.

Exact timing can depend on PID collisions and namespace mappings. An
application-level configuration success does not prove later inference works.

## Actual result

In a Frigate 0.18.2 / Hailo-8 reproduction, MPS repeatedly logged
`Client disconnected`, then Frigate failed with `HAILO_NOT_FOUND(61)`.
A subsequent native MPS crash occurred in disconnected-client cleanup.
The native crash is reported as an associated observation, not as a proven
direct consequence.

## Expected result

A live client sending timely keepalives must not be disconnected merely
because its container-local PID does not exist in the host PID namespace.

## Proposed patch

Replace the combined condition with:

```cpp
if (duration > hailort::HAILO_KEEPALIVE_INTERVAL) {
```

See `hailort/hailort_service/hailort_rpc_service.cpp` and
`docs/MPS_CONTAINER_PID_NAMESPACE.md` for tradeoffs. This intentionally
defers dead-client cleanup until keepalive expiration.

## Validation evidence

A patched v4.24.0 MPS service supported sustained Frigate inference in
the observed single-session test window: 17.7 aggregate detection FPS, 22.9 ms detector
inference time, zero container/service restarts, and no observed MPS
disconnections or `HAILO_NOT_FOUND` errors.

See `docs/MPS_HARDWARE_VALIDATION.md` and
`scripts/test-mps-container-pid-namespace.sh`.

## Request

Please verify cross-namespace client tracking, add a regression test for
containerized clients, and consider a namespace-safe cleanup mechanism
for a future HailoRT release. Investigate the disconnected-client cleanup
crash separately.

All reproduction details above have been sanitized for public disclosure.
