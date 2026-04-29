const std = @import("std");

/// Get root directory
pub fn getRootDir() []const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.process.getCwd(&buf) catch return "/";
    return path;
}

/// Get absolute path
pub fn getAbsolutePath(allocator: std.mem.Allocator, base: []const u8, relative: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, relative });
}

/// Normalize path separators
pub fn normalizePath(path: []const u8) []const u8 {
    var result: []u8 = &.{};
    for (path) |c| {
        if (c == '\') {
            result = result ++ "/";
        } else {
            result = result ++ &[_]u8{c};
        }
    }
    return result;
}

/// Check if path is relative
pub fn isRelative(path: []const u8) bool {
    return !std.fs.path.isAbsolute(path);
}

/// Get file extension
pub fn getExtension(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Change extension
pub fn changeExtension(path: []const u8, new_ext: []const u8) []const u8 {
    const ext = getExtension(path);
    if (ext.len == 0) return path ++ new_ext;
    return std.mem.concat(u8, &.{ std.fs.path.dirname(path) orelse ".", std.fs.path.basename(path, ext), new_ext });
}
