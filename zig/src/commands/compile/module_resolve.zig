const std = @import("std");

/// Module resolution cache
pub const ModuleResolutionCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(ResolvedModule),
    ambient_typings: ?[][]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) ModuleResolutionCache {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(ResolvedModule).init(allocator),
        };
    }

    pub fn deinit(self: *ModuleResolutionCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.file_name);
        }
        self.entries.deinit();
    }

    pub fn get(self: *const ModuleResolutionCache, key: []const u8) ?ResolvedModule {
        return self.entries.get(key);
    }

    pub fn set(self: *ModuleResolutionCache, key: []const u8, value: ResolvedModule) !void {
        try self.entries.put(try self.allocator.dupe(u8, key), value);
    }
};

/// Resolved module
pub const ResolvedModule = struct {
    file_name: []const u8,
    resolved_module_name: ?[]const u8 = null,
    is_external_library_import: bool = false,
    resolved_file_name: ?[]const u8 = null,
    package_id: ?PackageId = null,
};

/// Package ID
pub const PackageId = struct {
    name: []const u8,
    version: []const u8,
};

/// Module resolution host
pub const ModuleResolutionHost = struct {
    allocator: std.mem.Allocator,
    fs: std.fs.FileSystem,
    trace: bool = false,

    pub fn init(allocator: std.mem.Allocator) ModuleResolutionHost {
        return .{
            .allocator = allocator,
            .fs = std.fs.cwd(),
            .trace = false,
        };
    }

    pub fn fileExists(self: *const ModuleResolutionHost, path: []const u8) bool {
        return self.fs.accessable(path, .{});
    }

    pub fn readFile(self: *const ModuleResolutionHost, path: []const u8) ?[]const u8 {
        const file = self.fs.openFile(path, .{}) catch return null;
        defer file.close();
        return file.readToEndAlloc(self.allocator, 1024 * 1024) catch return null;
    }
};
