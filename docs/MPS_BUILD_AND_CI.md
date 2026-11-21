# MPS fix: build, local hooks, and public review

<!-- BEGIN GENERATED HAILORT RELEASE METADATA -->
**Fork release:** `v4.24.0-mps.1`
**Upstream HailoRT baseline:** `v4.24.0`
**HailoRT ABI/runtime:** `4.24.0`
**Modified component:** Host MPS client cleanup
**Hardware validation:** Raspberry Pi 5 ARM64, Hailo-8 only
**PCIe kernel driver:** Separate upstream `hailort-drivers` project
<!-- END GENERATED HAILORT RELEASE METADATA -->

## Version and scope

This change targets the **Hailo-8/Hailo-8L HailoRT v4.24.0** source.
The v4.24.0 release tag is the baseline. Do not presume the current
`master` branch uses the same runtime ABI or supports the same devices.
The runtime validation used a Raspberry Pi 5, full Hailo-8 accelerator,
Ubuntu ARM64, HailoRT 4.24.0 (service/runtime/firmware), and Frigate
0.18.2 in Docker. See `MPS_HARDWARE_VALIDATION.md` for results.

## Native build architectures

All MPS builds use the host's native CPU architecture.

- AMD64 on sparta: eight build jobs by default.
- ARM64 on picam: four build jobs by default.
- GitHub Actions: native AMD64 and ARM64 runners.

The wrapper supports native, amd64, and arm64 arguments.
Explicit architecture selection must match the host.

The build directories are build/mps-amd64 and build/mps-arm64.
Separate caches prevent conflicts when source trees are shared.

CI checks compilation and source-level regressions. It does
not establish successful Hailo-8 hardware inference.

## CMake 4.2 compatibility

The AMD64 development host runs CMake 4.2.3. The existing HailoRT
v4.24.0 dependency graph includes vendored projects with older
`cmake_minimum_required()` policy versions, including c-ares. CMake 4.x
rejects policy minimums older than 3.5 unless an explicit compatibility
floor is set. The service-only build wrapper sets both
`CMAKE_POLICY_VERSION_MINIMUM=3.5` in the environment and
`-DCMAKE_POLICY_VERSION_MINIMUM:STRING=3.5` at top level.

The environment setting propagates to nested CMake processes invoked
while building protobuf and gRPC. This does not downgrade CMake or
modify vendored source. The GitHub Actions matrix installs CMake 4.2.3
on AMD64 and ARM64 to exercise the same configuration. Older upstream
code may still need separate changes if additional CMake 4.x-incompatible
commands are encountered.

Do not commit locally fetched dependency trees or build logs. Compiler
output can contain local paths and personal information.

## Local validation and build

From the repository root on sparta (AMD64):

    bash scripts/install-git-hooks.sh
    bash scripts/preflight-mps.sh --worktree
    MPS_BUILD_JOBS=8 bash scripts/build-mps.sh amd64

From the repository root on picam (ARM64):

    bash scripts/preflight-mps.sh --worktree
    MPS_BUILD_JOBS=4 bash scripts/build-mps.sh arm64

The required build tools and dependencies must be available
on the selected native host.

The build wrapper runs source preflight before CMake.
MPS_BUILD_JOBS overrides the architecture-specific job count.

For native builds, MPS_BUILD_DIR overrides the default
build/mps-<arch> directory.

Building does not install a service, change the HailoRT driver,
update firmware, or replace a running runtime.

Local hooks check staged content before commits and feature
commits before pushes. Gitleaks checks the feature range
after the upstream v4.24.0 baseline.

The optional runtime inspection is read-only:

    bash scripts/test-mps-container-pid-namespace.sh --runtime

Run it only where Frigate and HailoRT are available. It reports
error signatures without generating inference traffic.

## CI

`.github/workflows/mps-isolated.yml` defines an `isolated` GitHub Actions
matrix with independent AMD64 and ARM64 jobs. It installs Gitleaks, runs preflight,
then builds the service. It is a CI definition, **not** proof that GitHub
Actions has passed; check the actual workflow result before requesting
branch protection. Configure both `isolated (amd64)` and `isolated (arm64)` as required
checks on the fork's protected default branch after the first successful run.

Build dependencies are fetched by HailoRT CMake configuration; CI must
have network access to those public dependencies. Validation does not
require Hailo hardware in CI. Actual inference validation remains a
separate manual hardware test.

## Publication and privacy

Only stage reviewed MPS source, docs, tests, workflow, hooks, and
`.gitignore`. Do not stage build products, native core files, logs,
local CMake overrides, or binary artifacts. Review `git diff --cached`,
run Gitleaks and the privacy check, and use signed commits.

Publish to a fork, not to `hailo-ai/hailort`. The upstream issue content
is in `MPS_UPSTREAM_ISSUE.md`. HailoAI may restrict issue creation; an
upstream pull request is an alternative, subject to maintainer review.

## Known limitations

- Source regression checks identify the changed cleanup decision;
  they do not simulate cross-namespace RPC scheduling.
- Keepalive-timeout-only reclamation can delay cleanup of dead clients.
- The separate native cleanup crash is not proven fixed.
- Real hardware results are a single-session validation, not a soak test.

## Native ARM64 verification

Build on picam or on a native ARM64 GitHub Actions runner.

On picam, use:

    MPS_BUILD_JOBS=4 bash scripts/build-mps.sh arm64

Inspect the executable and dynamic dependencies:

    file build/mps-arm64/hailort/hailort_service/hailort_service
    ldd build/mps-arm64/hailort/hailort_service/hailort_service

These commands do not install or launch the service.
Hardware testing is a separate, controlled procedure.

## Native-only build policy

MPS service compilation uses native CPU architectures, not QEMU.
GitHub Actions uses `ubuntu-24.04` for AMD64 and
`ubuntu-24.04-arm` for ARM64. CI verifies the actual CPU
architecture before starting compilation.

Set `MPS_BUILD_JOBS` to control native CMake parallelism:

```bash
MPS_BUILD_JOBS=8 bash scripts/build-mps.sh
```

Use four jobs on Raspberry Pi 5 ARM64 unless measurements
show that higher parallelism is sustainable. CI uses eight
jobs for AMD64 and four for ARM64. The source tests and
native CI builds do not replace hardware inference tests.
