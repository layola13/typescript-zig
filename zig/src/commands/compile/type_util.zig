const std = @import("std");

/// Type map
pub const TypeMap = struct {
    allocator: std.mem.Allocator,
    types: std.AutoHashMap([]const u8, *anyopaque),

    pub fn init(allocator: std.mem.Allocator) TypeMap {
        return .{ .allocator = allocator, .types = std.AutoHashMap([]const u8, *anyopaque).init(allocator) };
    }

    pub fn deinit(self: *TypeMap) void {
        var it = self.types.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.types.deinit();
    }

    pub fn set(self: *TypeMap, key: []const u8, value: *anyopaque) !void {
        try self.types.put(try self.allocator.dupe(u8, key), value);
    }

    pub fn get(self: *const TypeMap, key: []const u8) ?*anyopaque {
        return self.types.get(key);
    }
};

/// Get type string
pub fn typeToString(type_: *anyopaque) []const u8 {
    _ = type_;
    return "any";
}

/// Get type id
pub fn getTypeId(type_: *anyopaque) u32 {
    _ = type_;
    return 0;
}
