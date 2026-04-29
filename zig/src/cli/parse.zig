const std = @import("std");
const types = @import("./types.zig");

pub fn parseArgsSlice(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !types.ParsedArgs {
    var parsed = types.ParsedArgs.init(allocator);
    errdefer parsed.deinit();

    const first = if (argv.len > 0) argv[0] else null;
    const first_arg = first orelse {
        parsed.command = .help;
        return parsed;
    };

    if (isFlag(first_arg, "--version", "-v")) {
        parsed.command = .version;
        return parsed;
    }

    if (isFlag(first_arg, "--help", "-h")) {
        parsed.command = .help;
        return parsed;
    }

    if (std.mem.eql(u8, first_arg, "--lsp") or std.mem.eql(u8, first_arg, "lsp")) {
        parsed.command = .lsp;
        for (argv[1..]) |arg| {
            try parsed.passthrough.append(arg);
        }
        return parsed;
    }

    if (std.mem.eql(u8, first_arg, "--api") or std.mem.eql(u8, first_arg, "api")) {
        parsed.command = .api;
        for (argv[1..]) |arg| {
            try parsed.passthrough.append(arg);
        }
        return parsed;
    }

    parsed.command = .compile;
    var start_index: usize = 0;
    if (std.mem.eql(u8, first_arg, "compile")) {
        start_index = 1;
    } else {
        try parsed.passthrough.append(first_arg);
        updateCompileMode(&parsed, first_arg);
        start_index = 1;
    }

    for (argv[start_index..]) |arg| {
        try parsed.passthrough.append(arg);
        updateCompileMode(&parsed, arg);
    }

    return parsed;
}

fn updateCompileMode(parsed: *types.ParsedArgs, arg: []const u8) void {
    if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--build")) {
        parsed.compile_mode = .build;
    }
    if (std.mem.eql(u8, arg, "-w") or
        std.mem.eql(u8, arg, "--watch") or
        std.mem.eql(u8, arg, "--w") or
        std.mem.eql(u8, arg, "-watch"))
    {
        parsed.compile_mode = .watch;
    }
}

fn isFlag(value: []const u8, long: []const u8, short: []const u8) bool {
    return std.mem.eql(u8, value, long) or std.mem.eql(u8, value, short);
}

test "parse version and help commands" {
    const no_args = [_][]const u8{};
    var parsed_help = try parseArgsSlice(std.testing.allocator, no_args[0..]);
    defer parsed_help.deinit();
    try std.testing.expectEqual(types.Command.help, parsed_help.command);

    const version_args = [_][]const u8{"--version"};
    var parsed_version = try parseArgsSlice(std.testing.allocator, version_args[0..]);
    defer parsed_version.deinit();
    try std.testing.expectEqual(types.Command.version, parsed_version.command);
}

test "parse compile command and modes" {
    const compile_args = [_][]const u8{ "compile", "-b", "src/index.ts" };
    var parsed_build = try parseArgsSlice(std.testing.allocator, compile_args[0..]);
    defer parsed_build.deinit();
    try std.testing.expectEqual(types.Command.compile, parsed_build.command);
    try std.testing.expectEqual(types.CompileMode.build, parsed_build.compile_mode);
    try std.testing.expectEqual(@as(usize, 2), parsed_build.passthrough.items.len);

    const implicit_args = [_][]const u8{ "--watch", "src/index.ts" };
    var parsed_watch = try parseArgsSlice(std.testing.allocator, implicit_args[0..]);
    defer parsed_watch.deinit();
    try std.testing.expectEqual(types.Command.compile, parsed_watch.command);
    try std.testing.expectEqual(types.CompileMode.watch, parsed_watch.compile_mode);
}

test "parse lsp and api aliases" {
    const lsp_args = [_][]const u8{ "--lsp", "--stdio", "--graphJson" };
    var parsed_lsp = try parseArgsSlice(std.testing.allocator, lsp_args[0..]);
    defer parsed_lsp.deinit();
    try std.testing.expectEqual(types.Command.lsp, parsed_lsp.command);
    try std.testing.expectEqual(@as(usize, 2), parsed_lsp.passthrough.items.len);
    try std.testing.expectEqualStrings("--stdio", parsed_lsp.passthrough.items[0]);
    try std.testing.expectEqualStrings("--graphJson", parsed_lsp.passthrough.items[1]);

    const api_args = [_][]const u8{ "api", "--socket", "demo.sock" };
    var parsed_api = try parseArgsSlice(std.testing.allocator, api_args[0..]);
    defer parsed_api.deinit();
    try std.testing.expectEqual(types.Command.api, parsed_api.command);
    try std.testing.expectEqual(@as(usize, 2), parsed_api.passthrough.items.len);
    try std.testing.expectEqualStrings("--socket", parsed_api.passthrough.items[0]);
    try std.testing.expectEqualStrings("demo.sock", parsed_api.passthrough.items[1]);
}
