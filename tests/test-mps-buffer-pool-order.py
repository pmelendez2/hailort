#!/usr/bin/env python3
"""Verify HailoRT 4.24.0 MPS release dependencies in source."""
from pathlib import Path
import re
import sys

p = Path('hailort/hailort_service/hailort_rpc_service.cpp')
if not p.is_file():
    sys.exit('FAIL: execute at repository root')
s = p.read_text()

def function_between(start: str, end: str) -> str:
    a = s.find(start)
    b = s.find(end, a + len(start))
    if a < 0 or b < 0:
        sys.exit(f'FAIL: missing function boundaries: {start} / {end}')
    return s[a:b]

cleanup = function_between('void HailoRtRpcService::remove_disconnected_clients()',
                           'void HailoRtRpcService::keep_alive()')
expected = [
    'ServiceResourceManager<OutputVStream>',
    'ServiceResourceManager<InputVStream>',
    'ServiceResourceManager<ServiceNetworkGroupBufferPool>',
    'ServiceResourceManager<ConfiguredNetworkGroup>',
    'ServiceResourceManager<VDeviceCallbacksQueue>',
    'ServiceResourceManager<VDevice>',
]
positions = [cleanup.find(name + '::get_instance().release_by_id(client_pid)') for name in expected]
assert all(i >= 0 for i in positions) and positions == sorted(positions), positions
print('PASS: client-disconnect DMA pool precedes group and VDevice')

error = function_between('void HailoRtRpcService::release_resources_on_error(',
                         'grpc::Status HailoRtRpcService::VDevice_configure(')
assert 'buffer_pool_manager.release_resource(buffer_pool_handle, pid)' in error
assert 'networks_manager.release_resource(buffer_pool_handle, pid)' not in error
assert error.index('buffer_pool_manager.release_resource(buffer_pool_handle, pid)') < error.index('networks_manager.release_resource(current_ng_handle, pid)')
print('PASS: configure error cleanup uses correct manager and release order')

release = function_between('grpc::Status HailoRtRpcService::ConfiguredNetworkGroup_release(',
                           'hailo_status HailoRtRpcService::add_input_named_buffer(')
assert release.index('buffer_pool_manager.release_resource(') < release.index('\n    manager.release_resource(')
print('PASS: explicit RPC release frees pool before network group')

assert 'std::shared_ptr<VDevice> parent_vdevice;' in s
assert 'parent_vdevice.reset();' in s
print('PASS: prerequisite device-lifetime patch present')
print('PASS: static cleanup checks (hardware NOT tested)')
