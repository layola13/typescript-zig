const std = @import("std");

/// Diagnostic severity levels
pub const Severity = enum {
    error,
    warning,
    suggestion,
    message,
};

/// Diagnostic category
pub const Category = enum {
    none,
    message,
    suggestion,
    error,
    warning,
};

/// Source file location
pub const TextSpan = struct {
    start: u32,
    length: u32,
};

/// File and line information
pub const FileSpan = struct {
    file: []const u8,
    span: TextSpan,
};

/// Diagnostic message with location
pub const Diagnostic = struct {
    code: u32,
    category: Category,
    message: []const u8,
    file: ?[]const u8 = null,
    start: ?u32 = null,
    length: ?u32 = null,
    reports_unnecessary: bool = false,
    reports_unused: bool = false,
};

/// Diagnostic reporter function
pub const DiagnosticReporter = *const fn (diag: Diagnostic) void;

/// Format diagnostic to writer
pub fn formatDiagnostic(diag: Diagnostic, writer: anytype) !void {
    if (diag.file) |file| {
        try writer.print("{s}({d},{d}): ", .{ file, diag.start orelse 0, diag.length orelse 0 });
    }
    try writer.print("[TS{d}] {s}: {s}
", .{
        diag.code,
        @tagName(diag.category),
        diag.message,
    });
}
