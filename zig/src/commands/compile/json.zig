const std = @import("std");

/// Parse JSON from a string
pub fn parse(allocator: std.mem.Allocator, text: []const u8) !std.json.Value {
    var parser = std.json.parseFromSliceLeaky(std.json.Value, allocator, text, .{});
    return parser;
}

/// Parse JSON from a file
pub fn parseFromFile(allocator: std.mem.Allocator, path: []const u8) !std.json.Value {
    const text = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(text);
    return try parse(allocator, text);
}

/// Stringify JSON value to string
pub fn stringify(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try std.json.stringify(value, .{.whitespace = .indent_2}, buf.writer());
    return buf.toOwnedSlice();
}

/// Get string value from JSON object
pub fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |val| {
        if (val == .string) return val.string;
    }
    return null;
}

/// Get bool value from JSON object
pub fn getBool(obj: std.json.ObjectMap, key: []const u8) ?bool {
    if (obj.get(key)) |val| {
        if (val == .bool) return val.bool;
    }
    return null;
}

/// Get integer value from JSON object
pub fn getInt(obj: std.json.ObjectMap, key: []const u8) ?i64 {
    if (obj.get(key)) |val| {
        if (val == .integer) return val.integer;
    }
    return null;
}
