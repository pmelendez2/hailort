# HailoRT 4.24.0 MPS runtime tests

Run these on **picam** in the `hailort-4.24.0` repository root. Build the service natively on picam. The runtime tests inspect the
installed service; they do not install a replacement.

## Read-only runtime check

```bash
bash tests/test-mps-runtime.sh
```

The runtime check verifies systemd state, the installed service executable's
SHA-256, and Frigate container health. `MPS_EXPECTED_SHA` is required. Supply the independently verified
SHA-256 of the intended installed service executable before
running this test. There is no hardcoded default checksum.

## Controlled stop/start regression

**This interrupts Frigate.** HailoRT itself is not stopped or restarted.

```bash
MPS_STOP_HOLD_SECONDS=150 \
MPS_HEALTH_TIMEOUT_SECONDS=180 \
bash tests/test-mps-lifecycle.sh --run
```

Frigate management uses only `sacntr_mgr -s frigate` to stop and
`sacntr_mgr -u frigate` to start. Docker is used only for inspection.

The regression requires:

- Initially healthy Frigate and active HailoRT.
- Unchanged HailoRT MainPID and NRestarts while Frigate is stopped.
- No HailoRT SIGSEGV/core-dump journal event during the test.
- Frigate becomes healthy after restart without a HailoRT restart.

The script attempts to restart Frigate if interrupted or if a check fails
while it is stopped. If health never recovers, investigate Frigate logs.

A `Client disconnected` journal event confirms the keepalive cleanup path
was observed. Absence is reported as a NOTE, not proof that it was exercised;
normal graceful release may avoid that path. Container health alone does
not prove that inference FPS has resumed. Verify detector FPS separately.

The scripts deliberately do not modify source code, create commits, or
install binaries.
