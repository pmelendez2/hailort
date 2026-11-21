#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
if [[ -n "$(git config --local --get core.hooksPath || true)" &&
      "$(git config --local --get core.hooksPath)" != .githooks ]]; then
    echo 'FAIL: repository already has another hooksPath; review it first' >&2
    exit 1
fi
if [[ -e .git/hooks/pre-commit && ! -L .git/hooks/pre-commit ]]; then
    echo 'NOTE: existing .git/hooks/pre-commit is overridden by hooksPath' >&2
fi
for hook in pre-commit pre-push; do
    [[ -x ".githooks/$hook" ]] || {
        echo "FAIL: .githooks/$hook is not executable" >&2
        exit 1
    }
done
git config --local core.hooksPath .githooks
printf 'PASS: hooksPath=%s\n' "$(git config --local core.hooksPath)"
