const std = @import("std");

/// Map action
pub const MapAction = enum {
    created,
    changed,
    deleted,
    renamed,
};

/// Map result
pub const MapResult = struct {
    action: MapAction,
    path: []const u8,
};

/// File mapper
pub const FileMapper = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(MapResult),

    pub fn init(allocator: std.mem.Allocator) FileMapper {
        return .{ .allocator = allocator, .map = std.StringHashMap(MapResult).init(allocator) };
    }

    pub fn deinit(self: *FileMapper) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.map.deinit();
    }
};

/// Map files
pub fn mapFiles(mapper: *FileMapper, from: []const u8, to: []const u8) !void {
    _ = mapper;
    _ = from;
    _ = to;
}
