const std = @import("std");

/// Program emit options
pub const EmitOptions = struct {
    target: ?u32 = null,
    remove_comments: bool = false,
    pretty: bool = false,
};

/// Emit resolver
pub const EmitResolver = struct {
    allocator: std.mem.Allocator,
    emitter: ?*anyopaque,

    pub fn init(allocator: std.mem.Allocator) EmitResolver {
        return .{ .allocator = allocator, .emitter = null };
    }

    pub fn deinit(self: *EmitResolver) void {
        _ = self;
    }
};

/// Emit result
pub const EmitResult = struct {
    emit_skipped: bool,
    diagnostics: []const u8,
};

/// Emit for destructors
pub const DestructuringEmitter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DestructuringEmitter {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DestructuringEmitter) void {
        _ = self;
    }
};

/// Import emitter
pub const ImportEmitter = struct {
    allocator: std.mem.Allocator,
    deduplicated_imports: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) ImportEmitter {
        return .{
            .allocator = allocator,
            .deduplicated_imports = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ImportEmitter) void {
        var it = self.deduplicated_imports.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.deduplicated_imports.deinit();
    }
};

/// Output configuration
pub const OutputConfiguration = struct {
    output_files: []OutputFile,
    emit_skipped: bool,
};

/// Output file
pub const OutputFile = struct {
    name: []const u8,
    data: []const u8,
    write_byte_order_mark: bool = false,
    is_external_file: bool = false,
};
