const std = @import("std");
const compile_execute = @import("./commands/compile/execute.zig");
const types = @import("./commands/compile/types.zig");

pub const RunnerOptions = struct {
    mode: enum { smoke, testdata } = .testdata,
    suite: ?[]const u8 = null,
    filter: ?[]const u8 = null,
    limit: ?usize = null,
    strict: bool = false,
};

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const owned_args = std.process.argsAlloc(allocator) catch {
        std.debug.print("error: failed to alloc args\n", .{});
        std.process.exit(1);
    };
    defer std.process.argsFree(allocator, owned_args);
    const args = owned_args[1..];

    const exit_code = runTestdata(allocator, args) catch {
        std.debug.print("error: failed to run testdata harness\n", .{});
        std.process.exit(1);
    };
    std.process.exit(exit_code);
}

fn parseArgs(args: []const []const u8) RunnerOptions {
    var opts = RunnerOptions{};
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--smoke")) {
            opts.mode = .smoke;
        } else if (std.mem.eql(u8, arg, "--testdata")) {
            opts.mode = .testdata;
        } else if (std.mem.startsWith(u8, arg, "--suite=")) {
            opts.suite = arg["--suite=".len..];
        } else if (std.mem.startsWith(u8, arg, "--filter=")) {
            opts.filter = arg["--filter=".len..];
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            const num_str = arg["--limit=".len..];
            opts.limit = std.fmt.parseInt(usize, num_str, 10) catch null;
        } else if (std.mem.eql(u8, arg, "--strict")) {
            opts.strict = true;
        }
    }
    return opts;
}

fn runTestdata(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    const opts = parseArgs(args);

    return switch (opts.mode) {
        .smoke => runSmokeTests(allocator),
        .testdata => runTestdataTests(allocator, opts),
    };
}

fn runSmokeTests(allocator: std.mem.Allocator) u8 {
    _ = allocator;
    std.debug.print("Running smoke tests...\n", .{});
    return 0;
}

const TestResult = union(enum) {
    passed: void,
    failed: []const u8,
    skipped: void,
};

fn runTestdataTests(allocator: std.mem.Allocator, opts: RunnerOptions) u8 {
    const base_path = std.fs.path.join(allocator, &.{ "testdata", "tests", "cases" }) catch {
        std.debug.print("ERROR: could not build path\n", .{});
        return 1;
    };
    defer allocator.free(base_path);

    var cases = std.ArrayList([]const u8).init(allocator);
    defer {
        for (cases.items) |c| allocator.free(c);
        cases.deinit();
    }

    walkTestDir(allocator, &cases, base_path, opts.filter);

    std.debug.print("Found {d} test cases\n", .{cases.items.len});

    const limit = opts.limit orelse cases.items.len;
    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;

    for (cases.items[0..limit], 0..) |case_path, idx| {
        const result = runSingleTest(allocator, case_path, opts.strict);
        switch (result) {
            .passed => {
                std.debug.print("  PASS {s}\n", .{std.fs.path.basename(case_path)});
                passed += 1;
            },
            .failed => |msg| {
                std.debug.print("  FAIL {s}: {s}\n", .{ std.fs.path.basename(case_path), msg });
                failed += 1;
            },
            .skipped => {
                skipped += 1;
            },
        }
        if (idx > 0 and (idx + 1) % 50 == 0) {
            std.debug.print("  progress: {d}/{d}  pass={d} fail={d}\n", .{ idx + 1, limit, passed, failed });
        }
    }

    std.debug.print("Results: {d} passed, {d} failed, {d} skipped\n", .{ passed, failed, skipped });
    return if (failed > 0) 1 else 0;
}

fn walkTestDir(allocator: std.mem.Allocator, cases: *std.ArrayList([]const u8), dir_path: []const u8, filter: ?[]const u8) void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".ts")) continue;
        if (std.mem.endsWith(u8, entry.name, ".d.ts")) continue;

        const full_path = std.fs.path.join(allocator, &.{ dir_path, entry.name }) catch continue;
        if (filter) |f| {
            if (std.mem.indexOf(u8, entry.name, f) == null) {
                allocator.free(full_path);
                continue;
            }
        }
        cases.append(full_path) catch {
            allocator.free(full_path);
            continue;
        };
    }
}

fn runSingleTest(allocator: std.mem.Allocator, case_path: []const u8, strict: bool) TestResult {
    const src_text = std.fs.cwd().readFileAlloc(allocator, case_path, 1 << 20) catch return .{ .failed = "read file failed" };
    defer allocator.free(src_text);

    const expected_count = extractExpectedErrors(src_text);

    var request = types.CompileRequest.init(allocator, .normal);
    defer request.deinit();

    request.entry_files.clearAndFree();
    request.entry_files.append(case_path) catch return .{ .failed = "OOM" };

    const result = compile_execute.execute(&request);

    if (strict) {
        if (result.exit_code == 0 and expected_count > 0) {
            return .{ .failed = "expected errors but compilation succeeded" };
        }
        if (result.exit_code != 0 and expected_count == 0) {
            const diag = result.diagnostic orelse "unknown error";
            return .{ .failed = diag };
        }
        return .{ .passed = {} };
    } else {
        if (result.diagnostic != null) {
            return .{ .failed = result.diagnostic.? };
        }
        return .{ .passed = {} };
    }
}

fn extractExpectedErrors(text: []const u8) usize {
    var count: usize = 0;
    var iter = std.mem.tokenizeAny(u8, text, "\n");
    while (iter.next()) |line| {
        if (std.mem.indexOf(u8, line, "@expected-error:") != null) {
            count += 1;
        }
    }
    return count;
}
