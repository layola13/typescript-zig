const std = @import("std");

/// Flow analysis flags
pub const FlowFlags = struct {
    shared: bool = false,
    branch: bool = false,
    label: bool = false,
    loop: bool = false,
    try_: bool = false,
    call: bool = false,
};

/// Flow lock
pub const FlowLock = struct {
    shared: bool = false,
};

/// Flow analysis reference
pub const FlowReference = struct {
    node: *anyopaque,
    qualifier: ?*anyopaque,
};

/// Flow analysis
pub const FlowAnalysis = struct {
    allocator: std.mem.Allocator,
    flags: FlowFlags,
    current_node: ?*anyopaque,

    pub fn init(allocator: std.mem.Allocator) FlowAnalysis {
        return .{ .allocator = allocator, .flags = .{}, .current_node = null };
    }

    pub fn deinit(self: *FlowAnalysis) void {
        _ = self;
    }

    /// Start flow analysis
    pub fn start(self: *FlowAnalysis, node: *anyopaque) void {
        self.current_node = node;
    }

    /// Get type at current position
    pub fn getType(self: *const FlowAnalysis) ?*anyopaque {
        _ = self;
        return null;
    }
};

/// Flow type
pub const FlowType = enum {
    absolute,
    reference,
    not_known,
    undefined,
    null,
    string,
    number,
    boolean,
    bigint,
    essymbol,
    object,
    callable,
    namespace,
    property,
    method,
    method_or_getter,
    accessor,
    enum_member,
    tiny,
};

/// Get flow type
pub fn getFlowType(analysis: *const FlowAnalysis, node: *anyopaque) FlowType {
    _ = analysis;
    _ = node;
    return .not_known;
}
