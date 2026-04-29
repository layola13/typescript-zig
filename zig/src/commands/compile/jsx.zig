const std = @import("std");

/// JSX parse options
pub const JsxParseOptions = struct {
    jsx: JsxMode,
    jsx_factory: ?[]const u8,
    jsx_fragment_factory: ?[]const u8,
    jsx_import_source: ?[]const u8,
};

/// JSX emit options
pub const JsxEmitOptions = struct {
    jsx: JsxMode,
    jsx_factory: ?[]const u8,
    jsx_fragment_factory: ?[]const u8,
    jsx_import_source: ?[]const u8,
    jsx_runtime: ?[]const u8,
};

/// JSX mode
pub const JsxMode = enum {
    none,
    preserve,
    react,
    react_native,
    react_jsx,
    react_jsx_dev,
};

/// JSX attributes
pub const JsxAttributes = struct {
    allocator: std.mem.Allocator,
    attributes: std.ArrayList(JsxAttribute),

    pub fn init(allocator: std.mem.Allocator) JsxAttributes {
        return .{ .allocator = allocator, .attributes = std.ArrayList(JsxAttribute).init(allocator) };
    }

    pub fn deinit(self: *JsxAttributes) void {
        self.attributes.deinit();
    }
};

/// JSX attribute
pub const JsxAttribute = struct {
    name: []const u8,
    value: ?*anyopaque,
};

/// JSX child
pub const JsxChild = struct {
    kind: JsxChildKind,
    text: ?[]const u8,
    expression: ?*anyopaque,
};

/// JSX child kind
pub const JsxChildKind = enum {
    text,
    expression,
    fragment,
};

/// Parse JSX
pub fn parseJsx(text: []const u8, options: JsxParseOptions) !JsxAttributes {
    _ = text;
    _ = options;
    return error.NotImplemented;
}
