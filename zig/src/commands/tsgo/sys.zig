const std = @import("std");
const builtin = @import("builtin");

/// System interface providing access to filesystem, environment, and I/O
pub const System = struct {
    writer: std.io.AnyWriter,
    fs: std.fs.FileSystem,
    default_library_path: []const u8,
    cwd: []const u8,
    start_time: std.time.Instant,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !System {
        const cwd = try std.process.cwdAlloc(allocator);
        errdefer allocator.free(cwd);

        const now = std.time.Instant.now();

        // TODO: Get default library path from bundled resources
        const default_library_path = try allocator.dupe(u8, "");
        errdefer allocator.free(default_library_path);

        return System{
            .writer = std.io.getStdOut().writer().any(),
            .fs = std.fs.cwd(),
            .default_library_path = default_library_path,
            .cwd = cwd,
            .start_time = now,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *System) void {
        self.allocator.free(self.cwd);
        self.allocator.free(self.default_library_path);
    }

    pub fn sinceStart(self: *const System) std.time.Instant.Duration {
        return self.start_time.since();
    }

    pub fn now(self: *const System) std.time.Instant {
        return std.time.Instant.now();
    }

    pub fn fsReader(self: *const System) std.fs.File.Reader {
        _ = self;
        return std.io.getStdIn().reader();
    }

    pub fn fsWriter(self: *const System) std.fs.File.Writer {
        return std.io.getStdOut().writer();
    }

    pub fn getCurrentDirectory(self: *const System) []const u8 {
        return self.cwd;
    }

    pub fn getEnvironmentVariable(self: *const System, name: []const u8) ?[]const u8 {
        return std.process.getEnvVarOwned(self.allocator, name) catch return null;
    }

    pub fn isOutputTTY(self: *const System) bool {
        return std.io.isTty(std.io.getStdOut());
    }

    pub fn getTerminalWidth(self: *const System) usize {
        return @min(std.io.getStdOut().handle.getWakeableFd() catch return 80, 80);
    }

    pub fn readFile(self: *const System, path: []const u8) ?[]const u8 {
        const file = self.fs.openFile(path, .{}) catch return null;
        defer file.close();
        return file.readAllAlloc(self.allocator, std.math.maxInt(usize)) catch return null;
    }

    pub fn fileExists(self: *const System, path: []const u8) bool {
        return self.fs.accessable(path, .{});
    }

    pub fn directoryExists(self: *const System, path: []const u8) bool {
        return self.fs.statDir(path);
    }

    pub fn writeFile(self: *const System, path: []const u8, contents: []const u8) !void {
        const file = try self.fs.createFile(path, .{});
        defer file.close();
        try file.writeAll(contents);
    }

    pub fn exit(self: *const System, code: u8) noreturn {
        std.process.exit(code);
    }
};

/// Exit status codes matching TypeScript's tsc exit codes
pub const ExitStatus = enum(u8) {
    success = 0,
    diagnostics_present_outputs_skipped = 1,
    diagnostics_present_outputs_generated = 2,
    invalid_project_outputs_skipped = 3,
    cannot_read_file = 4,
    not_implemented = 5,
    exit_status_diagnostics_present_outputs_skipped = 6,
};
