const std = @import("std");
const symbol = @import("../sema/symbol_table.zig");

/// Type representation
pub const Type = enum {
    void,
    number,
    string,
    boolean,
    null,
    undefined,
    object,
    array,
    function,
    unknown,
    never,
    any,
};

/// Type constraint solver
pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    symbols: *symbol.SymbolTable,
    errors: std.ArrayList(TypeError),

    pub const TypeError = struct {
        message: []const u8,
        line: u32,
        column: u32,
    };

    pub fn init(allocator: std.mem.Allocator, symbols: *symbol.SymbolTable) TypeChecker {
        return .{
            .allocator = allocator,
            .symbols = symbols,
            .errors = std.ArrayList(TypeError).init(allocator),
        };
    }

    pub fn checkAssignment(self: *TypeChecker, target: Type, value: Type) !bool {
        if (target == .any or target == .unknown) return true;
        if (target == value) return true;
        if (target == .null and value == .null) return true;
        return false;
    }

    pub fn checkFunction(self: *TypeChecker, params: []const Type, args: []const Type) !bool {
        if (params.len != args.len) return false;
        for (params, 0..) |param, i| {
            if (!(try self.checkAssignment(param, args[i]))) return false;
        }
        return true;
    }

    pub fn addError(self: *TypeChecker, msg: []const u8, line: u32, col: u32) void {
        self.errors.append(.{ .message = msg, .line = line, .column = col }) catch unreachable;
    }

    pub fn destroy(self: *TypeChecker) void {
        self.errors.deinit();
    }
};
