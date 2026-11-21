#!/usr/bin/env python3
"""Apply focused HailoRT 4.24.0 MPS buffer-pool cleanup corrections.

Only changes two source locations; refuses unexpected source and never
modifies a file if source matches are ambiguous.
"""
from pathlib import Path
import sys

source = Path('hailort/hailort_service/hailort_rpc_service.cpp')
if not source.is_file():
    sys.exit(f'FAIL: source missing: {source}; run at repository root')

original = source.read_text()

old_cleanup = '''            ServiceResourceManager<ConfiguredNetworkGroup>::get_instance().release_by_id(client_pid);
            ServiceResourceManager<VDeviceCallbacksQueue>::get_instance().release_by_id(client_pid);
            ServiceResourceManager<ServiceNetworkGroupBufferPool>::get_instance().release_by_id(client_pid);
            ServiceResourceManager<VDevice>::get_instance().release_by_id(client_pid);'''
new_cleanup = '''            // DMA buffers must unmap while their network group still retains
            // the parent VDevice. Release buffer pools before network groups.
            ServiceResourceManager<ServiceNetworkGroupBufferPool>::get_instance().release_by_id(client_pid);
            ServiceResourceManager<ConfiguredNetworkGroup>::get_instance().release_by_id(client_pid);
            ServiceResourceManager<VDeviceCallbacksQueue>::get_instance().release_by_id(client_pid);
            ServiceResourceManager<VDevice>::get_instance().release_by_id(client_pid);'''

old_error = '''void HailoRtRpcService::release_resources_on_error(std::vector<uint32_t> ng_handles, std::vector<uint32_t> buffer_pool_handles, uint32_t pid)
{
    auto &networks_manager = ServiceResourceManager<ConfiguredNetworkGroup>::get_instance();
    for (auto &current_ng_handle : ng_handles) {
        networks_manager.release_resource(current_ng_handle, pid);
    }
    for (auto &buffer_pool_handle : buffer_pool_handles) {
        auto status = shutdown_cng_buffer_pool(buffer_pool_handle);
        if (status != HAILO_SUCCESS) {
            LOGGER__ERROR("Failed to shutdown cng buffer pool with handle={}, status={}", buffer_pool_handle, status);
        }
        networks_manager.release_resource(buffer_pool_handle, pid);
    }
}'''
new_error = '''void HailoRtRpcService::release_resources_on_error(std::vector<uint32_t> ng_handles, std::vector<uint32_t> buffer_pool_handles, uint32_t pid)
{
    auto &buffer_pool_manager = ServiceResourceManager<ServiceNetworkGroupBufferPool>::get_instance();
    for (auto &buffer_pool_handle : buffer_pool_handles) {
        auto status = shutdown_cng_buffer_pool(buffer_pool_handle);
        if (status != HAILO_SUCCESS) {
            LOGGER__ERROR("Failed to shutdown cng buffer pool with handle={}, status={}", buffer_pool_handle, status);
        }
        buffer_pool_manager.release_resource(buffer_pool_handle, pid);
    }

    // The configured groups keep their parent VDevices alive until all DMA
    // buffers held by their associated pools have been unmapped.
    auto &networks_manager = ServiceResourceManager<ConfiguredNetworkGroup>::get_instance();
    for (auto &current_ng_handle : ng_handles) {
        networks_manager.release_resource(current_ng_handle, pid);
    }
}'''

updated = original
for title, old, new in (
    ('disconnect cleanup', old_cleanup, new_cleanup),
    ('configure error cleanup', old_error, new_error),
):
    if updated.count(new) == 1:
        print(f'PASS: {title} already updated')
        continue
    count = updated.count(old)
    if count != 1:
        sys.exit(f'FAIL: expected one {title} block, found {count}; no source changed')
    updated = updated.replace(old, new, 1)
    print(f'PASS: {title} prepared')

if updated != original:
    source.write_text(updated)
    print(f'PASS: updated {source}')
else:
    print('PASS: source already up to date')
