const std = @import("std");

/// Project references for composite builds
pub const ProjectReference = struct {
    path: []const u8,
    original_path: []const u8,
    is_emitted: bool = false,
    references: ?[][]const u8 = null,
};

/// Build mode options
pub const BuildMode = struct {
    dry: bool = false,
    force: bool = false,
    verbose: bool = false,
    clean: bool = false,
};

/// Build order result
pub const BuildOrder = struct {
    projects: []BuildOrderItem,
};

/// Build order item
pub const BuildOrderItem = struct {
    project: []const u8,
    config_file: []const u8,
};

/// Build resolution
pub const BuildResolution = struct {
    project: []const u8,
    errors: []const u8,
    build_needed: bool,
    tests: bool,
};

/// File output
pub const FileOutput = struct {
    file_name: []const u8,
    size: u64,
    written: bool,
};
