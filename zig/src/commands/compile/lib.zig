const std = @import("std");

/// Get default library file name
pub fn getDefaultLibFileName(target: []const u8) []const u8 {
    _ = target;
    return "lib.d.ts";
}

/// Get default library extension
pub fn getDefaultLibExtension() []const u8 {
    return ".d.ts";
}

/// Get executable extension
pub fn getExecutableExtension() []const u8 {
    return if (std.builtin.os.tag == .windows) ".exe" else "";
}

/// Get declaration emit helper name
pub fn getDeclarationEmitHelperName() []const u8 {
    return "__decorate";
}

/// Get import helper name
pub fn getImportHelperName() []const u8 {
    return "__importStar";
}

/// Get await helper name
pub fn getAwaitHelperName() []const u8 {
    return "__await";
}

/// Get generator helper name
pub fn getGeneratorHelperName() []const u8 {
    return "__generator";
}
