const std = @import("std");

/// Type checker result
pub const CheckResult = struct {
    diagnostics: []Diagnostic,
    program: *anyopaque,
};

/// Diagnostic
pub const Diagnostic = struct {
    code: u32,
    message: []const u8,
    file: ?[]const u8,
    start: ?u32,
    length: ?u32,
};

/// Type checker options
pub const CheckerOptions = struct {
    no_implicit_any: bool = false,
    strict_null_checks: bool = false,
    strict_function_types: bool = false,
    strict_bind_call_apply: bool = false,
    strict_property_initialization: bool = false,
    no_implicit_this: bool = false,
    always_strict: bool = false,
    no_unused_locals: bool = false,
    no_unused_parameters: bool = false,
};

/// Type node kinds
pub const TypeNodeKind = enum {
    keyword,
    reference,
    array,
    tuple,
    optional,
    rest,
    union,
    intersection,
    parenthesized,
    literal,
    type_query,
    index_accessed,
    mapped,
    conditional,
    infer,
};

/// Type checker state
pub const CheckerState = struct {
    allocator: std.mem.Allocator,
    options: CheckerOptions,
    error_count: u32 = 0,
    warning_count: u32 = 0,
    current_file: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) CheckerState {
        return .{ .allocator = allocator, .options = .{} };
    }

    pub fn deinit(self: *CheckerState) void {
        _ = self;
    }

    /// Check a source file
    pub fn checkFile(self: *CheckerState, file: []const u8) !CheckResult {
        _ = self;
        _ = file;
        return CheckResult{ .diagnostics = &.{}, .program = undefined };
    }

    /// Get type at position
    pub fn getTypeAtPosition(self: *const CheckerState, file: []const u8, pos: u32) ?*anyopaque {
        _ = self;
        _ = file;
        _ = pos;
        return null;
    }

    /// Check call signature
    pub fn checkCallSignature(self: *CheckerState, callee: *anyopaque, args: []const *anyopaque) ?*anyopaque {
        _ = self;
        _ = callee;
        _ = args;
        return null;
    }
};

/// Get contextual type
pub fn getContextualType(checker: *CheckerState, file: []const u8, pos: u32) ?*anyopaque {
    _ = checker;
    _ = file;
    _ = pos;
    return null;
}

/// Check property access
pub fn checkPropertyAccess(checker: *CheckerState, object: *anyopaque, property: []const u8) ?*anyopaque {
    _ = checker;
    _ = object;
    _ = property;
    return null;
}
