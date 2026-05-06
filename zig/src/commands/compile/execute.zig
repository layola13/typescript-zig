const std = @import("std");
const cli_help = @import("../../cli/help.zig");
const version_info = @import("../../version.zig");
const types = @import("./types.zig");
const config = @import("./config.zig");

pub fn execute(request: *const types.CompileRequest) types.CompileResult {
    var result = types.CompileResult.init(.compile);
    
    // Set default values
    result.native_failed = false;
    result.project_path = request.project_path;
    result.entry_file_count = request.entry_files.items.len;
    result.forwarded_arg_count = request.passthrough.items.len;
    
    // Resolve config path
    const resolved_config_path = if (request.flags.ignore_config) null else blk: {
        if (request.tsconfig_path) |p| {
            result.config_resolution = .explicit_project;
            break :blk p;
        }
        if (request.project_path) |proj| {
            if (config.resolveProjectPath(std.heap.page_allocator, proj)) |p| {
                result.config_resolution = .found;
                break :blk p;
            }
        }
        result.config_resolution = .none;
        break :blk null;
    };
    result.resolved_config_path = resolved_config_path;
    
    return result;
}
