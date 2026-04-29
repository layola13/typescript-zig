const std = @import("std");

/// Symbol accessibility result
pub const SymbolAccessibilityResult = struct {
    accessibility: SymbolAccessibility,
    error_symbol_name: ?[]const u8,
    error_node: ?*anyopaque,
};

/// Symbol accessibility
pub const SymbolAccessibility = enum {
    accessible,
    not_accessible,
    Cannot_be_instantiated,
};

/// Symbol tracker
pub const SymbolTracker = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolTracker {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SymbolTracker) void {
        _ = self;
    }
};

/// Track symbol accessibility
pub fn trackSymbolAccessibility(symbol: *anyopaque, tracker: *SymbolTracker) SymbolAccessibilityResult {
    _ = symbol;
    _ = tracker;
    return .{ .accessibility = .accessible };
}
