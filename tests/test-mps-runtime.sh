#!/usr/bin/env bash
# Read-only HailoRT / Frigate diagnostics on picam.
# Does not start, stop, or modify services.
set -uo pipefail

service="${HAILORT_SERVICE:-hailort.service}"
container="${FRIGATE_CONTAINER:-frigate}"
expected_sha="${MPS_EXPECTED_SHA:-}"
service_binary="${HAILORT_SERVICE_BINARY:-/usr/local/bin/hailort_service}"
errors=0

if [[ ! "$expected_sha" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo 'FAIL: MPS_EXPECTED_SHA must be a 64-character SHA-256' >&2
    exit 2
fi
expected_sha="${expected_sha,,}"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; errors=$((errors + 1)); }

for command in systemctl docker sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        fail "required command missing: $command"
    }
done
if (( errors > 0 )); then
    exit 1
fi

printf '=== HailoRT service ===\n'
systemctl show "$service" -p ActiveState -p MainPID -p NRestarts
active="$(systemctl show "$service" -p ActiveState --value)"
pid="$(systemctl show "$service" -p MainPID --value)"
if [[ "$active" == active && "$pid" =~ ^[0-9]+$ && "$pid" != 0 ]]; then
    pass "HailoRT active (PID $pid)"
else
    fail "HailoRT service inactive or missing PID"
fi

printf '\n=== Installed executable ===\n'
if [[ -f "$service_binary" ]]; then
    actual_sha="$(sha256sum "$service_binary" | awk '{print $1}')"
    printf 'SHA-256: %s\n' "$actual_sha"
    if [[ "$actual_sha" == "$expected_sha" ]]; then
        pass 'installed executable matches expected SHA-256'
    else
        fail 'installed executable SHA-256 mismatch'
    fi
else
    fail "service executable missing: $service_binary"
fi

printf '\n=== Frigate state ===\n'
state="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)" || state=""
health="$(docker inspect --format \
    '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
    "$container" 2>/dev/null)" || health=""
printf 'State=%s Health=%s\n' "${state:-unknown}" "${health:-unknown}"
if [[ "$state" == running && "$health" == healthy ]]; then
    pass 'Frigate running and healthy'
else
    fail 'Frigate not both running and healthy'
fi

printf '\n=== Recent HailoRT events (diagnostic only) ===\n'
if command -v journalctl >/dev/null 2>&1; then
    journalctl -u "$service" --since '15 minutes ago' --no-pager \
        2>/dev/null | grep -Ei \
        'Client disconnected|segfault|core dumped|failed|error' | \
        tail -25 || true
fi

printf '\n=== Recent Frigate inference errors (diagnostic only) ===\n'
docker logs --since 15m "$container" 2>&1 | grep -Ei \
    'HAILO_NOT_FOUND|HAILO_SHUTDOWN|detect_raw|inference thread has stopped' | \
    tail -25 || true

if (( errors > 0 )); then
    printf 'FAIL: %d runtime check(s) failed\n' "$errors" >&2
    exit 1
fi
pass 'runtime checks passed (does not establish inference FPS)'
