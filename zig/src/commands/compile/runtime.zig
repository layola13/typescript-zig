const std = @import("std");
const cli_help = @import("../../cli/help.zig");
const version_info = @import("../../version.zig");
const types = @import("./types.zig");
const Action = types.Action;
const Mode = types.Mode;
const config = @import("./config.zig");
const plan = @import("./plan.zig");
const source = @import("./source.zig");
const binder = @import("./binder.zig");
const checker = @import("./checker.zig");
const emitter = @import("./emitter.zig");

pub fn run(request: *const types.CompileRequest, result: *types.CompileResult, writer: anytype) !u8 {
    if (result.diagnostic != null) {
        return result.exit_code;
    }

    return switch (result.action) {
        .print_help => try runHelp(request, result, writer),
        .print_version => try runVersion(request, result, writer),
        .show_config => try runShowConfig(request, result, writer),
        .init_config => try runInit(request, result, writer),
        .start_watch, .build, .compile => try runCompileLike(request, result, writer),
        .failed => result.exit_code,
    };
}

fn runHelp(request: *const types.CompileRequest, result: *types.CompileResult, writer: anytype) !u8 {
    if (request.flags.graph_json) {
        try writeActionGraphJson(writer, request, result, "help", null, null, cli_help.text);
        return result.exit_code;
    }
    try writer.writeAll(cli_help.text);
    return result.exit_code;
}

fn runVersion(request: *const types.CompileRequest, result: *types.CompileResult, writer: anytype) !u8 {
    if (request.flags.graph_json) {
        try writeActionGraphJson(writer, request, result, "version", null, null, version_info.value);
        return result.exit_code;
    }
    try writer.print("zts {s}\n", .{version_info.value});
    return result.exit_code;
}

fn runShowConfig(request: *const types.CompileRequest, result: *types.CompileResult, writer: anytype) !u8 {
    const config_path = result.resolved_config_path orelse {
        if (request.flags.graph_json) {
            result.exit_code = 1;
            try writeActionGraphJson(writer, request, result, "show-config", "Cannot find a tsconfig.json file for '--showConfig'.", null, null);
            return result.exit_code;
        }
        result.exit_code = 1;
        result.diagnostic = types.Diagnostic{ .severity = .@"error", .error_code = 0, .message = "Cannot find a tsconfig.json file for '--showConfig'." };
        return result.exit_code;
    };

    const content = try config.readConfig(std.heap.page_allocator, config_path);
    defer std.heap.page_allocator.free(content);

    if (request.flags.graph_json) {
        try writeActionGraphJson(writer, request, result, "show-config", null, config_path, content);
        return 0;
    }
    try writer.print("{s}\n", .{content});
    return 0;
}

fn runInit(request: *const types.CompileRequest, result: *types.CompileResult, writer: anytype) !u8 {
    const output_path = "tsconfig.json";

    if (std.fs.cwd().access(output_path, .{})) |_| {
        if (request.flags.graph_json) {
            result.exit_code = 1;
            try writeActionGraphJson(writer, request, result, "init", "A tsconfig.json file is already defined in the current directory.", output_path, null);
            return result.exit_code;
        }
        result.exit_code = 1;
        result.diagnostic = types.Diagnostic{ .severity = .@"error", .error_code = 0, .message = "A tsconfig.json file is already defined in the current directory." };
        return result.exit_code;
    } else |_| {}

    try config.writeInitConfig(output_path);
    if (request.flags.graph_json) {
        try writeActionGraphJson(writer, request, result, "init", null, output_path, null);
        return 0;
    }
    try writer.writeAll("Created a new tsconfig.json\n");
    return 0;
}

fn runCompileLike(request: *const types.CompileRequest, result: *types.CompileResult, writer: anytype) !u8 {
    var native_plan = try plan.buildPlan(std.heap.page_allocator, request, result);
    defer native_plan.deinit(std.heap.page_allocator);
    if (!request.flags.graph_json) {
        try plan.writePlan(writer, request, result, &native_plan);
    }
    if (request.flags.list_files_only) {
        if (request.flags.graph_json) {
            try writeListFilesGraphJson(writer, request, result, &native_plan);
            return 0;
        }
        return writeListFilesOnly(writer, &native_plan);
    }

    var source_summary = try source.loadSources(std.heap.page_allocator, &native_plan);
    defer source_summary.deinit(std.heap.page_allocator);
    if (!request.flags.graph_json) {
        try source.writeSummary(writer, &native_plan, &source_summary);
    }
    if (source_summary.diagnostics.items.len > 0) {
        result.exit_code = 1;
        result.native_failed = true;
        if (request.flags.graph_json) {
            try writeSourceRuntimeGraphJson(writer, request, result, &native_plan, &source_summary);
        }
        return result.exit_code;
    }

    var bind_summary = try binder.bindProgram(std.heap.page_allocator, &source_summary);
    defer bind_summary.deinit(std.heap.page_allocator);
    if (!request.flags.graph_json) {
        try binder.writeSummary(writer, &bind_summary);
    }
    if (bind_summary.diagnostics.items.len > 0) {
        result.exit_code = 1;
        result.native_failed = true;
        if (request.flags.graph_json) {
            try writeBindRuntimeGraphJson(writer, request, result, &native_plan, &bind_summary);
        }
        return result.exit_code;
    }

    var check_summary = try checker.checkProgram(std.heap.page_allocator, &native_plan, &source_summary, &bind_summary);
    defer check_summary.deinit(std.heap.page_allocator);
    if (!request.flags.graph_json) {
        try checker.writeSummary(writer, &check_summary);
    }
    if (check_summary.diagnostics.items.len > 0) {
        result.exit_code = 1;
        result.native_failed = true;
    }
    if (request.flags.graph_json) {
        try writeRuntimeGraphJson(writer, request, result, &native_plan, &source_summary, &bind_summary, &check_summary);
        return if (check_summary.diagnostics.items.len > 0) 1 else 0;
    }

    // Continue to emit even with unresolved diagnostics
    // so partial output is generated for IDE feedback

    return try runEmit(request, result, writer, &native_plan, &source_summary);
}

fn runEmit(
    request: *const types.CompileRequest,
    result: *types.CompileResult,
    writer: anytype,
    native_plan: *const plan.CompilePlan,
    source_summary: *const source.SourceLoadSummary,
) !u8 {
    try writer.print("zts-debug: runtime out_dir={s} root_dir={s} config_dir={s}\n", .{
    native_plan.out_dir orelse "null",
    native_plan.root_dir orelse "null", 
    native_plan.config_dir orelse "null",
});

var emit_result = try emitter.emitProgram(
        std.heap.page_allocator,
        source_summary,
        .{ .emit_js = true, .emit_declarations = true, .out_dir = request.flags.out_dir orelse native_plan.out_dir, .root_dir = native_plan.root_dir, .config_dir = native_plan.config_dir },
    );
    defer emit_result.deinit();

    if (result.exit_code == 0) result.exit_code = emit_result.exit_code;

    if (emit_result.diagnostics.items.len > 0) {
        for (emit_result.diagnostics.items) |diag| {
            try writer.print("zts: emit error: {s}: {s}\n", .{ diag.path, diag.message });
        }
    }

    try emitter.writeEmitResult(writer, &emit_result);

    return result.exit_code;
}

fn writeListFilesOnly(writer: anytype, native_plan: *const plan.CompilePlan) !u8 {
    for (native_plan.discovered_sources.items) |source_path| {
        try writer.print("{s}\n", .{source_path});
    }
    return 0;
}

fn writeActionGraphJson(
    writer: anytype,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
    stage: []const u8,
    diagnostic: ?[]const u8,
    path: ?[]const u8,
    content: ?[]const u8,
) !void {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    try writer.writeAll("{\"status\":");
    try std.json.encodeJsonString(if (result.exit_code == 0) "ok" else "error", .{}, writer);
    try writer.writeAll(",\"schemaVersion\":1,\"cwd\":");
    try std.json.encodeJsonString(cwd, .{}, writer);
    try writer.print(",\"exitCode\":{d}", .{result.exit_code});
    try writer.writeAll(",\"stage\":");
    try std.json.encodeJsonString(stage, .{}, writer);
    try writer.writeAll(",\"action\":");
    try std.json.encodeJsonString(actionLabel(result.action), .{}, writer);
    try writer.writeAll(",\"mode\":");
    try std.json.encodeJsonString(modeLabel(request.mode), .{}, writer);
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
    try writer.writeAll("}},\"roots\":[],\"sources\":[],\"plan\":null,\"diagnostics\":[");
    if (diagnostic) |message| {
        try writer.writeAll("{\"message\":");
        try std.json.encodeJsonString(message, .{}, writer);
        try writer.writeAll("}");
    }
    try writer.writeAll("],\"source\":null,\"bind\":null,\"check\":null,\"path\":");
    if (path) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"content\":");
    if (content) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    if (diagnostic) |message| {
        try writer.writeAll(",\"diagnostic\":");
        try std.json.encodeJsonString(message, .{}, writer);
    }
    try writer.writeAll("}\n");
}

fn writeListFilesGraphJson(
    writer: anytype,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
    native_plan: *const plan.CompilePlan,
) !void {
    try writeRuntimeJsonPrefix(writer, request, result, native_plan, "list-files");
    try writer.writeAll(",\"diagnostics\":[],\"source\":null,\"bind\":null,\"check\":null}\n");
}

fn writeRuntimeGraphJson(
    writer: anytype,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
    native_plan: *const plan.CompilePlan,
    source_summary: *const source.SourceLoadSummary,
    bind_summary: *const binder.BindSummary,
    check_summary: *const checker.CheckSummary,
) !void {
    try writeRuntimeJsonPrefix(writer, request, result, native_plan, "check");
    try writer.writeAll(",\"diagnostics\":");
    try writeCheckDiagnosticsJson(writer, check_summary);
    try writer.writeAll(",\"source\":");
    try writeSourceSummaryJson(writer, source_summary);
    try writer.writeAll(",\"bind\":");
    try writeBindSummaryJson(writer, bind_summary);
    try writer.writeAll(",\"check\":");
    try checker.writeGraphJsonPayload(writer, check_summary);
    try writer.writeAll("}\n");
}

fn writeRuntimeJsonPrefix(
    writer: anytype,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
    native_plan: *const plan.CompilePlan,
    stage: []const u8,
) !void {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    try writer.writeAll("{\"status\":");
    try std.json.encodeJsonString(if (result.exit_code == 0) "ok" else "error", .{}, writer);
    try writer.writeAll(",\"schemaVersion\":1,\"cwd\":");
    try std.json.encodeJsonString(cwd, .{}, writer);
    try writer.print(",\"exitCode\":{d}", .{result.exit_code});
    try writer.writeAll(",\"stage\":");
    try std.json.encodeJsonString(stage, .{}, writer);
    try writer.writeAll(",\"action\":");
    try std.json.encodeJsonString(actionLabel(result.action), .{}, writer);
    try writer.writeAll(",\"mode\":");
    try std.json.encodeJsonString(modeLabel(request.mode), .{}, writer);
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
    for (native_plan.cli_entry_files.items, 0..) |root, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(root, .{}, writer);
    }
    try writer.writeAll("],\"sources\":[");
    for (native_plan.discovered_sources.items, 0..) |source_path, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(source_path, .{}, writer);
    }
    try writer.writeAll("],\"plan\":{");
    try writer.writeAll("\"configPath\":");
    if (native_plan.config_path) |config_path| {
        try std.json.encodeJsonString(config_path, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"configDir\":");
    if (native_plan.config_dir) |config_dir| {
        try std.json.encodeJsonString(config_dir, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"rootDir\":");
    if (native_plan.root_dir) |root_dir| {
        try std.json.encodeJsonString(root_dir, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"outDir\":");
    if (native_plan.out_dir) |out_dir| {
        try std.json.encodeJsonString(out_dir, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"module\":");
    if (native_plan.module_name) |module_name| {
        try std.json.encodeJsonString(module_name, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"target\":");
    if (native_plan.target_name) |target_name| {
        try std.json.encodeJsonString(target_name, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"baseUrl\":");
    if (native_plan.base_url) |base_url| {
        try std.json.encodeJsonString(base_url, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"extends\":");
    if (native_plan.extends_path) |extends_path| {
        try std.json.encodeJsonString(extends_path, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"pathMappings\":[");
    for (native_plan.path_mappings.items, 0..) |mapping, mapping_index| {
        if (mapping_index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"pattern\":");
        try std.json.encodeJsonString(mapping.pattern, .{}, writer);
        try writer.writeAll(",\"targets\":[");
        for (mapping.targets.items, 0..) |target, target_index| {
            if (target_index > 0) try writer.writeAll(",");
            try std.json.encodeJsonString(target, .{}, writer);
        }
        try writer.writeAll("]}");
    }
    try writer.writeAll("],\"includePatterns\":[");
    for (native_plan.include_patterns.items, 0..) |pattern, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(pattern, .{}, writer);
    }
    try writer.writeAll("],\"explicitFiles\":[");
    for (native_plan.explicit_files.items, 0..) |file, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(file, .{}, writer);
    }
    try writer.writeAll("]}");
}

fn writeSourceRuntimeGraphJson(
    writer: anytype,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
    native_plan: *const plan.CompilePlan,
    source_summary: *const source.SourceLoadSummary,
) !void {
    try writeRuntimeJsonPrefix(writer, request, result, native_plan, "source");
    try writer.writeAll(",\"diagnostics\":");
    try writeSourceDiagnosticsJson(writer, source_summary.diagnostics.items);
    try writer.writeAll(",\"source\":");
    try writeSourceSummaryJson(writer, source_summary);
    try writer.writeAll(",\"bind\":null,\"check\":null}\n");
}

fn writeBindRuntimeGraphJson(
    writer: anytype,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
    native_plan: *const plan.CompilePlan,
    bind_summary: *const binder.BindSummary,
) !void {
    try writeRuntimeJsonPrefix(writer, request, result, native_plan, "bind");
    try writer.writeAll(",\"diagnostics\":");
    try writeBindDiagnosticsJson(writer, bind_summary.diagnostics.items);
    try writer.writeAll(",\"source\":null,\"bind\":");
    try writeBindSummaryJson(writer, bind_summary);
    try writer.writeAll(",\"check\":null}\n");
}

fn writeSourceSummaryJson(writer: anytype, source_summary: *const source.SourceLoadSummary) !void {
    try writer.print(
        "{{\"loaded\":{d},\"bytes\":{d},\"tokens\":{d},\"imports\":{d},\"exports\":{d},\"functions\":{d},\"classes\":{d}}}",
        .{
            source_summary.loaded_count,
            source_summary.loaded_bytes,
            source_summary.token_count,
            source_summary.import_count,
            source_summary.export_count,
            source_summary.function_count,
            source_summary.class_count,
        },
    );
}

fn writeBindSummaryJson(writer: anytype, bind_summary: *const binder.BindSummary) !void {
    try writer.print(
        "{{\"symbols\":{d},\"exported\":{d},\"value\":{d},\"type\":{d},\"duplicates\":{d}}}",
        .{
            bind_summary.symbol_count,
            bind_summary.exported_symbol_count,
            bind_summary.value_symbol_count,
            bind_summary.type_symbol_count,
            bind_summary.duplicate_count,
        },
    );
}

fn writeSourceDiagnosticsJson(writer: anytype, diagnostics: []const source.SourceDiagnostic) !void {
    try writer.writeAll("[");
    for (diagnostics, 0..) |diag, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"path\":");
        try std.json.encodeJsonString(diag.path, .{}, writer);
        try writer.writeAll(",\"message\":");
        try std.json.encodeJsonString(diag.message, .{}, writer);
        try writer.writeAll("}");
    }
    try writer.writeAll("]");
}

fn writeBindDiagnosticsJson(writer: anytype, diagnostics: []const binder.BoundDiagnostic) !void {
    try writer.writeAll("[");
    for (diagnostics, 0..) |diag, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"name\":");
        try std.json.encodeJsonString(diag.name, .{}, writer);
        try writer.writeAll(",\"message\":");
        try std.json.encodeJsonString(diag.message, .{}, writer);
        try writer.writeAll(",\"firstPath\":");
        try std.json.encodeJsonString(diag.first_path, .{}, writer);
        try writer.writeAll(",\"secondPath\":");
        try std.json.encodeJsonString(diag.second_path, .{}, writer);
        try writer.writeAll("}");
    }
    try writer.writeAll("]");
}

fn writeCheckDiagnosticsJson(writer: anytype, check_summary: *const checker.CheckSummary) !void {
    try writer.writeAll("[");
    for (check_summary.diagnostics.items, 0..) |diag, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"kind\":");
        try std.json.encodeJsonString(@tagName(diag.kind), .{}, writer);
        try writer.writeAll(",\"subject\":");
        try std.json.encodeJsonString(diag.subject, .{}, writer);
        try writer.writeAll(",\"message\":");
        try std.json.encodeJsonString(diag.message, .{}, writer);
        try writer.writeAll(",\"firstPath\":");
        try std.json.encodeJsonString(diag.first_path, .{}, writer);
        if (diag.second_path) |second_path| {
            try writer.writeAll(",\"secondPath\":");
            try std.json.encodeJsonString(second_path, .{}, writer);
        }
        if (diag.space) |space| {
            try writer.writeAll(",\"space\":");
            try std.json.encodeJsonString(@tagName(space), .{}, writer);
        }
        try writer.writeAll("}");
    }
    try writer.writeAll("]");
}

fn forwardToTsgo(request: *const types.CompileRequest, result: *types.CompileResult, writer: anytype) !u8 {
    const allocator = std.heap.page_allocator;
    _ = result;
    const tsgo_path = findTsgoBinary() orelse {
        _ = writer;
        return 0;
    };

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append(tsgo_path);
    for (request.passthrough.items) |arg| {
        try argv.append(arg);
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    _ = writer;
    return switch (term) {
        .Exited => |code| @intCast(code),
        .Signal => 1,
        .Stopped => 1,
        .Unknown => 1,
    };
}

fn findTsgoBinary() ?[]const u8 {
    const candidates = [_][]const u8{
        "./built/local/bin/tsgo",
        "built/local/bin/tsgo",
    };

    for (candidates) |candidate| {
        if (std.fs.cwd().access(candidate, .{})) |_| {
            return candidate;
        } else |_| {}
    }

    return null;
}

fn actionLabel(action: Action) []const u8 {
    return switch (action) {
        .print_help => "help",
        .print_version => "version",
        .init_config => "init",
        .show_config => "show-config",
        .start_watch => "watch",
        .build => "build",
        .compile => "compile",
        .failed => "failed",
    };
}

fn modeLabel(mode: Mode) []const u8 {
    return switch (mode) {
        .normal => "normal",
        .build => "build",
        .watch => "watch",
    };
}

fn configLabel(config_resolution: types.ConfigResolution) []const u8 {
    return switch (config_resolution) {
        .none => "none",
        
        .explicit_project => "explicit-project",
        .discovered_local_tsconfig => "local-tsconfig",
        .skipped_by_ignore_config => "ignore-config",
        .no => "no",
        .found => "found",
        .fallback => "fallback",
    };
}

test "listFilesOnly prints discovered sources and skips later phases" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var file = try temp.dir.createFile("src/main.ts", .{});
        defer file.close();
        try file.writeAll("export const value = 1;\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.ignore_config = true;
    request.flags.list_files_only = true;
    try request.passthrough.append("--ignoreConfig");
    try request.passthrough.append("--listFilesOnly");
    try request.passthrough.append("src/main.ts");
    try request.entry_files.append("src/main.ts");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = true,
        .native_failed = false,
        .config_resolution = .skipped_by_ignore_config,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = request.entry_files.items.len,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: native compile plan") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "src/main.ts\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: source summary") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: bind summary") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: check summary") == null);
}

test "listFilesOnly with graphJson emits list-files stage json" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var file = try temp.dir.createFile("src/main.ts", .{});
        defer file.close();
        try file.writeAll("export const value = 1;\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.ignore_config = true;
    request.flags.list_files_only = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--ignoreConfig");
    try request.passthrough.append("--listFilesOnly");
    try request.passthrough.append("--graphJson");
    try request.passthrough.append("src/main.ts");
    try request.entry_files.append("src/main.ts");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = true,
        .native_failed = false,
        .config_resolution = .skipped_by_ignore_config,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = request.entry_files.items.len,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"list-files\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"sources\":[\"src/main.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"source\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"bind\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"check\":null") != null);

    var lines = std.mem.splitScalar(u8, buffer.items, '\n');
    var last_non_empty: []const u8 = "";
    while (lines.next()) |line| {
        if (line.len != 0) last_non_empty = line;
    }
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, last_non_empty, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "native diagnostics stop before forwarding to tsgo" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var file = try temp.dir.createFile("src/main.ts", .{});
        defer file.close();
        try file.writeAll("import { missing } from \"./missing\";\n");
    }
    {
        var tsgo = try temp.dir.createFile("tsgo", .{});
        try tsgo.writeAll(
            "#!/bin/sh\n" ++
                "echo forwarded > forwarded.txt\n" ++
                "exit 0\n",
        );
        try tsgo.chmod(0o755);
        tsgo.close();
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.ignore_config = true;
    try request.passthrough.append("--ignoreConfig");
    try request.passthrough.append("src/main.ts");
    try request.entry_files.append("src/main.ts");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .skipped_by_ignore_config,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = request.entry_files.items.len,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expect(result.native_failed);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Cannot resolve relative import") != null);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access("forwarded.txt", .{}));
}

test "graphJson stays last line and skips forwarding" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    try temp.dir.makePath("built/local/bin");
    {
        var file = try temp.dir.createFile("src/main.ts", .{});
        defer file.close();
        try file.writeAll("export const value = 1;\n");
    }
    {
        var tsgo = try temp.dir.createFile("built/local/bin/tsgo", .{});
        try tsgo.writeAll(
            "#!/bin/sh\n" ++
                "echo forwarded > forwarded.txt\n" ++
                "echo tsgo-ran\n" ++
                "exit 0\n",
        );
        try tsgo.chmod(0o755);
        tsgo.close();
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.ignore_config = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--ignoreConfig");
    try request.passthrough.append("--graphJson");
    try request.passthrough.append("src/main.ts");
    try request.entry_files.append("src/main.ts");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .skipped_by_ignore_config,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = request.entry_files.items.len,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"schemaVersion\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"cwd\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"edges\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"status\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"request\":{\"projectPath\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"passthrough\":[\"--ignoreConfig\",\"--graphJson\",\"src/main.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"graphJson\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"roots\":[\"src/main.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"sources\":[\"src/main.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"plan\":{\"configPath\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"pathMappings\":[]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"source\":{\"loaded\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"bind\":{\"symbols\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"check\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "tsgo-ran") == null);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access("forwarded.txt", .{}));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: native compile plan") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: source summary") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: bind summary") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "zts: check summary") == null);

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, buffer.items, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

test "graphJson emits source-stage json on source diagnostics" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.ignore_config = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--ignoreConfig");
    try request.passthrough.append("--graphJson");
    try request.passthrough.append("src/missing.ts");
    try request.entry_files.append("src/missing.ts");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .skipped_by_ignore_config,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = request.entry_files.items.len,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"source\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"status\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"diagnostics\":[{\"path\":\"src/missing.ts\"") != null);
}

test "graphJson emits bind-stage json on bind diagnostics" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var a = try temp.dir.createFile("src/a.ts", .{});
        defer a.close();
        try a.writeAll("export function run() {}\n");
    }
    {
        var b = try temp.dir.createFile("src/b.ts", .{});
        defer b.close();
        try b.writeAll("function run() {}\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.ignore_config = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--ignoreConfig");
    try request.passthrough.append("--graphJson");
    try request.passthrough.append("src/a.ts");
    try request.entry_files.append("src/a.ts");
    try request.entry_files.append("src/b.ts");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .skipped_by_ignore_config,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = request.entry_files.items.len,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"bind\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"duplicates\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"diagnostics\":[{\"name\":\"run\"") != null);
}

test "showConfig with graphJson emits action json" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var file = try temp.dir.createFile("tsconfig.json", .{});
        defer file.close();
        try file.writeAll("{\"compilerOptions\":{\"strict\":true}}\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.show_config = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--showConfig");
    try request.passthrough.append("--graphJson");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .show_config,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .discovered_local_tsconfig,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = "tsconfig.json",
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"show-config\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"path\":\"tsconfig.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"content\":\"{\\\"compilerOptions\\\":{\\\"strict\\\":true}}\\n\"") != null);
}

test "help with graphJson emits action json" {
    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.help = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--help");
    try request.passthrough.append("--graphJson");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .print_help,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .none,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"help\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":\"help\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"content\":\"zts - Zig TypeScript compiler prototype") != null);
}

test "version with graphJson emits action json" {
    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.version = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--version");
    try request.passthrough.append("--graphJson");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .print_version,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .none,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"content\":\"0.0.0-dev\"") != null);
}

test "init with graphJson emits action json" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.flags.init = true;
    request.flags.graph_json = true;
    try request.passthrough.append("--init");
    try request.passthrough.append("--graphJson");

    var result = types.CompileResult{
        .exit_code = 0,
        .action = .init_config,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .none,
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try run(&request, &result, buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"init\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"path\":\"tsconfig.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"content\":null") != null);
}
