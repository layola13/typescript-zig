const std = @import("std");
const root = @import("../../../main.zig");
const ast = @import("ast/kind.zig");

/// Symbol represents a named declaration
pub const Symbol = struct {
    name: []const u8,
    kind: ast.SyntaxKind,
    declaration: ?usize = null,
    flags: SymbolFlags = .{},
};

/// Symbol flags
pub const SymbolFlags = struct {
    exported: bool = false,
    ambient: bool = false,
    augmented: bool = false,
    disabled: bool = false,
    optional: bool = false,
};

/// Symbol table mapping names to symbols
pub const SymbolTable = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMap(Symbol),

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Symbol).init(allocator),
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        self.symbols.deinit();
    }

    pub fn set(self: *SymbolTable, name: []const u8, sym: Symbol) !void {
        try self.symbols.put(try self.allocator.dupe(u8, name), sym);
    }

    pub fn get(self: *const SymbolTable, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }

    pub fn has(self: *const SymbolTable, name: []const u8) bool {
        return self.symbols.contains(name);
    }
};

/// Local symbol bucket for scope tracking
pub const LocalSymbolBucket = struct {
    allocator: std.mem.Allocator,
    symbols: std.StringHashMap(Symbol),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(Symbol).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.symbols.deinit();
    }
};
