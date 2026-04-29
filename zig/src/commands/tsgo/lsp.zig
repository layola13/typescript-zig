const std = @import("std");
const sys = @import("sys.zig");

/// Run the LSP server
pub fn run(args: []const []const u8, system: *sys.System) !u8 {
    // Parse flags
    var stdio = false;
    var pprof_dir: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--stdio")) {
            stdio = true;
        } else if (std.mem.eql(u8, arg, "-pprofDir") and i + 1 < args.len) {
            i += 1;
            pprof_dir = args[i];
        }
    }

    if (!stdio) {
        try std.err.print("only stdio is supported\n", .{});
        return 1;
    }

    if (pprof_dir) |dir| {
        try std.err.print("pprof profiles will be written to: {s}\n", .{dir});
        // TODO: Implement profiling
    }

    // Create LSP server options
    const server = try LspServer.init(system);
    defer server.deinit();

    // Run the server until shutdown
    try server.run();

    return 0;
}

const LspServer = struct {
    system: *sys.System,

    fn init(system: *sys.System) !LspServer {
        return LspServer{ .system = system };
    }

    fn deinit(self: *LspServer) void {
        _ = self;
    }

    fn run(self: *LspServer) !void {
        const reader = self.system.fsReader();
        const writer = self.system.fsWriter();

        // TODO: Implement full LSP protocol handling
        try writer.print("LSP server ready (stdio mode)\n", .{});
        _ = reader;
    }
};
