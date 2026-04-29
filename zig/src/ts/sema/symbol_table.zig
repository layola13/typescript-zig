const std = @import("std");

/// Symbol table entry
pub const SymbolEntry = struct {
    name: []const u8,
    kind: SymbolKind,
    type_info: []const u8,
    definition: ?[]const u8 = null,
};

pub const SymbolKind = enum {
    variable,
    function,
    type,
    class,
    interface,
    enum,
    module,
};

/// Symbol table for type checking
pub const SymbolTable = struct {
    allocator: std.mem.Allocator,
    scopes: std.ArrayList(std.StringHashMap(SymbolEntry)),
    current_scope: usize = 0,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        var table = SymbolTable{ .allocator = allocator, .scopes = std.ArrayList(std.StringHashMap(SymbolEntry)).init(allocator) };
        table.pushScope();
        return table;
    }

    pub fn pushScope(self: *SymbolTable) void {
        self.scopes.append(std.StringHashMap(SymbolEntry).init(self.allocator)) catch unreachable;
        self.current_scope += 1;
    }

    pub fn popScope(self: *SymbolTable) void {
        if (self.current_scope > 0) {
            self.current_scope -= 1;
            self.scopes.pop();
        }
    }

    pub fn define(self: *SymbolTable, name: []const u8, entry: SymbolEntry) !void {
        if (self.current_scope < self.scopes.items.len) {
            try self.scopes.items[self.current_scope].put(name, entry);
        }
    }

    pub fn lookup(self: *SymbolTable, name: []const u8) ?SymbolEntry {
        var i: usize = self.current_scope;
        while (i > 0) : (i -= 1) {
            if (self.scopes.items[i].get(name)) |entry| {
                return entry;
            }
        }
        return null;
    }

    pub fn destroy(self: *SymbolTable) void {
        for (self.scopes.items) |scope| {
            scope.deinit();
        }
        self.scopes.deinit();
    }
};
