#!/usr/bin/env python3
"""Read-only source regression for the service-side lifetime fix."""
from pathlib import Path

path = Path("hailort/hailort_service/hailort_rpc_service.cpp")
src = path.read_text()
checks = {
    "parent shared ownership": "std::shared_ptr<VDevice> parent_vdevice;",
    "capture parent from manager": "parent_vdevice = vdevice;",
    "group with strong parent lifetime": "[network, parent_vdevice](ConfiguredNetworkGroup *) mutable",
    "shutdown before releasing parent": "auto status = network->shutdown();",
    "release group before parent": "network.reset();\n                parent_vdevice.reset();",
    "register owned group": "register_resource(request->pid(), owned_network)",
}
failed = False
for label, expected in checks.items():
    ok = expected in src
    print(("PASS" if ok else "FAIL") + ": " + label)
    failed |= not ok
if failed:
    raise SystemExit(1)
print("PASS: source ownership assertions (hardware NOT tested)")
