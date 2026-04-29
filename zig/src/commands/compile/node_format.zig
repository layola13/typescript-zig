const std = @import("std");

/// Format options
pub const FormatOptions = struct {
    tab_size: u32 = 4,
    insert_space: bool = true,
    convert_tabs_to_spaces: bool = true,
};

/// Format node
pub fn formatNode(node: *anyopaque, options: FormatOptions) []const u8 {
    _ = node;
    _ = options;
    return "";
}

/// Format node and write
pub fn formatNodeAndWrite(node: *anyopaque, options: FormatOptions, writer: anytype) !void {
    const text = formatNode(node, options);
    try writer.writeAll(text);
}
