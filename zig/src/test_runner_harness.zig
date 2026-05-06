const std = @import("std");
const cli_types = @import("cli/types.zig");
const tsgo = @import("tsgo");
const compile = @import("commands/compile.zig");
const emit = @import("commands/compile/emitter.zig");

pub const HarnessOptions = struct {
    testdata_path: []const u8,
    suite: ?[]const u8 = null,
    limit: ?usize = null,
    strict: bool = false,
};

pub fn parseArgs(args: []const []const u8) !HarnessOptions {
    var opts = HarnessOptions{ .testdata_path = "testdata/tests/cases" };
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--testdata")) {
            i += 1;
            if (i < args.len) opts.testdata_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--suite") and i + 1 < args.len) {
            i += 1;
            opts.suite = args[i];
        } else if (std.mem.eql(u8, args[i], "--limit") and i + 1 < args.len) {
            i += 1;
            opts.limit = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--strict")) {
            opts.strict = true;
        }
    }
    return opts;
}

fn collectTsFiles(allocator: std.mem.Allocator, dir_path: []const u8, suite: ?[]const u8) !std.ArrayList([]const u8) {
    var results = std.ArrayList([]const u8).init(allocator);
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();
    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".ts")) continue;
        if (suite) |s| {
            if (std.mem.indexOf(u8, entry.path, s) == null) continue;
        }
        const full = try std.fs.path.join(allocator, &.{ dir_path, entry.path });
        try results.append(full);
    }
    return results;
}

pub const DiagEntry = struct {
    line: u32,
    code: i32,
    msg: []const u8,
};

fn diagComments(source: []const u8) []DiagEntry {
    var entries = std.ArrayList(DiagEntry).init(std.heap.page_allocator);
    var line_idx: u32 = 0;
    var line_start: usize = 0;
    var i: usize = 0;
    while (i <= source.len) : (i += 1) {
        const is_eol = i == source.len or source[i] == '
' or source[i] == '
';
        if (is_eol) {
            const line = source[line_start..i];
            const marker = "// @ts-error:";
            const marker_idx = std.mem.indexOf(u8, line, marker);
            if (marker_idx) |_| {
                const rest = line[marker_idx.? + marker.len ..];
                var num_end: usize = 0;
                while (num_end < rest.len and rest[num_end] >= '0' and rest[num_end] <= '9') num_end += 1;
                if (num_end > 0) {
                    const code_str = rest[0..num_end];
                    const code = std.fmt.parseInt(i32, code_str, 10) catch 0;
                    const msg = std.mem.trim(u8, rest[num_end..], " 	");
                    try entries.append(DiagEntry{ .line = line_idx, .code = code, .msg = msg });
                }
            }
            line_idx += 1;
            line_start = i + 1;
            if (line_start < source.len and source[line_start - 1] == '
' and source[line_start] == '
') line_start += 1;
        }
    }
    return entries.items;
}

pub fn runCase(allocator: std.mem.Allocator, file_path: []const u8, opts: HarnessOptions) !usize {
    const source = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 512);
    defer allocator.free(source);
    _ = opts;
    _ = allocator;
    std.debug.print("RUN {s}
", .{file_path});
    return 0;
}

pub fn run(allocator: std.mem.Allocator, opts: HarnessOptions) !usize {
    var files = try collectTsFiles(allocator, opts.testdata_path, opts.suite);
    defer {
        for (files.items) |f| allocator.free(f);
        files.deinit();
    }
    std.debug.print("Found {d} test files
", .{files.items.len});
    var failed: usize = 0;
    var executed: usize = 0;
    for (files.items) |file_path| {
        if (opts.limit) |lim| {
            if (executed >= lim) break;
        }
        const result = runCase(allocator, file_path, opts) catch {
            std.debug.print("ERROR {s}: failed
", .{file_path});
            failed += 1;
            executed += 1;
            continue;
        };
        if (result != 0) failed += 1;
        executed += 1;
    }
    std.debug.print("Executed: {d}, Failed: {d}
", .{executed, failed});
    return failed;
}
