#!/usr/bin/env bash
# Native AMD64/ARM64 build; enforce source preflight.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
"$root/scripts/preflight-mps.sh" --worktree
mode="${1:-native}"
if (( $# > 1 )); then
    echo 'Usage: scripts/build-mps.sh [native|amd64|arm64]' >&2
    exit 2
fi

host="$(uname -m)"
case "$mode" in
    native)
        ;;
    amd64)
        if [[ "$host" != x86_64 && "$host" != amd64 ]]; then
            echo 'FAIL: amd64 requires a native AMD64 host' >&2
            exit 1
        fi
        ;;
    arm64)
        if [[ "$host" != aarch64 && "$host" != arm64 ]]; then
            echo 'FAIL: arm64 requires a native ARM64 host' >&2
            exit 1
        fi
        ;;
    *)
        echo 'Usage: scripts/build-mps.sh [native|amd64|arm64]' >&2
        exit 2
        ;;
esac

case "$host" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "FAIL: unsupported build architecture: $(uname -m)" >&2; exit 1 ;;
esac
# Separate CMake caches are essential for shared NFS source trees.
build_dir="${MPS_BUILD_DIR:-$root/build/mps-$arch}"
if [[ -f "$build_dir/CMakeCache.txt" ]]; then
    cached_arch="$(sed -n 's/^MPS_NATIVE_ARCH:STRING=//p' \
        "$build_dir/CMakeCache.txt")"
    if [[ -n "$cached_arch" && "$cached_arch" != "$arch" ]]; then
        echo "FAIL: build directory was configured for $cached_arch" >&2
        exit 1
    fi
fi
# CMake 4.2 rejects legacy dependencies requesting policies below 3.5.
# HailoRT invokes nested CMake processes for bundled protobuf and gRPC.
# Export the variable so those subprocesses inherit the compatibility floor.
export CMAKE_POLICY_VERSION_MINIMUM=3.5
printf 'CMake: %s\n' "$(cmake --version | head -n 1)"
printf 'CMake policy version minimum: %s\n' \
    "$CMAKE_POLICY_VERSION_MINIMUM"
cmake -S "$root" -B "$build_dir" \
    -DCMAKE_POLICY_VERSION_MINIMUM:STRING=3.5 \
    -DCMAKE_BUILD_TYPE=Release \
    -DHAILO_BUILD_SERVICE=ON \
    -DHAILO_BUILD_EXAMPLES=OFF \
    -DHAILO_BUILD_UT=OFF \
    -DMPS_NATIVE_ARCH:STRING="$arch"
default_jobs=8
if [[ "$arch" == arm64 ]]; then
    default_jobs=4
fi
jobs="${MPS_BUILD_JOBS:-$default_jobs}"
if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    echo "FAIL: MPS_BUILD_JOBS must be a positive integer" >&2
    exit 2
fi
echo "Native MPS build: architecture=$arch jobs=$jobs"
cmake --build "$build_dir" --target hailort_service --parallel "$jobs"
binary="$build_dir/hailort/hailort_service/hailort_service"
test -x "$binary" || { echo 'FAIL: service executable missing' >&2; exit 1; }
file "$binary"
printf 'PASS: native %s service build: %s\n' "$arch" "$binary"
