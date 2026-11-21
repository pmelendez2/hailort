#!/usr/bin/env python3
"""Inspect files being published, not generated files or source history.

Exit nonzero for likely personal identifiers. This is intentionally strict for
new documentation/scripts; review findings rather than weakening rules.
"""
import argparse
import pathlib
import re
import subprocess
import sys

PATTERNS = {
    "personal home directory": r"/(?:home|Users)/[A-Za-z0-9._-]+/",
    "private network address":
        r"\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|"
        r"172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b",
    "internal DNS name": r"\b[A-Za-z0-9_.-]+\.(?:home\.arpa|localdomain)\b",
    "credential prefix": r"\b(?:gh" + r"[pousr]_" + r"|github_" + r"pat_|sk-" + r"[A-Za-z0-9]{12})",
    "SSH private key": r"BEGIN (?:OPENSSH|RSA|EC|DSA) PRIVATE KEY",
    "email address": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b",
    "hardware MAC": r"\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b",
}
COMPILED = {k: re.compile(v, re.I) for k, v in PATTERNS.items()}

def git(*args):
    return subprocess.check_output(["git", *args])

def paths(mode):
    if mode == "staged":
        raw = git("diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR")
    elif mode == "committed":
        raw = git("diff-tree", "--no-commit-id", "--name-only", "-r", "-z", "HEAD")
    else:
        raw = b"\0".join(str(p).encode() for p in (
            pathlib.Path('docs/MPS_CONTAINER_PID_NAMESPACE.md'),
            pathlib.Path('docs/MPS_HARDWARE_VALIDATION.md'),
            pathlib.Path('docs/MPS_UPSTREAM_ISSUE.md'),
            pathlib.Path('docs/MPS_BUILD_AND_CI.md'),
            pathlib.Path('.github/workflows/mps-isolated.yml'),
            pathlib.Path('.githooks/pre-commit'),
            pathlib.Path('.githooks/pre-push'),
            *pathlib.Path('scripts').glob('*'),
        ) if p.is_file())
    return [p.decode() for p in raw.split(b"\0") if p]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=('staged', 'committed', 'worktree'),
                        default='worktree')
    args = parser.parse_args()
    hits = []
    for path in paths(args.mode):
        try:
            if args.mode == 'staged':
                data = git('show', ':' + path)
            elif args.mode == 'committed':
                data = git('show', 'HEAD:' + path)
            else:
                data = pathlib.Path(path).read_bytes()
        except (subprocess.CalledProcessError, OSError):
            print('FAIL: cannot read ' + path, file=sys.stderr)
            return 1
        if b'\0' in data:
            hits.append((path, 'binary file not allowed in submission'))
            continue
        for name, pattern in COMPILED.items():
            if pattern.search(data.decode('utf-8', errors='replace')):
                hits.append((path, name))
    for path, category in hits:
        print(f'REVIEW: {path}: {category}', file=sys.stderr)
    if hits:
        return 1
    print(f'PASS: public-content privacy scan ({args.mode})')
    return 0

if __name__ == '__main__':
    sys.exit(main())
