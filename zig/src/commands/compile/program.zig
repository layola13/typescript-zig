const std = @import("std");
const tsoptions = @import("tsoptions.zig");
const source = @import("source_file.zig");
const diagnostics = @import("diagnostics.zig");

/// Program represents a TypeScript compilation unit
pub const Program = struct {
    allocator: std.mem.Allocator,
    config: *const tsoptions.ParsedCommandLine,
    host: *const CompilerHost,
    source_files: []source.SourceFile,
    checker: ?*anyopaque = null, // Placeholder for type checker

    pub fn init(allocator: std.mem.Allocator, config: *const tsoptions.ParsedCommandLine, host: *const CompilerHost) !Program {
        return Program{
            .allocator = allocator,
            .config = config,
            .host = host,
            .source_files = &.{},
        };
    }

    pub fn deinit(self: *Program) void {
        for (self.source_files) |file| {
            self.allocator.free(file.filename);
            self.allocator.free(file.text);
        }
        self.allocator.free(self.source_files);
    }

    /// Get a source file by filename
    pub fn getSourceFile(self: *const Program, filename: []const u8) ?*const source.SourceFile {
        for (self.source_files) |*file| {
            if (std.mem.eql(u8, file.filename, filename)) return file;
        }
        return null;
    }

    /// Get compiler options
    pub fn getCompilerOptions(self: *const Program) tsoptions.CompilerOptions {
        return self.config.options;
    }

    /// Get type checker (placeholder)
    pub fn getTypeChecker(self: *Program) *anyopaque {
        return self.checker orelse unreachable;
    }
};

/// Compiler host interface
pub const CompilerHost = struct {
    allocator: std.mem.Allocator,
    loader: source.SourceFileLoader,

    pub fn init(allocator: std.mem.Allocator) CompilerHost {
        return .{
            .allocator = allocator,
            .loader = source.SourceFileLoader.init(allocator),
        };
    }

    pub fn deinit(self: *CompilerHost) void {
        self.loader.deinit();
    }

    /// Get default library path
    pub fn getDefaultLibraryPath(self: *const CompilerHost) []const u8 {
        _ = self;
        return "lib";
    }

    /// Load a source file
    pub fn getSourceFile(self: *CompilerHost, filename: []const u8) !source.SourceFile {
        return try self.loader.loadFile(filename);
    }

    /// Check if file exists
    pub fn fileExists(self: *const CompilerHost, filename: []const u8) bool {
        return std.fs.cwd().accessable(filename, .{});
    }

    /// Get current directory
    pub fn getCurrentDirectory(self: *const CompilerHost) []const u8 {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.process.getCwd(&buf) catch return "";
        return path;
    }

    /// Get canonical file name
    pub fn getCanonicalFileName(self: *const CompilerHost, filename: []const u8) []const u8 {
        _ = self;
        return filename;
    }
};

/// Create a new program
pub fn createProgram(allocator: std.mem.Allocator, config: *const tsoptions.ParsedCommandLine, host: *CompilerHost) !Program {
    var program = try Program.init(allocator, config, host);

    // Load all file names from config
    for (config.file_names) |filename| {
        const file = try host.getSourceFile(filename);
        try program.source_files.append(file);
    }

    return program;
}
