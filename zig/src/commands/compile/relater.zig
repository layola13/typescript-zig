const std = @import("std");

/// Relater flags
pub const RelaterFlags = struct {
    exact: bool = false,
    broad: bool = false,
};

/// Relation result
pub const RelationResult = struct {
    related: bool,
    unrelated_reason: ?[]const u8,
};

/// Symbol relater
pub const SymbolRelater = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolRelater {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SymbolRelater) void {
        _ = self;
    }

    /// Check if two symbols are related
    pub fn areRelated(self: *const SymbolRelater, a: *anyopaque, b: *anyopaque, flags: RelaterFlags) RelationResult {
        _ = self;
        _ = a;
        _ = b;
        _ = flags;
        return .{ .related = false };
    }
};
