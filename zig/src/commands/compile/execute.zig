const std = @import("std");
const types = @import("./types.zig");
const config = @import("./config.zig");

pub fn execute(request: *const types.CompileRequest) types.CompileResult {
    const resolved_config_path = resolveConfigPath(request);
    var result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = request.mode,
        .list_files_only = request.flags.list_files_only,
        .config_resolution = resolveConfig(request, resolved_config_path),
        .forwarded_arg_count = request.passthrough.items.len,
        .entry_file_count = request.entry_files.items.len,
        .project_path = request.project_path,
        .resolved_config_path = resolved_config_path,
        .diagnostic = null,
    };

    if (request.missing_project_value) {
        return fail(result, "Option '--project' expects a path.");
    }

    if (request.mode == .watch and request.flags.list_files_only) {
        return fail(result, "Options '--watch' and '--listFilesOnly' cannot be combined.");
    }

    if (request.project_path != null and request.entry_files.items.len > 0) {
        return fail(result, "Option '--project' cannot be mixed with source files on the command line.");
    }

    if (request.project_path) |project_path| {
        if (resolved_config_path == null and !config.projectExists(project_path)) {
            return fail(result, "The specified project path does not exist or does not contain a tsconfig.json file.");
        }
    }

    if (request.flags.version) {
        result.action = .print_version;
        return result;
    }

    if (request.flags.help or request.flags.all) {
        result.action = .print_help;
        return result;
    }

    if (request.flags.init) {
        result.action = .init_config;
        return result;
    }

    if (request.flags.show_config) {
        if (result.resolved_config_path == null) {
            return fail(result, "Cannot find a tsconfig.json file for '--showConfig'.");
        }
        result.action = .show_config;
        return result;
    }

    switch (request.mode) {
        .watch => result.action = .start_watch,
        .build => result.action = .build,
        .normal => result.action = .compile,
    }

    return result;
}

fn resolveConfig(request: *const types.CompileRequest, resolved_config_path: ?[]const u8) types.ConfigResolution {
    if (request.project_path != null and resolved_config_path != null) {
        return .explicit_project;
    }

    if (request.flags.ignore_config) {
        return .skipped_by_ignore_config;
    }

    if (resolved_config_path != null) {
        return .discovered_local_tsconfig;
    }

    return .none;
}

fn resolveConfigPath(request: *const types.CompileRequest) ?[]const u8 {
    // Priority: explicit tsconfig flag > project path > auto-detect
    if (request.flags.tsconfig_path) |tsconfig_path| {
        return tsconfig_path;
    }

    if (request.project_path) |project_path| {
        return config.resolveProjectPath(std.heap.page_allocator, project_path);
    }

    if (request.flags.ignore_config) {
        return null;
    }

    return config.findAncestorTsconfigPath(std.heap.page_allocator);
}

fn fail(result: types.CompileResult, diagnostic: []const u8) types.CompileResult {
    var failed = result;
    failed.exit_code = 1;
    failed.action = .failed;
    failed.diagnostic = diagnostic;
    return failed;
}

test "reject project mixed with source files" {
    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    request.project_path = "tsconfig.json";
    try request.entry_files.append("src/index.ts");

    const result = execute(&request);
    try std.testing.expectEqual(types.CompileAction.failed, result.action);
    try std.testing.expect(result.diagnostic != null);
}

test "watch mode rejects listFilesOnly" {
    var request = types.CompileRequest.init(std.testing.allocator, .watch);
    defer request.deinit();

    request.flags.list_files_only = true;

    const result = execute(&request);
    try std.testing.expectEqual(types.CompileAction.failed, result.action);
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "showConfig fails when project path is missing" {
    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    request.flags.show_config = true;
    request.flags.ignore_config = true;

    const result = execute(&request);
    try std.testing.expectEqual(types.CompileAction.failed, result.action);
    try std.testing.expect(result.diagnostic != null);
}

test "missing explicit project path fails" {
    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    request.project_path = "definitely-missing-zts-project";

    const result = execute(&request);
    try std.testing.expectEqual(types.CompileAction.failed, result.action);
    try std.testing.expect(result.diagnostic != null);
}

test "directory project resolves to explicit project config" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    try temp.dir.makePath("sample");
    var sample_dir = try temp.dir.openDir("sample", .{});
    defer sample_dir.close();
    var file = try sample_dir.createFile("tsconfig.json", .{});
    defer file.close();
    try file.writeAll("{}");

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    request.project_path = "sample";

    const result = execute(&request);
    try std.testing.expect(result.resolved_config_path != null);
    try std.testing.expectEqual(types.ConfigResolution.explicit_project, result.config_resolution);
}

test "entry files still discover local tsconfig" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var file = try temp.dir.createFile("tsconfig.json", .{});
        defer file.close();
        try file.writeAll("{}");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    try request.entry_files.append("src/main.ts");

    const result = execute(&request);
    try std.testing.expect(result.resolved_config_path != null);
    try std.testing.expectEqual(types.ConfigResolution.discovered_local_tsconfig, result.config_resolution);
}
