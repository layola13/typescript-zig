const std = @import("std");

/// Serialized diagnostics
pub const SerializedDiagnostics = struct {
    version: u32,
    files: []FileDiagnostic,
};

/// File diagnostic
pub const FileDiagnostic = struct {
    file: []const u8,
    diagnostics: []Diagnostic,
};

/// Diagnostic
pub const Diagnostic = struct {
    code: u32,
    category: DiagnosticCategory,
    message: []const u8,
    start: u32,
    length: u32,
};

/// Diagnostic category
pub const DiagnosticCategory = enum {
    none,
    error,
    warning,
    suggestion,
    message,
};

/// Diagnostic message chain
pub const DiagnosticMessageChain = struct {
    message_text: []const u8,
    category: DiagnosticCategory,
    code: u32,
    next: ?*DiagnosticMessageChain,
};

/// Diagnostic writer
pub const DiagnosticWriter = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) DiagnosticWriter {
        return .{ .allocator = allocator, .output = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *DiagnosticWriter) void {
        self.output.deinit();
    }

    pub fn write(self: *DiagnosticWriter, diag: *const Diagnostic) !void {
        try self.output.writer().print("[TS{d}] {s}: {s}
", .{
            diag.code,
            @tagName(diag.category),
            diag.message,
        });
    }

    pub fn getOutput(self: *const DiagnosticWriter) []const u8 {
        return self.output.items;
    }
};

/// Diagnostic aggregator
pub const DiagnosticAggregator = struct {
    allocator: std.mem.Allocator,
    diagnostics: std.ArrayList(Diagnostic),

    pub fn init(allocator: std.mem.Allocator) DiagnosticAggregator {
        return .{ .allocator = allocator, .diagnostics = std.ArrayList(Diagnostic).init(allocator) };
    }

    pub fn deinit(self: *DiagnosticAggregator) void {
        self.diagnostics.deinit();
    }

    pub fn add(self: *DiagnosticAggregator, diag: Diagnostic) !void {
        try self.diagnostics.append(diag);
    }

    pub fn count(self: *const DiagnosticAggregator) usize {
        return self.diagnostics.items.len;
    }
};
