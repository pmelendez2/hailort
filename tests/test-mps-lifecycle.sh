#!/usr/bin/env bash
# Controlled Frigate stop/start hardware regression on picam.
# Never starts or stops Frigate using docker; uses sacntr_mgr exclusively.
# HailoRT must remain running with the same PID and restart counter.
set -uo pipefail

service="${HAILORT_SERVICE:-hailort.service}"
container="${FRIGATE_CONTAINER:-frigate}"
stop_hold="${MPS_STOP_HOLD_SECONDS:-150}"
health_timeout="${MPS_HEALTH_TIMEOUT_SECONDS:-180}"

usage() {
    cat <<'USAGE'
Usage: bash tests/test-mps-lifecycle.sh --run

Actions: validate initial healthy Frigate, stop with sacntr_mgr,
observe HailoRT for MPS_STOP_HOLD_SECONDS (default 150), restart with
sacntr_mgr, and wait up to MPS_HEALTH_TIMEOUT_SECONDS (default 180)
for healthy Frigate. HailoRT PID and NRestarts must remain unchanged.

This test intentionally interrupts Frigate. It does not stop HailoRT.
The test attempts to restart Frigate if interrupted or if a check fails.
USAGE
}
if [[ "${1:-}" != --run || $# -ne 1 ]]; then
    usage
    exit 2
fi
if [[ ! "$stop_hold" =~ ^[0-9]+$ || "$stop_hold" == 0 ||
      ! "$health_timeout" =~ ^[0-9]+$ || "$health_timeout" == 0 ]]; then
    echo 'FAIL: timeouts must be positive whole seconds' >&2
    exit 2
fi
for command in sacntr_mgr docker systemctl journalctl date sleep; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "FAIL: required command missing: $command" >&2
        exit 1
    }
done

state() {
    docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null
}
health() {
    docker inspect --format \
        '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "$container" 2>/dev/null
}
service_field() {
    systemctl show "$service" -p "$1" --value
}

ensure_service_unchanged() {
    local phase="$1" current_pid current_restarts active
    active="$(service_field ActiveState)"
    current_pid="$(service_field MainPID)"
    current_restarts="$(service_field NRestarts)"
    printf 'HailoRT (%s): State=%s PID=%s NRestarts=%s\n' \
        "$phase" "$active" "$current_pid" "$current_restarts"
    if [[ "$active" != active || "$current_pid" != "$baseline_pid" ||
          "$current_restarts" != "$baseline_restarts" ]]; then
        echo "FAIL: HailoRT changed during $phase" >&2
        return 1
    fi
}

frigate_stopped=0
restore_frigate() {
    local rc=$?
    trap - EXIT INT TERM
    if (( frigate_stopped )); then
        echo '=== Recovery: attempt to start Frigate ===' >&2
        sacntr_mgr -u frigate >&2 || {
            echo 'FAIL: automatic Frigate recovery failed' >&2
            rc=1
        }
    fi
    exit "$rc"
}
trap restore_frigate EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '=== Initial checks ===\n'
if [[ "$(state)" != running || "$(health)" != healthy ]]; then
    echo 'FAIL: Frigate must be running and healthy before test' >&2
    exit 1
fi
baseline_pid="$(service_field MainPID)"
baseline_restarts="$(service_field NRestarts)"
if [[ "$(service_field ActiveState)" != active ||
      ! "$baseline_pid" =~ ^[0-9]+$ || "$baseline_pid" == 0 ]]; then
    echo 'FAIL: HailoRT must be active before test' >&2
    exit 1
fi
printf 'Baseline: PID=%s NRestarts=%s\n' \
    "$baseline_pid" "$baseline_restarts"
start_stamp="$(date '+%Y-%m-%d %H:%M:%S')"

printf '\n=== Stop Frigate using sacntr_mgr ===\n'
frigate_stopped=1
if ! sacntr_mgr -s frigate; then
    echo 'FAIL: Frigate stop failed' >&2
    exit 1
fi
if [[ "$(state)" != exited ]]; then
    echo 'FAIL: expected Frigate state=exited after stop' >&2
    exit 1
fi
ensure_service_unchanged 'immediately after stop' || exit 1

printf '\n=== Observe disconnected-client cleanup (%s seconds) ===\n' \
    "$stop_hold"
end_time=$((SECONDS + stop_hold))
while (( SECONDS < end_time )); do
    remaining=$((end_time - SECONDS))
    if (( remaining >= 5 )); then
        sleep 5
    else
        sleep "$remaining"
    fi
    ensure_service_unchanged 'Frigate stopped' || exit 1
done

printf '\n=== HailoRT cleanup observations ===\n'
journal="$(journalctl -u "$service" --since "$start_stamp" \
    --no-pager 2>&1)" || {
    echo 'FAIL: cannot read HailoRT journal' >&2
    exit 1
}
if grep -Eiq 'segfault|core dumped|Main process exited.*SEGV' \
    <<<"$journal"; then
    echo 'FAIL: HailoRT crash signature found in journal' >&2
    exit 1
fi
if grep -Eiq 'Client disconnected' <<<"$journal"; then
    echo 'PASS: disconnected-client cleanup observed'
else
    echo 'NOTE: no disconnected-client cleanup event observed'
    echo 'NOTE: this cycle verifies stability, not the cleanup code path'
fi

printf '\n=== Restart Frigate using sacntr_mgr ===\n'
if ! sacntr_mgr -u frigate; then
    echo 'FAIL: Frigate start failed' >&2
    exit 1
fi
frigate_stopped=0

printf '\n=== Wait for Frigate health ===\n'
end_time=$((SECONDS + health_timeout))
while true; do
    current_state="$(state)"
    current_health="$(health)"
    printf 'Frigate: State=%s Health=%s\n' \
        "${current_state:-unknown}" "${current_health:-unknown}"
    ensure_service_unchanged 'Frigate restarting' || exit 1
    if [[ "$current_state" == running && "$current_health" == healthy ]]; then
        break
    fi
    if (( SECONDS >= end_time )); then
        echo 'FAIL: Frigate did not become healthy before timeout' >&2
        exit 1
    fi
    sleep 5
done

printf '\n=== Final checks ===\n'
ensure_service_unchanged 'final' || exit 1
journal="$(journalctl -u "$service" --since "$start_stamp" \
    --no-pager 2>&1)" || exit 1
if grep -Eiq 'segfault|core dumped|Main process exited.*SEGV' \
    <<<"$journal"; then
    echo 'FAIL: HailoRT crash signature found in journal' >&2
    exit 1
fi
printf 'PASS: lifecycle test passed (Frigate healthy, HailoRT stable)\n'
echo 'NOTE: health status alone does not prove inference FPS'
