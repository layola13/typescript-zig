const std = @import("std");

/// Abstract Syntax Tree transformation utilities
pub const Transformer = struct {
    allocator: std.mem.Allocator,

    pub fn transform(self: *Transformer, node: []const u8) ![]const u8 {
        _ = self;
        return try self.allocator.dupe(u8, node);
    }

    pub fn destroy(self: *Transformer) void {
        self.allocator.destroy(self);
    }
};
