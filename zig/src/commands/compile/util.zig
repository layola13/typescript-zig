const std = @import("std");

/// String interning for efficient string comparison
pub const StringTable = struct {
    allocator: std.mem.Allocator,
    strings: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) StringTable {
        return .{ .allocator = allocator, .strings = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *StringTable) void {
        var it = self.strings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.strings.deinit();
    }

    /// Intern a string, returning the interned version
    pub fn intern(self: *StringTable, s: []const u8) ![]const u8 {
        if (self.strings.get(s)) |existing| return existing;
        const interned = try self.allocator.dupe(u8, s);
        try self.strings.put(interned, interned);
        return interned;
    }
};

/// Bit vector for efficiently tracking sets of integers
pub const BitVector = struct {
    words: []u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_bits: usize) !BitVector {
        const num_words = (num_bits + 63) / 64;
        return .{
            .allocator = allocator,
            .words = try allocator.alloc(u64, num_words),
        };
    }

    pub fn deinit(self: *BitVector) void {
        self.allocator.free(self.words);
    }

    pub fn set(self: *BitVector, bit: usize) void {
        self.words[bit / 64] |= @as(u64, 1) << @intCast(bit % 64);
    }

    pub fn reset(self: *BitVector, bit: usize) void {
        self.words[bit / 64] &= ~(@as(u64, 1) << @intCast(bit % 64));
    }

    pub fn isSet(self: *const BitVector, bit: usize) bool {
        return (self.words[bit / 64] & (@as(u64, 1) << @intCast(bit % 64))) != 0;
    }
};

/// Memoization cache
pub fn MemoCache(comptime K: type, comptime V: type) type {
    return struct {
        cache: std.AutoHashMap(K, V),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .cache = std.AutoHashMap(K, V).init(allocator), .allocator = allocator };
        }

        pub fn deinit(self: *@This()) void {
            self.cache.deinit();
        }

        pub fn get(self: *const @This(), key: K) ?V {
            return self.cache.get(key);
        }

        pub fn put(self: *@This(), key: K, value: V) !void {
            try self.cache.put(key, value);
        }
    };
}
