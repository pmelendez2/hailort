#!/usr/bin/env bash
# Append protective rules without replacing existing upstream ignore rules.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
touch .gitignore
entries=(
    '/build/'
    '/cmake-build-*/'
    '/hailort.log'
    '*.core'
    'core.*'
    '*.orig'
    '*.swp'
    '*.swo'
    '__pycache__/'
    '.venv/'
    '*.whl'
    '*.deb'
    '*.zip'
)
for entry in "${entries[@]}"; do
    if ! grep -Fxq "$entry" .gitignore; then
        printf '%s\n' "$entry" >> .gitignore
    fi
done
printf 'PASS: reviewed ignore patterns present\n'
