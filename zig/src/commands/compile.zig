const std = @import("std");
const cli_types = @import("../cli/types.zig");
const compile_parse = @import("./compile/parse.zig");
const compile_execute = @import("./compile/execute.zig");
const compile_render = @import("./compile/render.zig");
const compile_runtime = @import("./compile/runtime.zig");

pub fn run(parsed: *cli_types.ParsedArgs, writer: anytype) !u8 {
    var request = try compile_parse.requestFromParsed(std.heap.page_allocator, parsed);
    defer request.deinit();

    var result = compile_execute.execute(&request);
    const exit_code = try compile_runtime.run(&request, &result, writer);
    if (result.diagnostic != null or result.action == .failed) {
        if (request.flags.graph_json) {
            try writeRejectedGraphJson(writer, &request, &result);
            return exit_code;
        }
        try compile_render.writeResult(writer, result);
    } else {
        if (result.list_files_only or result.native_failed or request.flags.graph_json) {
            return exit_code;
        }
        switch (result.action) {
            .compile, .build, .start_watch => try compile_render.writeResult(writer, result),
            .print_help, .print_version, .init_config, .show_config => {},
            .failed => unreachable,
        }
    }
    return exit_code;
}

fn writeRejectedGraphJson(
    writer: anytype,
    request: *const @import("./compile/types.zig").CompileRequest,
    result: *const @import("./compile/types.zig").CompileResult,
) !void {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    try writer.writeAll("{\"status\":\"error\",\"stage\":\"request\"");
    try writer.writeAll(",\"schemaVersion\":1,\"cwd\":");
    try std.json.encodeJsonString(cwd, .{}, writer);
    try writer.print(",\"exitCode\":{d}", .{result.exit_code});
    try writer.writeAll(",\"action\":\"failed\",\"mode\":");
    try std.json.encodeJsonString(modeLabel(result.mode), .{}, writer);
    try writer.writeAll(",\"config\":");
    try std.json.encodeJsonString(configLabel(result.config_resolution), .{}, writer);
    try writer.writeAll(",\"request\":{");
    try writer.writeAll("\"projectPath\":");
    if (request.project_path) |project_path| {
        try std.json.encodeJsonString(project_path, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"entryFiles\":[");
    for (request.entry_files.items, 0..) |entry_file, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(entry_file, .{}, writer);
    }
    try writer.writeAll("],\"passthrough\":[");
    for (request.passthrough.items, 0..) |arg, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(arg, .{}, writer);
    }
    try writer.writeAll("],\"flags\":{");
    try writer.print(
        "\"help\":{s},\"version\":{s},\"init\":{s},\"showConfig\":{s},\"graphJson\":{s},\"listFilesOnly\":{s},\"ignoreConfig\":{s},\"all\":{s}",
        .{
            if (request.flags.help) "true" else "false",
            if (request.flags.version) "true" else "false",
            if (request.flags.init) "true" else "false",
            if (request.flags.show_config) "true" else "false",
            if (request.flags.graph_json) "true" else "false",
            if (request.flags.list_files_only) "true" else "false",
            if (request.flags.ignore_config) "true" else "false",
            if (request.flags.all) "true" else "false",
        },
    );
    try writer.writeAll("}}");
    try writer.writeAll(",\"roots\":[");
    for (request.entry_files.items, 0..) |root, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(root, .{}, writer);
    }
    try writer.writeAll("],\"sources\":[],\"plan\":null,\"diagnostics\":[{\"message\":");
    try std.json.encodeJsonString(result.diagnostic orelse "Unknown request failure", .{}, writer);
    try writer.writeAll("}],\"source\":null,\"bind\":null,\"check\":null,\"diagnostic\":");
    try std.json.encodeJsonString(result.diagnostic orelse "Unknown request failure", .{}, writer);
    try writer.writeAll("}\n");
}

fn modeLabel(mode: cli_types.CompileMode) []const u8 {
    return switch (mode) {
        .normal => "normal",
        .build => "build",
        .watch => "watch",
    };
}

fn configLabel(config: @import("./compile/types.zig").ConfigResolution) []const u8 {
    return switch (config) {
        .none => "none",
        .explicit_project => "explicit-project",
        .discovered_local_tsconfig => "local-tsconfig",
        .skipped_by_ignore_config => "ignore-config",
    };
}

test "request failure with graphJson ends with request-stage json" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();

    parsed.command = .compile;
    parsed.compile_mode = .normal;
    try parsed.passthrough.appendSlice(&[_][]const u8{
        "--graphJson",
        "--project",
    });

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&parsed, buffer.writer());
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"error\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"schemaVersion\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"cwd\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"request\":{\"projectPath\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"sources\":[]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"plan\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"diagnostics\":[{\"message\":\"Option '--project' expects a path.\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"source\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"bind\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"check\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"diagnostic\":\"Option '--project' expects a path.\"") != null);
}
