const std = @import("std");

/// Language service host interface
pub const LanguageServiceHost = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LanguageServiceHost {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LanguageServiceHost) void {
        _ = self;
    }

    /// Get compiler options
    pub fn getCompilerOptions(self: *const LanguageServiceHost) *anyopaque {
        _ = self;
        return undefined;
    }

    /// Get current directory
    pub fn getCurrentDirectory(self: *const LanguageServiceHost) []const u8 {
        _ = self;
        return "";
    }

    /// Get default library file name
    pub fn getDefaultLibFileName(self: *const LanguageServiceHost) []const u8 {
        _ = self;
        return "lib.d.ts";
    }

    /// Log a message
    pub fn log(self: *const LanguageServiceHost, message: []const u8) void {
        std.debug.print("{s}
", .{message});
    }
};

/// Language service
pub const LanguageService = struct {
    allocator: std.mem.Allocator,
    host: *LanguageServiceHost,

    pub fn init(allocator: std.mem.Allocator, host: *LanguageServiceHost) LanguageService {
        return .{
            .allocator = allocator,
            .host = host,
        };
    }

    pub fn deinit(self: *LanguageService) void {
        _ = self;
    }

    /// Get syntactic diagnostics
    pub fn getSyntacticDiagnostics(self: *const LanguageService, file_name: []const u8) []const u8 {
        _ = self;
        _ = file_name;
        return &.{};
    }

    /// Get semantic diagnostics
    pub fn getSemanticDiagnostics(self: *const LanguageService, file_name: []const u8) []const u8 {
        _ = self;
        _ = file_name;
        return &.{};
    }

    /// Get suggestion diagnostics
    pub fn getSuggestionDiagnostics(self: *const LanguageService, file_name: []const u8) []const u8 {
        _ = self;
        _ = file_name;
        return &.{};
    }
};
