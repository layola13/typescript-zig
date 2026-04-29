const std = @import("std");
const source = @import("source_file.zig");
const tsoptions = @import("tsoptions.zig");

/// Transform result
pub const TransformationResult = struct {
    files: []TransformationOutput,
    diagnostics: []const u8,
};

/// Output file from transformation
pub const TransformationOutput = struct {
    file_name: []const u8,
    text: []const u8,
    write_byte_order_mark: bool = false,
    emit_only_dts_files: bool = false,
};

/// Transformer context
pub const TransformerContext = struct {
    allocator: std.mem.Allocator,
    program: *anyopaque, // Program reference
    host: *anyopaque,     // CompilerHost reference
    options: *const tsoptions.CompilerOptions,

    pub fn init(allocator: std.mem.Allocator, opts: *const tsoptions.CompilerOptions) TransformerContext {
        return .{
            .allocator = allocator,
            .program = undefined,
            .host = undefined,
            .options = opts,
        };
    }

    /// Get source file text
    pub fn getSourceFile(self: *const TransformerContext, file_name: []const u8) ?[]const u8 {
        _ = self;
        _ = file_name;
        return null;
    }

    /// Get compiler options
    pub fn getCompilerOptions(self: *const TransformerContext) tsoptions.CompilerOptions {
        return self.options.*;
    }
};

/// Emit resolver for custom emit
pub const EmitResolver = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EmitResolver {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *EmitResolver) void {
        _ = self;
    }

    /// Check if file should be emitted
    pub fn isEmitRequired(self: *const EmitResolver, file_name: []const u8) bool {
        _ = self;
        _ = file_name;
        return true;
    }

    /// Check if declaration emit is required
    pub fn isDeclarationEmitRequired(self: *const EmitResolver, file_name: []const u8) bool {
        _ = self;
        _ = file_name;
        return true;
    }
};
