const std = @import("std");

/// Symbol display part
pub const SymbolDisplayPart = struct {
    text: []const u8,
    kind: SymbolDisplayPartKind,
};

/// Symbol display part kind
pub const SymbolDisplayPartKind = enum {
    line_break,
    space,
    text,
    keyword,
    punctuation,
    plus,
    minus,
    dot,
    operator,
    class_name,
    enum_name,
    module_name,
    property_name,
    method_name,
    parameter_name,
    local_name,
    string_literal,
    interface_name,
    type_parameter_name,
    alias_name,
    numeric_literal,
    nothing,
};

/// Get display parts as string
pub fn displayPartsToString(parts: []SymbolDisplayPart) []const u8 {
    var result: []u8 = &.{};
    for (parts) |part| {
        if (part.kind != .line_break and part.kind != .nothing) {
            result = result ++ part.text;
        }
    }
    return result;
}

/// Part builder
pub const PartBuilder = struct {
    allocator: std.mem.Allocator,
    parts: std.ArrayList(SymbolDisplayPart),

    pub fn init(allocator: std.mem.Allocator) PartBuilder {
        return .{ .allocator = allocator, .parts = std.ArrayList(SymbolDisplayPart).init(allocator) };
    }

    pub fn deinit(self: *PartBuilder) void {
        self.parts.deinit();
    }

    pub fn addText(self: *PartBuilder, text: []const u8) !void {
        try self.parts.append(.{ .text = text, .kind = .text });
    }

    pub fn addKeyword(self: *PartBuilder, keyword: []const u8) !void {
        try self.parts.append(.{ .text = keyword, .kind = .keyword });
    }

    pub fn addPunctuation(self: *PartBuilder, punct: []const u8) !void {
        try self.parts.append(.{ .text = punct, .kind = .punctuation });
    }

    pub fn addClassName(self: *PartBuilder, name: []const u8) !void {
        try self.parts.append(.{ .text = name, .kind = .class_name });
    }

    pub fn addProperty(self: *PartBuilder, name: []const u8) !void {
        try self.parts.append(.{ .text = name, .kind = .property_name });
    }

    pub fn getParts(self: *PartBuilder) []SymbolDisplayPart {
        return self.parts.items;
    }
};
