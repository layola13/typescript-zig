const std = @import("std");

/// Type definition provider
pub const TypeDefinitionProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TypeDefinitionProvider {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TypeDefinitionProvider) void {
        _ = self;
    }
};

/// Implementation provider
pub const ImplementationProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ImplementationProvider {
        return .{ .allocator = allocator };
    }
};

/// Document highlight provider
pub const DocumentHighlightProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DocumentHighlightProvider {
        return .{ .allocator = allocator };
    }
};

/// Code lens provider
pub const CodeLensProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CodeLensProvider {
        return .{ .allocator = allocator };
    }

    /// Resolve code lens
    pub fn resolve(self: *CodeLensProvider, code_lens: *CodeLens) !void {
        _ = self;
        _ = code_lens;
    }
};

/// Code lens
pub const CodeLens = struct {
    range: Range,
    command: ?Command,
    data: ?[]u8,
};

/// Command
pub const Command = struct {
    title: []const u8,
    command: []const u8,
    arguments: ?[]u8,
};

/// Range
pub const Range = struct {
    start: Position,
    end: Position,
};

/// Position
pub const Position = struct {
    line: u32,
    character: u32,
};

/// Document link provider
pub const DocumentLinkProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DocumentLinkProvider {
        return .{ .allocator = allocator };
    }
};

/// Document link
pub const DocumentLink = struct {
    range: Range,
    target: ?[]const u8,
    tooltip: ?[]const u8,
};

/// Color provider
pub const ColorProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ColorProvider {
        return .{ .allocator = allocator };
    }
};

/// Color
pub const Color = struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

/// Color information
pub const ColorInformation = struct {
    range: Range,
    color: Color,
};
