const std = @import("std");

/// Services container
pub const Services = struct {
    allocator: std.mem.Allocator,
    language_service: ?*LanguageService,
    compiler_host: ?*CompilerHost,

    pub fn init(allocator: std.mem.Allocator) Services {
        return .{ .allocator = allocator, .language_service = null, .compiler_host = null };
    }

    pub fn deinit(self: *Services) void {
        _ = self;
    }
};

/// Language service stub
pub const LanguageService = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LanguageService {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LanguageService) void {
        _ = self;
    }
};

/// Compiler host stub
pub const CompilerHost = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CompilerHost {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CompilerHost) void {
        _ = self;
    }
};
