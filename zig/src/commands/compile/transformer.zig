const std = @import("std");

/// Transformer options
pub const TransformerOptions = struct {
    target: ?u32 = null,
    module_kind: ?u32 = null,
    remove_comments: bool = false,
    strict: bool = false,
    emit_bom: bool = false,
    emit_decorations: bool = false,
    importHelpers: bool = false,
    noEmitHelpers: bool = false,
};

/// Transformer context
pub const TransformerContext = struct {
    allocator: std.mem.Allocator,
    options: TransformerOptions,
    host: *anyopaque,
    program: *anyopaque,

    pub fn init(allocator: std.mem.Allocator, opts: TransformerOptions) TransformerContext {
        return .{
            .allocator = allocator,
            .options = opts,
            .host = undefined,
            .program = undefined,
        };
    }

    pub fn deinit(self: *TransformerContext) void {
        _ = self;
    }

    /// Start transformation
    pub fn start(self: *TransformerContext) !void {
        _ = self;
    }
};

/// Transformation result
pub const TransformationResult = struct {
    files: []TransformationFile,
    diagnostics: []Diagnostic,
    emit_skipped: bool,
};

/// Transformation file
pub const TransformationFile = struct {
    file_name: []const u8,
    text: []const u8,
    text_settings: TextSettings,
};

/// Text settings
pub const TextSettings = struct {
    has_trailing_new_line: bool = true,
    pretty: bool = false,
};

/// Diagnostic
pub const Diagnostic = struct {
    code: u32,
    message: []const u8,
    file: ?[]const u8,
};

/// Emit helper
pub const EmitHelper = struct {
    name: []const u8,
    priority: u32,
    text: []const u8,
};

/// Get emit helpers
pub fn getEmitHelpers(ctx: *TransformerContext, node: *anyopaque) ?[]const EmitHelper {
    _ = ctx;
    _ = node;
    return null;
}
