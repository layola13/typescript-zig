const std = @import("std");

/// Source file map entry
pub const SourceFileMapEntry = struct {
    line: u32,
    offset: u32,
};

/// Source map
pub const SourceFileMap = struct {
    allocator: std.mem.Allocator,
    entries: []SourceFileMapEntry,
    sorted: bool,

    pub fn init(allocator: std.mem.Allocator) SourceFileMap {
        return .{ .allocator = allocator, .entries = &.{}, .sorted = false };
    }

    pub fn deinit(self: *SourceFileMap) void {
        self.allocator.free(self.entries);
    }

    /// Get line start for a line number
    pub fn getLineStarts(self: *const SourceFileMap) []u32 {
        _ = self;
        return &.{};
    }

    /// Get position from line and column
    pub fn getPosition(self: *const SourceFileMap, line: u32, column: u32) u32 {
        _ = self;
        _ = line;
        _ = column;
        return 0;
    }
};
