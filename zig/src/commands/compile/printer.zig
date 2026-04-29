const std = @import("std");

/// Printer options
pub const PrinterOptions = struct {
    tab_size: u32 = 4,
    indent: u32 = 0,
    line_map: bool = true,
    remove_comments: bool = false,
    compact: bool = false,
};

/// Print result
pub const PrintResult = struct {
    text: []const u8,
    text_map: ?*anyopaque,
};

/// Printer
pub const Printer = struct {
    allocator: std.mem.Allocator,
    options: PrinterOptions,
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, options: PrinterOptions) Printer {
        return .{
            .allocator = allocator,
            .options = options,
            .output = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Printer) void {
        self.output.deinit();
    }

    pub fn printNode(self: *Printer, node: *anyopaque) !void {
        _ = self;
        _ = node;
    }

    pub fn getText(self: *const Printer) []const u8 {
        return self.output.items;
    }
};

/// Print to string
pub fn printToString(allocator: std.mem.Allocator, node: *anyopaque, options: PrinterOptions) ![]const u8 {
    var printer = Printer.init(allocator, options);
    defer printer.deinit();
    try printer.printNode(node);
    return try allocator.dupe(u8, printer.getText());
}
