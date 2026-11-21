#!/usr/bin/env python3
"""Generate/check narrowly scoped HailoRT release metadata in fork docs."""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = (
    'README-MPS.md',
    'docs/MPS_BUILD_AND_CI.md',
    'docs/MPS_CONTAINER_PID_NAMESPACE.md',
    'docs/MPS_HARDWARE_VALIDATION.md',
)
START = '<!-- BEGIN GENERATED HAILORT RELEASE METADATA -->'
END = '<!-- END GENERATED HAILORT RELEASE METADATA -->'
PATTERN = re.compile(r'\Av?(4\.24\.0-mps\.[1-9][0-9]*)\Z')


def render(version):
    return '\n'.join((
        START,
        f'**Fork release:** `v{version}`',
        '**Upstream HailoRT baseline:** `v4.24.0`',
        '**HailoRT ABI/runtime:** `4.24.0`',
        '**Modified component:** Host MPS client cleanup',
        '**Hardware validation:** Raspberry Pi 5 ARM64, Hailo-8 only',
        '**PCIe kernel driver:** Separate upstream `hailort-drivers` project',
        END,
    ))


def transform(source, block, init):
    if source.count(START) != source.count(END):
        raise ValueError('unbalanced release markers')
    if source.count(START) > 1:
        raise ValueError('duplicate release markers')
    if START in source:
        opening = source.index(START)
        closing = source.index(END, opening) + len(END)
        return source[:opening] + block + source[closing:]
    if not init:
        raise ValueError('missing release markers; run --init once')
    match = re.search(r'^# .+\n', source, flags=re.MULTILINE)
    if not match:
        raise ValueError('document has no top-level Markdown heading')
    return source[:match.end()] + '\n' + block + '\n' + source[match.end():]


def main():
    ap = argparse.ArgumentParser()
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument('--init', action='store_true')
    group.add_argument('--sync', action='store_true')
    group.add_argument('--check', action='store_true')
    args = ap.parse_args()
    version_file = ROOT / 'release/VERSION'
    raw = version_file.read_text().strip()
    match = PATTERN.fullmatch(raw)
    if not match:
        ap.error('release/VERSION must match 4.24.0-mps.N')
    block = render(match.group(1))
    edits = []
    for filename in DOCS:
        path = ROOT / filename
        if not path.is_file():
            ap.error(f'missing expected document: {filename}')
        current = path.read_text()
        try:
            expected = transform(current, block, args.init)
        except ValueError as exc:
            ap.error(f'{filename}: {exc}')
        if args.check:
            if current != expected:
                ap.error(f'stale metadata: {filename}')
        elif current != expected:
            edits.append((path, expected))
    for path, output in edits:
        path.write_text(output)
        print(f'UPDATED: {path.relative_to(ROOT)}')
    print(f'PASS: {len(DOCS)} documents match v{match.group(1)}')


if __name__ == '__main__':
    main()
