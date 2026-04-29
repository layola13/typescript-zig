const std = @import("std");

/// Pseudo type node
pub const PseudoTypeNode = struct {
    kind: PseudoTypeKind,
    text: []const u8,
};

/// Pseudo type kind
pub const PseudoTypeKind = enum {
    identifier,
    keyword,
    literal,
    operator,
    punctuation,
    comment,
};

/// Build pseudo type from node
pub fn buildPseudoTypeNode(node: *anyopaque) ?PseudoTypeNode {
    _ = node;
    return null;
}

/// Format pseudo type
pub fn formatPseudoType(node: *const PseudoTypeNode) []const u8 {
    _ = node;
    return "";
}
