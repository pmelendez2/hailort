# HailoRT 4.24.0 — Container-safe Multi-Process Service

<!-- BEGIN GENERATED HAILORT RELEASE METADATA -->
**Fork release:** `v4.24.0-mps.1`
**Upstream HailoRT baseline:** `v4.24.0`
**HailoRT ABI/runtime:** `4.24.0`
**Modified component:** Host MPS client cleanup
**Hardware validation:** Raspberry Pi 5 ARM64, Hailo-8 only
**PCIe kernel driver:** Separate upstream `hailort-drivers` project
<!-- END GENERATED HAILORT RELEASE METADATA -->

This repository is a fork of [HailoRT](https://github.com/hailo-ai/hailort)
based on upstream `v4.24.0`. It develops and validates fixes to the
**host-side HailoRT Multi-Process Service (MPS)** for clients running in
containers, including Frigate 0.18.2.

> **Release status:** `v4.24.0-mps.1` is proposed, not yet published.
> The fork's `main` branch currently contains the unmodified upstream
> `v4.24.0` baseline. **Do not download `main` and expect these fixes
> until the feature PR has passed CI and been merged.** No downloadable
> prebuilt service package is promised.

## What this fork changes, and why

With MPS, a host-side `hailort_service` manages a Hailo accelerator for
multiple clients. A container can have a different PID namespace from the
host. Upstream v4.24.0 may treat a valid container PID as a nonexistent host
PID and remove a still-active client's resources.

This fork contains four related source changes:

1. **Container PID / keepalive handling:** use keepalive expiry instead
   of an incompatible host-local PID-existence check when disconnecting
   MPS clients.
2. **Device lifetime:** retain ownership of the parent `VDevice` while
   configured network groups depend on it; do not use host PID visibility
   to decide whether an owned resource can be released.
3. **DMA buffer-pool cleanup:** release buffer pools before network groups
   and their parent devices, including during configuration error cleanup.
4. **gRPC/CMake compatibility:** set
   `CMAKE_POLICY_VERSION_MINIMUM=3.5` for the external gRPC build.

These changes affect service cleanup and build compatibility. They do not
constitute a replacement Hailo PCIe kernel driver or firmware.

## Where the components run

| Component | Location | Responsibility |
| --- | --- | --- |
| Hailo-8 PCIe driver and matching firmware | Linux host | Access to the physical accelerator |
| Patched HailoRT 4.24.0 `hailort_service` | Linux host | MPS resource sharing and client management |
| HailoRT 4.24.0 client runtime | Application / container | RPC client communicating with host MPS |
| Frigate with MPS enabled | Container | Video detection using the Hailo-8 accelerator |

The host PCIe driver comes from the **separate**
[HailoRT Drivers repository](https://github.com/hailo-ai/hailort-drivers/releases/tag/v4.24.0).
This fork does **not** supply a patched PCIe driver. Install matching host
driver, firmware, runtime and MPS service components before expecting
hardware inference. The host MPS socket must be accessible to the container.
See the application's deployment documentation for its mount and detector
settings.

## Download the source

Project: https://github.com/pmelendez2/hailort

**After** the signed `v4.24.0-mps.1` tag is published, download the
reviewed source using the following commands. Do not substitute upstream
`v4.24.0` or the fork's unpatched baseline `main`.

```bash
git clone https://github.com/pmelendez2/hailort.git hailort-mps
cd hailort-mps
git fetch --tags
git checkout --detach v4.24.0-mps.1
git show -s --format='%H %D' HEAD
git tag -v v4.24.0-mps.1
cat release/VERSION
```

The signed tag must verify, and `release/VERSION` should report
`4.24.0-mps.1`. Check the GitHub release notes for the exact source
revision and published validation before using it.

**Until that tag exists:** development takes place on
`feature/mps-container-pid-keepalive`; that branch is not a stable
installation target.

## Build the patched host service

Use a supported Linux build environment with the compiler, CMake, Git,
Python 3, Gitleaks and the dependencies required by upstream HailoRT.
The project's local build wrapper runs the source/security preflight and
builds **only** `hailort_service`; it does not install a driver or service.

From the checked-out patched source:

```bash
python3 scripts/sync-release-docs.py --check
bash scripts/preflight-mps.sh --committed
bash scripts/build-mps.sh
```

For a successful native build, the expected executable is under:

```text
build/mps-<architecture>/hailort/hailort_service/hailort_service
```

The architecture name is determined by the build wrapper. Inspect the
actual output and linked runtime before installing anything:

```bash
find build -type f -name hailort_service -executable -print
file build/mps-*/hailort/hailort_service/hailort_service
ldd build/mps-*/hailort/hailort_service/hailort_service
```

ARM64 release builds run on native ARM64 GitHub Actions runners,
without emulation. For a native build on a Raspberry Pi 5, use
`MPS_BUILD_JOBS=4 bash scripts/build-mps.sh` after installing the
documented build dependencies. Building does not install the
service or exercise Hailo hardware.

## Install on the Hailo-8 host

**These installation steps are deliberately gated.** A successful build
does not verify driver compatibility or identify the active systemd unit's
executable path. Do not overwrite a running service based on an assumed
path.

1. Install and validate the appropriate Hailo-8 PCIe driver and firmware
   from the official drivers release linked above, using Hailo's
   kernel-specific instructions. Ensure host userspace components use
   compatible HailoRT 4.24.0 libraries.
2. Identify the *actual* service unit and executable using the commands
   below. Record the installed file's SHA-256 hash and retain a copy for
   rollback.
3. Confirm that the newly built binary is for the host architecture and
   resolves the intended `libhailort.so.4.24.0`, with no unresolved
   libraries. Review the host's service unit and follow the maintenance
   procedure for replacing **only** that service executable. Do not
   replace the PCIe driver, firmware, or runtime library as part of this
   service-only update.
4. Restart the existing service through the host's service-management
   procedure, confirm it becomes active, then verify its socket and run
   the read-only runtime check.

Read-only host inspection commands:

```bash
systemctl status hailort.service --no-pager
systemctl cat hailort.service
systemctl show hailort.service -p ExecStart -p MainPID
ldconfig -p | grep libhailort
hailortcli --version
```

After the approved service installation:

```bash
systemctl is-active hailort.service
bash scripts/test-mps-container-pid-namespace.sh --runtime
```

The read-only runtime check does not create inference traffic. An actual
inference workload must be tested separately, and failures must be
investigated without exposing camera names, logs or local network details.

For maintainers, see
[Build and CI](docs/MPS_BUILD_AND_CI.md),
[container PID namespaces](docs/MPS_CONTAINER_PID_NAMESPACE.md),
[hardware validation](docs/MPS_HARDWARE_VALIDATION.md), and
[release process](docs/MPS_RELEASE_PROCESS.md).

## Validation scope and limitations

The recorded hardware validation used **Raspberry Pi 5 ARM64 and a full
Hailo-8 accelerator** with Frigate 0.18.2. AMD64 hardware inference and
Hailo-8L are **not validated**. The latest device-lifetime and buffer-pool
source assertions pass, but those results do not establish a full hardware
soak test or prove that every associated native cleanup crash is fixed.

See [hardware validation](docs/MPS_HARDWARE_VALIDATION.md) for the
specific observations and limitations.

## Contributing and releases

All source changes use `feature/*` or `fix/*` branches, signed commits,
preflight and Gitleaks checks, a PR targeting protected `main`, and
required `isolated` CI before merge. Never push source changes directly
to `main`. A fork release is tagged and signed only after the approved
merge. The release identity comes from `release/VERSION`; generated
Markdown version metadata is managed by
`scripts/sync-release-docs.py`.

This fork retains the upstream HailoRT licenses and notices. Review any
separate firmware or binary redistribution restrictions before packaging
release assets.
