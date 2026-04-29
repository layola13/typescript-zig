const std = @import("std");

/// Async iterator interface
pub const AsyncIterator = struct {
    allocator: std.mem.Allocator,
    done: bool = false,

    pub fn next(self: *AsyncIterator) !?[]const u8 {
        if (self.done) return null;
        self.done = true;
        return try self.allocator.dupe(u8, "value");
    }

    pub fn destroy(self: *AsyncIterator) void {
        self.allocator.destroy(self);
    }
};
