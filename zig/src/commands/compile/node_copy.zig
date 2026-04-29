const std = @import("std");

/// Node copy options
pub const NodeCopyOptions = struct {
    copy_locals: bool = true,
    copy_synthetic: bool = false,
};

/// Copy node
pub fn copyNode(node: *anyopaque, options: NodeCopyOptions) ?*anyopaque {
    _ = node;
    _ = options;
    return null;
}

/// Deep clone node
pub fn cloneNode(node: *anyopaque) ?*anyopaque {
    _ = node;
    return null;
}

/// Copy identifiers
pub fn copyIdentifiers(node: *anyopaque) void {
    _ = node;
}
