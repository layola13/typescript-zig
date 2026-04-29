const std = @import("std");

/// Map types result
pub const MapTypesResult = struct {
    mapped_type: *anyopaque,
    constraint_type: ?*anyopaque,
    mapper: *anyopaque,
};

/// Mapper
pub const Mapper = struct {
    allocator: std.mem.Allocator,
    mappings: std.AutoHashMap(*anyopaque, *anyopaque),

    pub fn init(allocator: std.mem.Allocator) Mapper {
        return .{ .allocator = allocator, .mappings = std.AutoHashMap(*anyopaque, *anyopaque).init(allocator) };
    }

    pub fn deinit(self: *Mapper) void {
        self.mappings.deinit();
    }

    pub fn setMapping(self: *Mapper, from: *anyopaque, to: *anyopaque) !void {
        try self.mappings.put(from, to);
    }
};

/// Map from type
pub fn mapType(mapper: *Mapper, type_: *anyopaque) ?*anyopaque {
    return mapper.mappings.get(type_);
}
