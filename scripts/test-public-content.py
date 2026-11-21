#!/usr/bin/env python3
"""Unit-test privacy pattern matching without including real credentials."""
import importlib.util
import pathlib

path = pathlib.Path(__file__).with_name('check-public-content.py')
spec = importlib.util.spec_from_file_location('privacy_guard', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
checks = [
    ('home', '/' + 'home' + '/somebody/source', 'personal home directory'),
    ('private ipv4', '192' + '.168.4.7', 'private network address'),
    ('domain', 'myhost.' + 'home.arpa', 'internal DNS name'),
    ('email', 'someone' + '@example.com', 'email address'),
]
for label, sample, category in checks:
    assert module.COMPILED[category].search(sample), label
assert not any(p.search('HailoRT v4.24.0 MPS')
               for p in module.COMPILED.values())
print('PASS: privacy scanner unit tests')
