const std = @import("std");

/// JSDoc tag kinds
pub const JSDocTagKind = enum {
    tag,
    annotation,
};

/// JSDoc tag
pub const JSDocTag = struct {
    tag_name: []const u8,
    comment: []const u8,
};

/// JSDoc info
pub const JSDocInfo = struct {
    tags: []JSDocTag,
    comment: []const u8,
};

/// JSDoc type literal
pub const JSDocTypeLiteral = struct {
    js_doc: ?*anyopaque,
    type_node: ?*anyopaque,
};

/// JSDoc callback
pub const JSDocCallbackTag = struct {
    full_name: ?*anyopaque,
    name: ?*anyopaque,
    params: ?[]*anyopaque,
    return_type: ?*anyopaque,
};

/// JSDoc template
pub const JSDocTemplateTag = struct {
    tag_name: []const u8,
    constraint: ?*anyopaque,
    type_parameters: ?[]*anyopaque,
};

/// Parse JSDoc from source
pub fn parseJSDoc(text: []const u8) JSDocInfo {
    _ = text;
    return JSDocInfo{ .tags = &.{}, .comment = "" };
}
