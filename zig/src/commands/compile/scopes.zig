const std = @import("std");

/// Scope kind
pub const ScopeKind = enum {
    unknown,
    block,
    function,
    class,
    module,
    enum_,
};

/// Scope
pub const Scope = struct {
    allocator: std.mem.Allocator,
    kind: ScopeKind,
    parent: ?*Scope,
    locals: std.StringHashMap(*anyopaque),

    pub fn init(allocator: std.mem.Allocator, kind: ScopeKind, parent: ?*Scope) Scope {
        return .{
            .allocator = allocator,
            .kind = kind,
            .parent = parent,
            .locals = std.StringHashMap(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Scope) void {
        var it = self.locals.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.locals.deinit();
    }

    pub fn addLocal(self: *Scope, name: []const u8, symbol: *anyopaque) !void {
        try self.locals.put(try self.allocator.dupe(u8, name), symbol);
    }
};

/// Scope builder
pub const ScopeBuilder = struct {
    allocator: std.mem.Allocator,
    root: *Scope,
    current: *Scope,

    pub fn init(allocator: std.mem.Allocator) ScopeBuilder {
        const root = try allocator.create(Scope);
        root.* = Scope.init(allocator, .module, null);
        return .{ .allocator = allocator, .root = root, .current = root };
    }

    pub fn deinit(self: *ScopeBuilder) void {
        self.root.deinit();
        self.allocator.destroy(self.root);
    }

    pub fn pushScope(self: *ScopeBuilder, kind: ScopeKind) !void {
        const new_scope = try self.allocator.create(Scope);
        new_scope.* = Scope.init(self.allocator, kind, self.current);
        self.current = new_scope;
    }

    pub fn popScope(self: *ScopeBuilder) void {
        if (self.current.parent) |parent| {
            self.current = parent;
        }
    }
};
