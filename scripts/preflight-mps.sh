#!/usr/bin/env bash
# Scan only staged changes and commits after the v4.24.0 feature base.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
mode="${1:---worktree}"
base="${MPS_BASE_REF:-v4.24.0}"

command -v gitleaks >/dev/null || {
    echo 'FAIL: Gitleaks v8 is required' >&2
    exit 1
}

# Validate GitHub Actions expressions before commit or publication.
# Go-installed tools may not yet be on the interactive shell's PATH.
actionlint_bin="$(command -v actionlint || true)"

if [[ -z "$actionlint_bin" ]] && command -v go >/dev/null; then
    go_bin="$(go env GOBIN)"
    if [[ -z "$go_bin" ]]; then
        go_bin="$(go env GOPATH)/bin"
    fi
    if [[ -x "$go_bin/actionlint" ]]; then
        actionlint_bin="$go_bin/actionlint"
    fi
fi

if [[ -z "$actionlint_bin" ]]; then
    echo 'FAIL: actionlint v1.7.12 is required' >&2
    exit 1
fi

"$actionlint_bin" .github/workflows/mps-isolated.yml
echo 'PASS: GitHub Actions workflow lint'

scan_feature_commits() {
    git rev-parse --verify "${base}^{commit}" >/dev/null || {
        echo "FAIL: feature base $base not found" >&2
        exit 1
    }
    git merge-base --is-ancestor "$base" HEAD || {
        echo "FAIL: $base is not an ancestor of HEAD" >&2
        exit 1
    }
    git diff "$base"..HEAD --check
    if [[ "$(git rev-parse "$base")" != "$(git rev-parse HEAD)" ]]; then
        # Explicit range excludes every commit at or before v4.24.0.
        gitleaks git --redact --no-banner \
            --log-opts="$base..HEAD" .
    else
        echo 'PASS: no feature commits to scan yet'
    fi
}

case "$mode" in
    --staged)
        git diff --cached --check
        python3 scripts/check-public-content.py --mode staged
        gitleaks git --staged --redact --no-banner .
        ;;
    --committed)
        python3 scripts/check-public-content.py --mode committed
        scan_feature_commits
        ;;
    --worktree)
        git diff --check
        python3 scripts/check-public-content.py --mode worktree
        # Scan staged changes and feature commits, never upstream history,
        # generated binaries, dependency caches, or local untracked logs.
        gitleaks git --staged --redact --no-banner .
        scan_feature_commits
        ;;
    *)
        echo "Usage: $0 [--staged|--committed|--worktree]" >&2
        exit 2
        ;;
esac

bash -n .githooks/pre-commit .githooks/pre-push \
    scripts/install-git-hooks.sh scripts/preflight-mps.sh \
    scripts/build-mps.sh scripts/test-mps-container-pid-namespace.sh
python3 scripts/test-public-content.py
python3 scripts/sync-release-docs.py --check
python3 -m unittest discover \
    -s tests -p 'test_sync_release_docs.py' -v
python3 tests/test-mps-device-lifetime.py
python3 tests/test-mps-buffer-pool-order.py
bash scripts/test-mps-container-pid-namespace.sh
printf 'PASS: MPS preflight (%s, base=%s)\n' "$mode" "$base"
