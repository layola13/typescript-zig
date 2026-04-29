const std = @import("std");
const source = @import("source_file.zig");

/// Incremental compilation state
pub const IncrementalBuilder = struct {
    allocator: std.mem.Allocator,
    build_info: ?BuildInfo,
    dirty: std.StringHashMap(bool),

    pub fn init(allocator: std.mem.Allocator) IncrementalBuilder {
        return .{
            .allocator = allocator,
            .build_info = null,
            .dirty = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *IncrementalBuilder) void {
        if (self.build_info) |bi| {
            self.allocator.free(bi.signature);
        }
        self.dirty.deinit();
    }

    /// Mark a file as dirty (needs recompilation)
    pub fn markDirty(self: *IncrementalBuilder, file: []const u8) !void {
        try self.dirty.put(try self.allocator.dupe(u8, file), true);
    }

    /// Check if a file is dirty
    pub fn isDirty(self: *const IncrementalBuilder, file: []const u8) bool {
        return self.dirty.get(file) orelse false;
    }

    /// Get or create build info
    pub fn getBuildInfo(self: *IncrementalBuilder) !*BuildInfo {
        if (self.build_info) |*bi| return bi;
        self.build_info = try self.allocator.create(BuildInfo);
        self.build_info.* = BuildInfo{
            .signature = try self.allocator.dupe(u8, ""),
            .file_names = &.{},
        };
        return &self.build_info.?;
    }
};

/// Build information
pub const BuildInfo = struct {
    signature: []const u8,
    file_names: [][]const u8,
    file_infos: []FileInfo,
};

/// File information
pub const FileInfo = struct {
    name: []const u8,
    signature: []const u8,
    version: u32,
};

/// Build info reader
pub const BuildInfoReader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BuildInfoReader {
        return .{ .allocator = allocator };
    }

    /// Read build info from file
    pub fn read(self: *const BuildInfoReader, path: []const u8) !?BuildInfo {
        const text = std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024) catch return null;
        defer self.allocator.free(text);
        // Parse JSON build info
        return null;
    }
};

/// Build info writer
pub const BuildInfoWriter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BuildInfoWriter {
        return .{ .allocator = allocator };
    }

    /// Write build info to file
    pub fn write(self: *const BuildInfoWriter, path: []const u8, info: *const BuildInfo) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll("{"signature":"" ++ info.signature ++ ""}");
    }
};
