const std = @import("std");

/// Serialized diagnostics file
pub const SerializedDiagnostics = struct {
    version: u32,
    files: []FileDiagnostics,
};

/// File diagnostics
pub const FileDiagnostics = struct {
    file_name: []const u8,
    diagnostics: []DiagEntry,
};

/// Diagnostic entry
pub const DiagEntry = struct {
    code: u32,
    start: u32,
    length: u32,
    message: []const u8,
};

/// Read serialized diagnostics
pub fn readSerializedDiagnostics(path: []const u8) !?SerializedDiagnostics {
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();
    return null;
}

/// Write serialized diagnostics
pub fn writeSerializedDiagnostics(path: []const u8, diags: *const SerializedDiagnostics) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll("{"version":" ++ diags.version ++ "}");
}
