const std = @import("std");

/// String utilities
pub const StringUtil = struct {
    /// Trim whitespace from both ends
    pub fn trim(s: []const u8) []const u8 {
        var start: usize = 0;
        while (start < s.len and std.ascii.isWhitespace(s[start])) start += 1;
        var end = s.len;
        while (end > start and std.ascii.isWhitespace(s[end - 1])) end -= 1;
        return s[start..end];
    }

    /// Split string by delimiter
    pub fn split(s: []const u8, delim: u8) std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).init(std.heap.page_allocator);
        var start: usize = 0;
        for (s, 0..) |c, i| {
            if (c == delim) {
                result.append(s[start..i]) catch {};
                start = i + 1;
            }
        }
        result.append(s[start..]) catch {};
        return result;
    }
};
