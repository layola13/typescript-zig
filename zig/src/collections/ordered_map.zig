const std = @import("std");

/// MapEntry represents a key-value pair for use with iteration.
pub fn MapEntry(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
    };
}

/// KeyIterator iterates over keys in an OrderedMap.
pub fn KeyIterator(comptime K: type) type {
    return struct {
        keys: []K,
        index: usize,
        pub fn next(self: *@This()) ?K {
            if (self.index >= self.keys.len) return null;
            defer self.index += 1;
            return self.keys[self.index];
        }
    };
}

/// ValueIterator iterates over values in an OrderedMap.
pub fn ValueIterator(comptime K: type, comptime V: type) type {
    return struct {
        keys: []K,
        mp: std.AutoHashMap(K, V),
        index: usize,
        pub fn next(self: *@This()) ?V {
            if (self.index >= self.keys.len) return null;
            defer self.index += 1;
            return self.mp.get(self.keys[self.index]);
        }
    };
}

/// EntryIterator iterates over key-value pairs in an OrderedMap.
pub fn EntryIterator(comptime K: type, comptime V: type) type {
    return struct {
        keys: []K,
        mp: std.AutoHashMap(K, V),
        index: usize,
        pub fn next(self: *@This()) ?MapEntry(K, V) {
            if (self.index >= self.keys.len) return null;
            defer self.index += 1;
            const key = self.keys[self.index];
            return MapEntry(K, V){ .key = key, .value = self.mp.get(key).? };
        }
    };
}

/// OrderedMap is an insertion ordered map.
/// Uses a slice for key ordering and a hash map for O(1) lookups.
pub fn OrderedMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        keys: []K,
        mp: std.AutoHashMap(K, V),
        allocator: std.mem.Allocator,

        /// Initialize an empty OrderedMap.
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .keys = &.{},
                .mp = std.AutoHashMap(K, V).init(allocator),
            };
        }

        /// Initialize with a capacity hint.
        pub fn initCapacity(allocator: std.mem.Allocator, hint: usize) !Self {
            var self = Self{
                .allocator = allocator,
                .keys = &.{},
                .mp = try std.AutoHashMap(K, V).initCapacity(allocator, hint),
            };
            if (hint > 0) {
                self.keys = try allocator.alloc(K, hint);
                self.keys.len = 0;
            }
            return self;
        }

        /// Deinitialize and free memory.
        pub fn deinit(self: *Self) void {
            self.mp.deinit();
            if (self.keys.len > 0) {
                self.allocator.free(self.keys);
            }
        }

        /// Set a key-value pair.
        pub fn set(self: *Self, key: K, value: V) !void {
            const gop = try self.mp.getOrPut(key);
            if (!gop.found_existing) {
                try self.keys.append(key);
            }
            gop.value_ptr.* = value;
        }

        /// Get retrieves a value.
        pub fn get(self: *const Self, key: K) ?V {
            return self.mp.get(key);
        }

        /// GetOrZero returns value or zero.
        pub fn getOrZero(self: *const Self, key: K) V {
            return self.mp.get(key) orelse @as(V, 0);
        }

        /// EntryAt returns key-value at index.
        pub fn entryAt(self: *const Self, index: usize) ?MapEntry(K, V) {
            if (index >= self.keys.len) return null;
            const key = self.keys[index];
            const value = self.mp.get(key).?;
            return MapEntry(K, V){ .key = key, .value = value };
        }

        /// Has returns true if key exists.
        pub fn has(self: *const Self, key: K) bool {
            return self.mp.contains(key);
        }

        /// Delete removes a key-value pair.
        pub fn delete(self: *Self, key: K) ?V {
            const value = self.mp.fetchRemove(key) orelse return null;
            for (self.keys, 0..) |k, i| {
                if (std.meta.eql(k, key)) {
                    @memcpy(self.keys[i..self.keys.len-1], self.keys[i+1..self.keys.len]);
                    self.keys.len -= 1;
                    break;
                }
            }
            return value;
        }

        /// Clear removes all entries.
        pub fn clear(self: *Self) void {
            self.keys.len = 0;
            self.mp.clearRetainingCapacity();
        }

        /// len returns the number of entries.
        pub fn len(self: *const Self) usize {
            return self.keys.len;
        }

        /// Clone returns a shallow copy.
        pub fn clone(self: *const Self) !Self {
            var result = Self{
                .allocator = self.allocator,
                .keys = try self.allocator.alloc(K, self.keys.len),
                .mp = try std.AutoHashMap(K, V).initCapacity(self.allocator, self.keys.len),
            };
            @memcpy(result.keys, self.keys);
            var it = self.mp.iterator();
            while (it.next()) |entry| {
                result.mp.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
            }
            return result;
        }
    };
}
