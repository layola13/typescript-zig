const std = @import("std");
const sys = @import("sys.zig");

/// Run the API server
pub fn run(args: []const []const u8, system: *sys.System) !u8 {
    // Parse flags
    var cwd: ?[]const u8 = null;
    var pipe_path: ?[]const u8 = null;
    var callbacks: ?[]const u8 = null;
    var async_mode = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--cwd") and i + 1 < args.len) {
            i += 1;
            cwd = args[i];
        } else if (std.mem.eql(u8, arg, "--pipe") and i + 1 < args.len) {
            i += 1;
            pipe_path = args[i];
        } else if (std.mem.eql(u8, arg, "--callbacks") and i + 1 < args.len) {
            i += 1;
            callbacks = args[i];
        } else if (std.mem.eql(u8, arg, "--async")) {
            async_mode = true;
        }
    }

    // Default cwd to system cwd if not specified
    const working_dir = cwd orelse system.cwd;

    // Parse callbacks list
    var callbacks_list = std.ArrayList([]const u8).init(system.allocator);
    defer callbacks_list.deinit();
    if (callbacks) |cb| {
        var it = std.mem.splitSequence(u8, cb, ",");
        while (it.next()) |item| {
            try callbacks_list.append(item);
        }
    }

    if (pipe_path) |pipe| {
        try std.err.print("API server using pipe: {s}\n", .{pipe});
        // TODO: Implement named pipe communication
        _ = async_mode;
        _ = working_dir;
        return 0;
    }

    // Use stdio for communication
    return runStdio(system, async_mode, working_dir, &callbacks_list);
}

fn runStdio(
    system: *sys.System,
    async_mode: bool,
    cwd: []const u8,
    callbacks: *const std.ArrayList([]const u8),
) !u8 {
    const reader = system.fsReader();
    const writer = system.fsWriter();

    if (async_mode) {
        try writer.print("API server ready (async/JSON-RPC mode)\n", .{});
    } else {
        try writer.print("API server ready (MessagePack mode)\n", .{});
    }

    _ = cwd;
    _ = callbacks;
    _ = reader;

    // TODO: Implement full API protocol
    return 0;
}
