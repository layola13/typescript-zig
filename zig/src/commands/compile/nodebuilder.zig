const std = @import("std");

/// Node builder context
pub const NodeBuilderContext = struct {
    allocator: std.mem.Allocator,
    checker: *anyopaque,
    type_builder: *TypeBuilder,
};

/// Type builder
pub const TypeBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TypeBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TypeBuilder) void {
        _ = self;
    }
};

/// Build type from node
pub fn buildTypeFromNode(ctx: *NodeBuilderContext, node: *anyopaque) ?*anyopaque {
    _ = ctx;
    _ = node;
    return null;
}

/// Build type from type node
pub fn buildTypeFromTypeNode(ctx: *NodeBuilderContext, node: *anyopaque) ?*anyopaque {
    _ = ctx;
    _ = node;
    return null;
}
