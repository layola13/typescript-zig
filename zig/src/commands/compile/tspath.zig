const std = @import("std");

/// Join multiple path components
pub fn join(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return std.fs.path.join(allocator, parts);
}

/// Normalize a path (resolve . and ..)
pub fn normalize(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.path.resolve(allocator, &.{path});
}

/// Get the directory name of a path
pub fn dirname(path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse ".";
}

/// Get the base name of a path
pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

/// Get the extension of a path
pub fn extension(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Check if path is absolute
pub fn isAbsolute(path: []const u8) bool {
    return std.fs.path.isAbsolute(path);
}

/// Convert to absolute path
pub fn toAbsolute(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.path.resolve(allocator, &.{path});
}

/// Get relative path from base to target
pub fn relative(allocator: std.mem.Allocator, from: []const u8, to: []const u8) ![]u8 {
    return std.fs.path.relative(allocator, from, to);
}

/// Check if path starts with prefix
pub fn startsWith(path: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, path, prefix);
}
