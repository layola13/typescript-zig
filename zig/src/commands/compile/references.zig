const std = @import("std");

/// Jump scanner for find all references
pub const JumpScanner = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JumpScanner {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *JumpScanner) void {
        _ = self;
    }

    /// Scan for identifier at position
    pub fn scan(self: *const JumpScanner, text: []const u8, pos: u32) ?IdentifierInfo {
        _ = self;
        _ = text;
        _ = pos;
        return null;
    }
};

/// Identifier info
pub const IdentifierInfo = struct {
    start: u32,
    end: u32,
    text: []const u8,
};

/// Rename provider
pub const RenameProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RenameProvider {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RenameProvider) void {
        _ = self;
    }

    /// Get rename locations
    pub fn getRenameLocations(self: *const RenameProvider, file: []const u8, pos: u32) []RenameLocation {
        _ = self;
        _ = file;
        _ = pos;
        return &.{};
    }
};

/// Rename location
pub const RenameLocation = struct {
    file: []const u8,
    start: u32,
    length: u32,
};

/// Find references provider
pub const FindReferencesProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FindReferencesProvider {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FindReferencesProvider) void {
        _ = self;
    }

    /// Get references
    pub fn getReferences(self: *const FindReferencesProvider, file: []const u8, pos: u32) []ReferenceEntry {
        _ = self;
        _ = file;
        _ = pos;
        return &.{};
    }
};

/// Reference entry
pub const ReferenceEntry = struct {
    file: []const u8,
    start: u32,
    length: u32,
    is_definition: bool,
    is_in_string: bool,
};
