const std = @import("std");

/// TypeScript built-in type definitions
pub const BuiltinTypes = struct {
    pub const any = "any";
    pub const unknown = "unknown";
    pub const never = "never";
    pub const void_ = "void";
    pub const undefined_ = "undefined";
    pub const null_ = "null";
    pub const number = "number";
    pub const string = "string";
    pub const boolean = "boolean";
    pub const symbol = "symbol";
    pub const bigint = "bigint";
};

pub const Keywords = std.ComptimeStringMap([]const u8, .{
    .{ "any", BuiltinTypes.any },
    .{ "unknown", BuiltinTypes.unknown },
    .{ "never", BuiltinTypes.never },
    .{ "void", BuiltinTypes.void_ },
    .{ "number", BuiltinTypes.number },
    .{ "string", BuiltinTypes.string },
    .{ "boolean", BuiltinTypes.boolean },
    .{ "type", "type" },
    .{ "interface", "interface" },
    .{ "class", "class" },
    .{ "enum", "enum" },
    .{ "export", "export" },
    .{ "import", "import" },
    .{ "const", "const" },
    .{ "let", "let" },
    .{ "var", "var" },
    .{ "function", "function" },
    .{ "return", "return" },
    .{ "if", "if" },
    .{ "else", "else" },
    .{ "for", "for" },
    .{ "while", "while" },
    .{ "true", "true" },
    .{ "false", "false" },
    .{ "null", "null" },
    .{ "undefined", "undefined" },
    .{ "async", "async" },
    .{ "await", "await" },
    .{ "public", "public" },
    .{ "private", "private" },
    .{ "protected", "protected" },
    .{ "readonly", "readonly" },
    .{ "static", "static" },
    .{ "extends", "extends" },
    .{ "implements", "implements" },
    .{ "new", "new" },
    .{ "this", "this" },
    .{ "super", "super" },
    .{ "typeof", "typeof" },
);
