const std = @import("std");

/// Project reference
pub const ProjectReference = struct {
    path: []const u8,
    original_path: []const u8,
    prepend: bool = false,
    types: ?[]const u8 = null,
};

/// Build order result
pub const BuildOrderResult = struct {
    projects: []BuildOrderItem,
    errors: []BuildError,
};

/// Build order item
pub const BuildOrderItem = struct {
    project: []const u8,
    config_file: []const u8,
};

/// Build error
pub const BuildError = struct {
    project: []const u8,
    message: []const u8,
    code: u32,
};

/// Build config
pub const BuildConfig = struct {
    project_references: ?[]ProjectReference,
    build_mode: bool = false,
    force: bool = false,
    dry: bool = false,
    clean: bool = false,
};

/// Solution file
pub const SolutionFile = struct {
    allocator: std.mem.Allocator,
    file_name: []const u8,
    projects: []SolutionProject,

    pub fn init(allocator: std.mem.Allocator) SolutionFile {
        return .{
            .allocator = allocator,
            .file_name = "",
            .projects = &.{},
        };
    }

    pub fn deinit(self: *SolutionFile) void {
        for (self.projects) |p| self.allocator.free(p.config_file);
        self.allocator.free(self.projects);
    }
};

/// Solution project
pub const SolutionProject = struct {
    config_file: []const u8,
    reverse_references: ?[][]const u8,
};

/// Get build order
pub fn getBuildOrder(config: *const BuildConfig) ![]BuildOrderItem {
    _ = config;
    return &.{};
}

/// Resolve project references
pub fn resolveProjectReferences(config: *const BuildConfig) ![]ProjectReference {
    _ = config;
    return &.{};
}
