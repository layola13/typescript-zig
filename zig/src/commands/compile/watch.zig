const std = @import("std");

/// File watcher callback
pub const WatchCallback = *const fn (file_name: []const u8, event: WatchEvent) void;

/// Watch event
pub const WatchEvent = enum {
    created,
    changed,
    deleted,
};

/// Directory watcher
pub const DirectoryWatcher = struct {
    allocator: std.mem.Allocator,
    fs: std.fs.FileSystem,

    pub fn init(allocator: std.mem.Allocator) DirectoryWatcher {
        return .{ .allocator = allocator, .fs = std.fs.cwd() };
    }

    pub fn deinit(self: *DirectoryWatcher) void {
        _ = self;
    }

    /// Watch directory
    pub fn watchDirectory(self: *DirectoryWatcher, dir: []const u8, callback: WatchCallback) !void {
        _ = self;
        _ = dir;
        _ = callback;
    }
};

/// File watcher
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    fs: std.fs.FileSystem,
    watched: std.StringHashMap(WatchCallback),

    pub fn init(allocator: std.mem.Allocator) FileWatcher {
        return .{ .allocator = allocator, .fs = std.fs.cwd(), .watched = std.StringHashMap(WatchCallback).init(allocator) };
    }

    pub fn deinit(self: *FileWatcher) void {
        var it = self.watched.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.watched.deinit();
    }

    /// Watch file
    pub fn watchFile(self: *FileWatcher, file: []const u8, callback: WatchCallback) !void {
        try self.watched.put(try self.allocator.dupe(u8, file), callback);
    }

    /// Unwatch file
    pub fn unwatchFile(self: *FileWatcher, file: []const u8) void {
        if (self.watched.fetchRemove(file)) |entry| {
            self.allocator.free(entry.key);
        }
    }
};

/// Watch options
pub const WatchOptions = struct {
    watch_file: bool = true,
    watch_directory: bool = true,
    ignore_pattern: ?[]const u8 = null,
    fallback_polling: bool = false,
};
