const std = @import("std");

/// Export info
pub const ExportInfo = struct {
    name: []const u8,
    symbol: *anyopaque,
    target: *anyopaque,
};

/// Export resolution
pub const ExportResolution = struct {
    exports: []ExportInfo,
    duplicated: bool,
};

/// Resolve exports
pub fn resolveExports(symbol: *anyopaque) ?ExportResolution {
    _ = symbol;
    return null;
}

/// Export checker
pub const ExportChecker = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ExportChecker {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ExportChecker) void {
        _ = self;
    }
};
