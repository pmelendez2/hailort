#!/usr/bin/env bash
# Source check; optionally inspect an existing service and Frigate container.
# Does not start, stop, or modify the runtime.
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
SRC="$ROOT/hailort/hailort_service/hailort_rpc_service.cpp"

if [ ! -f "$SRC" ]; then
    echo "FAIL: MPS source not found" >&2
    exit 1
fi

python3 - "$SRC" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
start = "void HailoRtRpcService::remove_disconnected_clients()"
end = "void HailoRtRpcService::keep_alive()"
if source.count(start) != 1 or source.count(end) != 1:
    sys.exit("FAIL: expected MPS function boundaries not found")
body = source.split(start, 1)[1].split(end, 1)[0]
expected = "if (duration > hailort::HAILO_KEEPALIVE_INTERVAL)"
if expected not in body:
    sys.exit("FAIL: keepalive-only cleanup check missing")
if "OsUtils::is_pid_alive" in body:
    sys.exit("FAIL: host-local PID liveness check still present")
print("PASS: keepalive-only MPS client cleanup condition")
PY
status=$?
if [ "$status" -ne 0 ]; then
    exit "$status"
fi

if [ "${1:-}" != "--runtime" ]; then
    echo "Source test complete (runtime inspection skipped)"
    exit 0
fi

container="${FRIGATE_CONTAINER:-frigate}"
service="${HAILORT_SERVICE:-hailort.service}"
since="${TEST_SINCE:-1 hour ago}"

echo "=== HailoRT service ==="
systemctl is-active --quiet "$service" || {
    echo "FAIL: MPS service is not active" >&2
    exit 1
}
systemctl show "$service" -p ActiveState -p MainPID -p NRestarts

echo "=== Frigate container ==="
docker inspect "$container" \
    --format 'State={{.State.Status}} Restarts={{.RestartCount}}' ||
    exit 1

echo "=== Frigate errors ==="
if docker logs --since 1h "$container" 2>&1 |
    grep -Ei 'HAILO_NOT_FOUND|HAILO_SHUTDOWN|detect_raw|inference thread has stopped'; then
    echo "FAIL: inference error signature present" >&2
    exit 1
fi
echo "PASS: no matched Frigate inference errors"

echo "=== MPS cleanup errors ==="
if journalctl -u "$service" --since "$since" --no-pager 2>&1 |
    grep -Ei 'Client disconnected|segfault|core dumped'; then
    echo "FAIL: MPS cleanup error signature present" >&2
    exit 1
fi
echo "PASS: no matched MPS disconnection/crash entries"
echo "NOTE: this inspection does not prove inference is active"
