const std = @import("std");

pub const Command = enum {
    help,
    version,
    compile,
    lsp,
    api,
};

pub const CompileMode = enum {
    normal,
    build,
    watch,
};

pub const ParsedArgs = struct {
    command: Command,
    compile_mode: CompileMode = .normal,
    passthrough: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) ParsedArgs {
        return .{
            .command = .help,
            .compile_mode = .normal,
            .passthrough = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ParsedArgs) void {
        self.passthrough.deinit();
    }
};
