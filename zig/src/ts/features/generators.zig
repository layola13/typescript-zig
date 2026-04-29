const std = @import("std");

/// Generator functions support
pub const Generator = struct {
    allocator: std.mem.Allocator,
    value: ?[]const u8 = null,
    done: bool = false,

    pub fn next(self: *Generator, args: ?[]const u8) !struct { done: bool, value: []const u8 } {
        if (self.done) return .{ .done = true, .value = "" };
        self.done = true;
        const v = try self.allocator.dupe(u8, self.value orelse "");
        return .{ .done = false, .value = v };
    }

    pub fn destroy(self: *Generator) void {
        self.allocator.destroy(self);
    }
};
