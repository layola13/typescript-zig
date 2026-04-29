const std = @import("std");

/// Package info from package.json
pub const PackageInfo = struct {
    name: []const u8,
    version: []const u8,
    main: ?[]const u8,
    types: ?[]const u8,
    exports: ?ExportsMap,
    dependencies: ?[][]const u8,
    dev_dependencies: ?[][]const u8,
};

/// Exports map for package.json exports field
pub const ExportsMap = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(ExportsEntry),

    pub fn init(allocator: std.mem.Allocator) ExportsMap {
        return .{ .allocator = allocator, .entries = std.StringHashMap(ExportsEntry).init(allocator) };
    }

    pub fn deinit(self: *ExportsMap) void {
        self.entries.deinit();
    }
};

/// Exports entry
pub const ExportsEntry = struct {
    types: ?[]const u8,
    require: ?[]const u8,
    import: ?[]const u8,
    default: ?[]const u8,
};

/// Package json info
pub const PackageJsonInfo = struct {
    info: PackageInfo,
    file_name: []const u8,
    path: []const u8,
};

/// Package json host
pub const PackageJsonHost = struct {
    allocator: std.mem.Allocator,
    fs: std.fs.FileSystem,

    pub fn init(allocator: std.mem.Allocator) PackageJsonHost {
        return .{ .allocator = allocator, .fs = std.fs.cwd() };
    }

    pub fn deinit(self: *PackageJsonHost) void {
        _ = self;
    }

    /// Read package.json
    pub fn readPackageJson(self: *const PackageJsonHost, path: []const u8) !PackageInfo {
        const text = try self.fs.openFile(path, .{}) catch return error.FileNotFound;
        defer text.close();
        const content = try text.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);
        // Parse package.json
        _ = content;
        return PackageInfo{ .name = "", .version = "" };
    }
};

/// Get package name from file path
pub fn getPackageNameFromTypes(types: []const u8) ?[]const u8 {
    _ = types;
    return null;
}
