# Publishing the HailoRT 4.24.0 MPS fork

This fork is based on [hailo-ai/hailort](https://github.com/hailo-ai/hailort)
`v4.24.0` and adds an MPS client-lifetime fix for clients using different
PID namespaces. It does **not** include a modified PCIe kernel driver; that
is maintained separately in
[hailort-drivers](https://github.com/hailo-ai/hailort-drivers/releases/tag/v4.24.0).
Keep upstream license and copyright notices. Confirm redistribution terms for
any firmware or binary packages before attaching them to a GitHub release.

## Release identity

`release/VERSION` is the fork's proposed release identifier. It must contain
`4.24.0-mps.N` (no initial `v`). The Git tag adds `v`, for example
`v4.24.0-mps.1`. The library ABI and installed version remain `4.24.0`.
Regenerate Markdown metadata with:

```bash
python3 scripts/sync-release-docs.py --sync
python3 scripts/sync-release-docs.py --check
python3 -m unittest discover -s tests -p 'test_sync_release_docs.py' -v
```

Do not confuse a proposed version file with a published or hardware-tested
release. The tag is created only after the final reviewed commit has passed
required CI checks.

## Fork workflow

1. Preserve `v4.24.0` as the upstream baseline. Do not modify its tag.
2. Review and stage intended MPS source, including the previously tested
   `hailort/cmake/external/grpc.cmake` compatibility change, documentation,
   tests, Git hooks, CI, metadata and safeguards. Review the gRPC diff and
   explain why it is necessary. Do not stage build products, logs, firmware
   or private paths.
3. Run `scripts/preflight-mps.sh --worktree`, existing regression checks,
   release metadata check and Gitleaks checks before a signed commit.
4. Initialize the fork's `main` branch *once* at the immutable upstream
   `v4.24.0` commit (not its current `master` branch, which targets newer
   devices). Set `main` as the default and protect it. This one-time branch
   initialization is the only exception to the no-direct-main-push rule.
5. Push only `feature/*` or `fix/*` branches containing our changes and
   open PRs targeting the fork's `main`, **not** upstream Hailo.
6. Require the `isolated` GitHub Actions check after verifying its exact job
   name from the first run. Build CI validates software, not Hailo hardware.
7. After merging through the PR, verify the merge commit and create a signed
   annotated tag matching `release/VERSION`; publish a GitHub source release.
8. Record the exact full Git commit SHA in downstream Frigate's source-fetch
   script so Frigate cannot silently switch to unpatched upstream source.

## Hardware and limitations

The observed hardware setup was Raspberry Pi 5 ARM64 with a full Hailo-8 and
Frigate 0.18.2. No AMD64 or Hailo-8L hardware inference validation is claimed.
The patch changes how service client resources expire when container PIDs do
not correspond to host PIDs. Cleanup can be deferred until the keepalive
interval expires. A separately observed native cleanup crash has not been
proven fixed, and the existing validation is not a long-duration soak test.

## Release gates

The release remains blocked if there are unreviewed findings from Gitleaks,
failed CI checks, unrelated changes, mismatched source revisions, unsigned
commits/tags, or uncertainty about licensing of redistributed binaries.

## One-time fork initialization

Create `pmelendez2/hailort` as a fork via `gh repo fork hailo-ai/hailort --clone=false`. Check `gh repo view` before proceeding. From the existing local checkout, configure the `fork` remote to reference the public `pmelendez2/hailort` repository. Verify the local `v4.24.0` tag matches upstream; create the *new* remote `main` from that tag using `git push fork refs/tags/v4.24.0:refs/heads/main` only when `refs/heads/main` does not exist. This is bootstrap of the baseline, not a release change. Set the fork default to `main` with `gh repo edit pmelendez2/hailort --default-branch main`. Afterward, no direct pushes to `main`; use branch/PR/CI/merge.

Before the first feature push, check CI tests against a clean source archive, not locally modified or ignored dependencies. The inclusion of `grpc.cmake` must be explicit in both the signed commit and release notes.
