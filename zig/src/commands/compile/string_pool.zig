const std = @import("std");

/// String pool for interning
pub const StringPool = struct {
    allocator: std.mem.Allocator,
    pool: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) StringPool {
        return .{ .allocator = allocator, .pool = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *StringPool) void {
        var it = self.pool.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.pool.deinit();
    }

    pub fn intern(self: *StringPool, s: []const u8) ![]const u8 {
        if (self.pool.get(s)) |existing| return existing;
        const interned = try self.allocator.dupe(u8, s);
        try self.pool.put(interned, interned);
        return interned;
    }
};

/// Id generator
pub const IdGenerator = struct {
    next: u32 = 1,
    pub fn nextId(self: *IdGenerator) u32 {
        const id = self.next;
        self.next += 1;
        return id;
    }
};

/// Clone with allocator
pub fn cloneString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    return allocator.dupe(u8, s);
}
