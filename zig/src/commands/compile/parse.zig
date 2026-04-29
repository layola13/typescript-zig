const std = @import("std");
const cli_types = @import("../../cli/types.zig");
const types = @import("./types.zig");

pub fn requestFromParsed(
    allocator: std.mem.Allocator,
    parsed: *const cli_types.ParsedArgs,
) !types.CompileRequest {
    var request = types.CompileRequest.init(allocator, parsed.compile_mode);
    errdefer request.deinit();

    var consume_next_as_project = false;
    var consume_next_as_outdir = false;
    var consume_next_as_tsconfig = false;

    for (parsed.passthrough.items) |arg| {
        try request.passthrough.append(arg);

        if (consume_next_as_project) {
            request.project_path = arg;
            consume_next_as_project = false;
            continue;
        }

        if (consume_next_as_outdir) {
            request.flags.out_dir = arg;
            consume_next_as_outdir = false;
            continue;
        }

        if (consume_next_as_tsconfig) {
            request.flags.tsconfig_path = arg;
            consume_next_as_tsconfig = false;
            continue;
        }

        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--project")) {
            consume_next_as_project = true;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--project=")) {
            request.project_path = arg["--project=".len..];
            continue;
        }

        if (std.mem.eql(u8, arg, "--tsconfig") or std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            consume_next_as_tsconfig = true;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--tsconfig=")) {
            request.flags.tsconfig_path = arg["--config=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--config=")) {
            request.flags.tsconfig_path = arg["--config=".len..];
            continue;
        }

        if (std.mem.eql(u8, arg, "--outDir") or std.mem.eql(u8, arg, "-d")) {
            consume_next_as_outdir = true;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--outDir=")) {
            request.flags.out_dir = arg["--outDir=".len..];
            continue;
        }

        updateFlags(&request.flags, arg);

        if (!std.mem.startsWith(u8, arg, "-")) {
            try request.entry_files.append(arg);
        }
    }

    if (consume_next_as_project) {
        request.missing_project_value = true;
    }

    return request;
}

fn updateFlags(flags: *types.CompileFlags, arg: []const u8) void {
    if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
        flags.help = true;
    } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
        flags.version = true;
    } else if (std.mem.eql(u8, arg, "--init")) {
        flags.init = true;
    } else if (std.mem.eql(u8, arg, "--showConfig")) {
        flags.show_config = true;
    } else if (std.mem.eql(u8, arg, "--graphJson")) {
        flags.graph_json = true;
    } else if (std.mem.eql(u8, arg, "--listFilesOnly")) {
        flags.list_files_only = true;
    } else if (std.mem.eql(u8, arg, "--ignoreConfig")) {
        flags.ignore_config = true;
    } else if (std.mem.eql(u8, arg, "--all")) {
        flags.all = true;
    }
}

test "build compile request with explicit project" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();

    parsed.command = .compile;
    parsed.compile_mode = .normal;
    try parsed.passthrough.appendSlice(&[_][]const u8{
        "-p",
        "configs/tsconfig.json",
        "--showConfig",
    });

    var request = try requestFromParsed(std.testing.allocator, &parsed);
    defer request.deinit();

    try std.testing.expectEqualStrings("configs/tsconfig.json", request.project_path.?);
    try std.testing.expect(request.flags.show_config);
    try std.testing.expectEqual(@as(usize, 0), request.entry_files.items.len);
}

test "track graph json flag" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();

    parsed.command = .compile;
    parsed.compile_mode = .normal;
    try parsed.passthrough.appendSlice(&[_][]const u8{
        "--graphJson",
    });

    var request = try requestFromParsed(std.testing.allocator, &parsed);
    defer request.deinit();

    try std.testing.expect(request.flags.graph_json);
}

test "track positional inputs as entry files" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();

    parsed.command = .compile;
    parsed.compile_mode = .watch;
    try parsed.passthrough.appendSlice(&[_][]const u8{
        "--watch",
        "src/index.ts",
        "src/cli.ts",
    });

    var request = try requestFromParsed(std.testing.allocator, &parsed);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 2), request.entry_files.items.len);
    try std.testing.expectEqualStrings("src/index.ts", request.entry_files.items[0]);
    try std.testing.expectEqualStrings("src/cli.ts", request.entry_files.items[1]);
}

// Add tsconfig support to existing parse.zig
// We need to add --tsconfig handling in requestFromParsed
