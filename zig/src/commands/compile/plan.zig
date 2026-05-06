const std = @import("std");
const cli_types = @import("../../cli/types.zig");
const types = @import("./types.zig");
const config = @import("./config.zig");
const parser = @import("./parser.zig");
const tsoptions = @import("./tsoptions.zig");


/// Parse module kind from string value
fn parseModuleKind(value: ?std.json.Value) tsoptions.ModuleKind {
    if (value) |v| {
        if (v == .string) {
            const s = v.string;
            if (std.mem.eql(u8, s, "CommonJS")) return .commonjs;
            if (std.mem.eql(u8, s, "AMD")) return .amd;
            if (std.mem.eql(u8, s, "UMD")) return .umd;
            if (std.mem.eql(u8, s, "System")) return .system;
            if (std.mem.eql(u8, s, "ES6") or std.mem.eql(u8, s, "ES2015")) return .es6;
            if (std.mem.eql(u8, s, "ES2020")) return .es2020;
            if (std.mem.eql(u8, s, "ES2022")) return .es2022;
            if (std.mem.eql(u8, s, "ESNext")) return .esnext;
            if (std.mem.eql(u8, s, "Node16")) return .node16;
            if (std.mem.eql(u8, s, "Node18")) return .node18;
            if (std.mem.eql(u8, s, "Node20")) return .node20;
            if (std.mem.eql(u8, s, "NodeNext")) return .nodenext;
            if (std.mem.eql(u8, s, "Preserve")) return .preserve;
        }
    }
    return .commonjs; // default
}

pub const CompilePlan = struct {
    config_path: ?[]const u8 = null,
    config_dir: ?[]const u8 = null,
    root_dir: ?[]const u8 = null,
    out_dir: ?[]const u8 = null,
    module_name: ?[]const u8 = null,
    module_type: tsoptions.ModuleKind = .commonjs,
    target_name: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    extends_path: ?[]const u8 = null,
    path_mappings: std.ArrayList(PathMapping),
    include_patterns: std.ArrayList([]const u8),
    explicit_files: std.ArrayList([]const u8),
    cli_entry_files: std.ArrayList([]const u8),
    discovered_sources: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) CompilePlan {
        return .{
            .config_path = null,
            .config_dir = null,
            .root_dir = null,
            .out_dir = null,
            .module_name = null,
            .target_name = null,
            .base_url = null,
            .extends_path = null,
            .path_mappings = std.ArrayList(PathMapping).init(allocator),
            .include_patterns = std.ArrayList([]const u8).init(allocator),
            .explicit_files = std.ArrayList([]const u8).init(allocator),
            .cli_entry_files = std.ArrayList([]const u8).init(allocator),
            .discovered_sources = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CompilePlan, allocator: std.mem.Allocator) void {
        if (self.config_path) |value| allocator.free(value);
        if (self.config_dir) |value| allocator.free(value);
        if (self.root_dir) |value| allocator.free(value);
        if (self.out_dir) |value| allocator.free(value);
        if (self.module_name) |value| allocator.free(value);
        if (self.target_name) |value| allocator.free(value);
        if (self.base_url) |value| allocator.free(value);
        if (self.extends_path) |value| allocator.free(value);
        freePathMappings(allocator, &self.path_mappings);
        freeStringList(allocator, &self.include_patterns);
        freeStringList(allocator, &self.explicit_files);
        freeStringList(allocator, &self.cli_entry_files);
        freeStringList(allocator, &self.discovered_sources);
    }
};

pub const PathMapping = struct {
    pattern: []const u8,
    targets: std.ArrayList([]const u8),
};

pub fn buildPlan(
    allocator: std.mem.Allocator,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
) !CompilePlan {
    var plan = CompilePlan.init(allocator);
    errdefer plan.deinit(allocator);

    for (request.entry_files.items) |entry| {
        try plan.cli_entry_files.append(try allocator.dupe(u8, entry));
    }

    if (result.resolved_config_path) |config_path| {
        plan.config_path = try allocator.dupe(u8, config_path);
        plan.config_dir = try configDirFromPath(allocator, config_path);
        try populateFromConfig(allocator, &plan, config_path);
    }

    try populateSourceFiles(allocator, &plan);

    return plan;
}

pub fn writePlan(
    writer: anytype,
    request: *const types.CompileRequest,
    result: *const types.CompileResult,
    plan: *const CompilePlan,
) !void {
    try writer.print(
        "zts: native compile plan (action={s}, mode={s}, config={s})\n",
        .{
            actionLabel(result.action),
            modeLabel(request.compile_mode),
            if (plan.config_path != null) "yes" else "no",
        },
    );

    if (plan.config_path) |value| {
        try writer.print("zts: config-path={s}\n", .{value});
    }
    if (plan.config_dir) |value| {
        try writer.print("zts: config-dir={s}\n", .{value});
    }
    if (plan.extends_path) |value| {
        try writer.print("zts: extends={s}\n", .{value});
    }
    if (plan.root_dir) |value| {
        try writer.print("zts: rootDir={s}\n", .{value});
    }
    if (plan.out_dir) |value| {
        try writer.print("zts: outDir={s}\n", .{value});
    }
    if (plan.module_name) |value| {
        try writer.print("zts: module={s}\n", .{value});
    }
    if (plan.target_name) |value| {
        try writer.print("zts: target={s}\n", .{value});
    }
    if (plan.base_url) |value| {
        try writer.print("zts: baseUrl={s}\n", .{value});
    }

    try writer.print(
        "zts: summary(cli-files={d}, config-files={d}, includes={d}, paths={d}, discovered={d})\n",
        .{
            plan.cli_entry_files.items.len,
            plan.explicit_files.items.len,
            plan.include_patterns.items.len,
            plan.path_mappings.items.len,
            plan.discovered_sources.items.len,
        },
    );

    for (plan.cli_entry_files.items) |value| {
        try writer.print("zts: cli-file={s}\n", .{value});
    }
    for (plan.explicit_files.items) |value| {
        try writer.print("zts: config-file={s}\n", .{value});
    }
    for (plan.include_patterns.items) |value| {
        try writer.print("zts: include={s}\n", .{value});
    }
    for (plan.path_mappings.items) |mapping| {
        for (mapping.targets.items) |target| {
            try writer.print("zts: path={s} -> {s}\n", .{ mapping.pattern, target });
        }
    }
    for (plan.discovered_sources.items) |value| {
        try writer.print("zts: source={s}\n", .{value});
    }
}

fn populateFromConfig(
    allocator: std.mem.Allocator,
    plan: *CompilePlan,
    config_path: []const u8,
) !void {
    var seen_paths = std.StringHashMap(void).init(allocator);
    defer {
        var iterator = seen_paths.keyIterator();
        while (iterator.next()) |key_ptr| {
            allocator.free(key_ptr.*);
        }
        seen_paths.deinit();
    }

    try populateFromConfigRecursive(allocator, plan, config_path, &seen_paths);
}

fn populateFromConfigRecursive(
    allocator: std.mem.Allocator,
    plan: *CompilePlan,
    config_path: []const u8,
    seen_paths: *std.StringHashMap(void),
) !void {
    if (seen_paths.contains(config_path)) return;
    try seen_paths.put(try allocator.dupe(u8, config_path), {});

    const text = try config.readConfig(allocator, config_path);
    defer allocator.free(text);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const object = root.object;

    if (object.get("extends")) |extends_value| {
        if (extends_value == .string) {
            const resolved_extends = try resolveExtendsPath(allocator, config_path, extends_value.string);
            defer allocator.free(resolved_extends);

            if (plan.extends_path) |value| allocator.free(value);
            plan.extends_path = try allocator.dupe(u8, resolved_extends);
            try populateFromConfigRecursive(allocator, plan, resolved_extends, seen_paths);
        }
    }

    if (object.get("compilerOptions")) |compiler_options_value| {
        if (compiler_options_value == .object) {
            const compiler_options = compiler_options_value.object;
            try replaceOptionalString(allocator, &plan.root_dir, compiler_options.get("rootDir"));
            try replaceOptionalString(allocator, &plan.out_dir, compiler_options.get("outDir"));
            plan.module_type = parseModuleKind(compiler_options.get("module"));
            try replaceOptionalString(allocator, &plan.target_name, compiler_options.get("target"));
            try replaceOptionalString(allocator, &plan.module_name, compiler_options.get("module"));
            try replaceOptionalString(allocator, &plan.base_url, compiler_options.get("baseUrl"));
            if (compiler_options.get("paths")) |paths_value| {
                freePathMappings(allocator, &plan.path_mappings);
                plan.path_mappings = std.ArrayList(PathMapping).init(allocator);
                try appendPathMappings(allocator, &plan.path_mappings, paths_value);
            }
        }
    }

    if (object.get("include")) |include_value| {
        freeStringList(allocator, &plan.include_patterns);
        plan.include_patterns = std.ArrayList([]const u8).init(allocator);
        try appendStringArray(allocator, &plan.include_patterns, include_value);
    }

    if (object.get("files")) |files_value| {
        freeStringList(allocator, &plan.explicit_files);
        plan.explicit_files = std.ArrayList([]const u8).init(allocator);
        try appendStringArray(allocator, &plan.explicit_files, files_value);
    }
}

fn dupOptionalString(
    allocator: std.mem.Allocator,
    value: ?std.json.Value,
) !?[]const u8 {
    if (value) |unwrapped| {
        if (unwrapped == .string) {
            return try allocator.dupe(u8, unwrapped.string);
        }
    }
    return null;
}

fn replaceOptionalString(
    allocator: std.mem.Allocator,
    slot: *?[]const u8,
    value: ?std.json.Value,
) !void {
    const next = try dupOptionalString(allocator, value);
    if (next) |resolved| {
        if (slot.*) |existing| allocator.free(existing);
        slot.* = resolved;
    }
}

fn appendStringArray(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: std.json.Value,
) !void {
    if (value != .array) {
        return;
    }

    for (value.array.items) |item| {
        if (item == .string) {
            try list.append(try allocator.dupe(u8, item.string));
        }
    }
}

fn appendPathMappings(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(PathMapping),
    value: std.json.Value,
) !void {
    if (value != .object) return;

    var iterator = value.object.iterator();
    while (iterator.next()) |entry| {
        if (entry.value_ptr.* != .array) continue;

        var mapping = PathMapping{
            .pattern = try allocator.dupe(u8, entry.key_ptr.*),
            .targets = std.ArrayList([]const u8).init(allocator),
        };
        errdefer {
            allocator.free(mapping.pattern);
            freeStringList(allocator, &mapping.targets);
        }

        for (entry.value_ptr.array.items) |item| {
            if (item == .string) {
                try mapping.targets.append(try allocator.dupe(u8, item.string));
            }
        }

        try list.append(mapping);
    }
}

fn populateSourceFiles(allocator: std.mem.Allocator, plan: *CompilePlan) !void {
    for (plan.cli_entry_files.items) |entry| {
        try appendUniquePath(allocator, &plan.discovered_sources, entry);
    }

    for (plan.explicit_files.items) |entry| {
        const resolved = try resolveAgainstConfigDir(allocator, plan, entry);
        defer allocator.free(resolved);
        try appendUniquePath(allocator, &plan.discovered_sources, resolved);
    }

    for (plan.include_patterns.items) |pattern| {
        const resolved = try resolveAgainstConfigDir(allocator, plan, pattern);
        defer allocator.free(resolved);
        try expandIncludePattern(allocator, &plan.discovered_sources, resolved);
    }

    try discoverDependencies(allocator, plan);
}

fn discoverDependencies(
    allocator: std.mem.Allocator,
    compile_plan: *const CompilePlan,
) !void {
    const discovered_sources = @constCast(&compile_plan.discovered_sources);
    var cursor: usize = 0;
    while (cursor < discovered_sources.items.len) : (cursor += 1) {
        const source_path = discovered_sources.items[cursor];
        const contents = readSourceForDiscovery(allocator, source_path) catch |err| switch (err) {
            error.FileNotFound, error.IsDir => continue,
            else => return err,
        };
        defer allocator.free(contents);

        var parsed = try parser.parseTopLevel(allocator, contents);
        defer parsed.deinit(allocator);

        for (parsed.declarations.items) |decl| {
            const specifier = decl.module_specifier orelse continue;
            const resolved = try resolveDiscoveredImport(allocator, compile_plan, source_path, specifier);
            defer if (resolved) |path| allocator.free(path);
            if (resolved) |path| {
                try appendUniquePath(allocator, discovered_sources, path);
            }
        }
    }
}

fn readSourceForDiscovery(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.kind == .directory) return error.IsDir;
    return file.readToEndAlloc(allocator, 4 * 1024 * 1024);
}

fn isRelativeModuleSpecifier(specifier: []const u8) bool {
    return std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../");
}

fn resolveRelativeDiscoveryImport(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    specifier: []const u8,
) !?[]const u8 {
    const base_dir = std.fs.path.dirname(source_path) orelse ".";
    const joined = try std.fs.path.join(allocator, &.{ base_dir, specifier });
    defer allocator.free(joined);

    return resolveDiscoveryPathCandidates(allocator, joined);
}

fn resolveDiscoveredImport(
    allocator: std.mem.Allocator,
    compile_plan: *const CompilePlan,
    source_path: []const u8,
    specifier: []const u8,
) !?[]const u8 {
    if (isRelativeModuleSpecifier(specifier)) {
        return resolveRelativeDiscoveryImport(allocator, source_path, specifier);
    }

    if (try resolvePathMappedDiscoveryImport(allocator, compile_plan, specifier)) |resolved| {
        return resolved;
    }

    if (try resolveBaseUrlDiscoveryImport(allocator, compile_plan, specifier)) |resolved| {
        return resolved;
    }

    return null;
}

fn resolvePathMappedDiscoveryImport(
    allocator: std.mem.Allocator,
    compile_plan: *const CompilePlan,
    specifier: []const u8,
) !?[]const u8 {
    const mapping = findPathMapping(compile_plan, specifier) orelse return null;
    const captures = extractPathCapture(mapping.pattern, specifier) orelse return null;

    const base_root = try baseRootForPlan(allocator, compile_plan);
    defer allocator.free(base_root);

    for (mapping.targets.items) |target_pattern| {
        const target = try substitutePathCapture(allocator, target_pattern, captures);
        defer allocator.free(target);

        const joined = try std.fs.path.join(allocator, &.{ base_root, target });
        defer allocator.free(joined);

        if (try resolveDiscoveryPathCandidates(allocator, joined)) |resolved| {
            return resolved;
        }
    }

    return null;
}

fn resolveBaseUrlDiscoveryImport(
    allocator: std.mem.Allocator,
    compile_plan: *const CompilePlan,
    specifier: []const u8,
) !?[]const u8 {
    const base_url = compile_plan.base_url orelse return null;
    const config_dir = compile_plan.config_dir orelse ".";
    const joined_base = try std.fs.path.join(allocator, &.{ config_dir, base_url, specifier });
    defer allocator.free(joined_base);

    return resolveDiscoveryPathCandidates(allocator, joined_base);
}

fn baseRootForPlan(
    allocator: std.mem.Allocator,
    compile_plan: *const CompilePlan,
) ![]u8 {
    const config_dir = compile_plan.config_dir orelse ".";
    if (compile_plan.base_url) |base_url| {
        return std.fs.path.join(allocator, &.{ config_dir, base_url });
    }
    return allocator.dupe(u8, config_dir);
}

fn findPathMapping(
    compile_plan: *const CompilePlan,
    specifier: []const u8,
) ?PathMapping {
    for (compile_plan.path_mappings.items) |mapping| {
        if (pathPatternMatches(mapping.pattern, specifier)) {
            return mapping;
        }
    }
    return null;
}

fn pathPatternMatches(pattern: []const u8, specifier: []const u8) bool {
    return extractPathCapture(pattern, specifier) != null;
}

fn extractPathCapture(pattern: []const u8, specifier: []const u8) ?[]const u8 {
    const wildcard_index = std.mem.indexOf(u8, pattern, "*");
    if (wildcard_index == null) {
        if (std.mem.eql(u8, pattern, specifier)) return "";
        return null;
    }

    const index = wildcard_index.?;
    const prefix = pattern[0..index];
    const suffix = pattern[index + 1 ..];
    if (!std.mem.startsWith(u8, specifier, prefix)) return null;
    if (!std.mem.endsWith(u8, specifier, suffix)) return null;
    if (specifier.len < prefix.len + suffix.len) return null;
    return specifier[prefix.len .. specifier.len - suffix.len];
}

fn substitutePathCapture(
    allocator: std.mem.Allocator,
    target_pattern: []const u8,
    capture: []const u8,
) ![]u8 {
    const wildcard_index = std.mem.indexOf(u8, target_pattern, "*");
    if (wildcard_index == null) {
        return allocator.dupe(u8, target_pattern);
    }

    const index = wildcard_index.?;
    return std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}",
        .{ target_pattern[0..index], capture, target_pattern[index + 1 ..] },
    );
}

fn resolveDiscoveryPathCandidates(
    allocator: std.mem.Allocator,
    joined: []const u8,
) !?[]const u8 {
    const candidates = [_][]const u8{
        "",
        ".d.ts",
        ".ts",
        ".tsx",
        ".mts",
        ".cts",
        "/index.d.ts",
        "/index.ts",
        "/index.tsx",
        "/index.mts",
        "/index.cts",
    };

    for (candidates) |suffix| {
        const candidate = try std.fmt.allocPrint(allocator, "{s}{s}", .{ joined, suffix });
        errdefer allocator.free(candidate);
        if (std.fs.cwd().access(candidate, .{})) |_| {
            return candidate;
        } else |_| {
            allocator.free(candidate);
        }
    }

    return null;
}

fn expandIncludePattern(
    allocator: std.mem.Allocator,
    output: *std.ArrayList([]const u8),
    pattern: []const u8,
) !void {
    if (std.mem.endsWith(u8, pattern, "/**/*")) {
        const base = pattern[0 .. pattern.len - "/**/*".len];
        try collectDirSources(allocator, output, base);
        return;
    }

    if (std.mem.indexOf(u8, pattern, "/**/*.")) |glob_index| {
        const base = pattern[0..glob_index];
        const suffix = pattern[glob_index + "/**/*".len ..];
        try collectDirSourcesMatchingSuffix(allocator, output, base, suffix);
        return;
    }

    if (std.mem.indexOf(u8, pattern, "*") != null) {
        return;
    }

    if (isDirectory(pattern)) {
        try collectDirSources(allocator, output, pattern);
        return;
    }

    if (isSupportedSourceFile(pattern)) {
        try appendUniquePath(allocator, output, pattern);
    }
}

fn collectDirSources(
    allocator: std.mem.Allocator,
    output: *std.ArrayList([]const u8),
    dir_path: []const u8,
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!isSupportedSourceFile(entry.basename)) continue;

        const joined = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.path });
        defer allocator.free(joined);
        try appendUniquePath(allocator, output, joined);
    }
}

fn collectDirSourcesMatchingSuffix(
    allocator: std.mem.Allocator,
    output: *std.ArrayList([]const u8),
    dir_path: []const u8,
    suffix: []const u8,
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!isSupportedSourceFile(entry.basename)) continue;
        if (!std.mem.endsWith(u8, entry.basename, suffix)) continue;

        const joined = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.path });
        defer allocator.free(joined);
        try appendUniquePath(allocator, output, joined);
    }
}

fn appendUniquePath(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: []const u8,
) !void {
    const normalized = try normalizeProjectPath(allocator, value);
    defer allocator.free(normalized);

    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, normalized)) {
            return;
        }
    }

    try list.append(try allocator.dupe(u8, normalized));
}

fn normalizeProjectPath(
    allocator: std.mem.Allocator,
    value: []const u8,
) ![]const u8 {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    if (std.fs.path.isAbsolute(value)) {
        const absolute = try std.fs.path.resolve(allocator, &.{value});
        defer allocator.free(absolute);
        return std.fs.path.relative(allocator, cwd, absolute);
    }

    const absolute = try std.fs.path.resolve(allocator, &.{ cwd, value });
    defer allocator.free(absolute);
    return std.fs.path.relative(allocator, cwd, absolute);
}

fn resolveAgainstConfigDir(
    allocator: std.mem.Allocator,
    plan: *const CompilePlan,
    value: []const u8,
) ![]const u8 {
    if (plan.config_dir) |config_dir| {
        if (std.fs.path.isAbsolute(value)) {
            return allocator.dupe(u8, value);
        }
        return std.fs.path.join(allocator, &[_][]const u8{ config_dir, value });
    }
    return allocator.dupe(u8, value);
}

fn configDirFromPath(allocator: std.mem.Allocator, config_path: []const u8) ![]const u8 {
    const dirname = std.fs.path.dirname(config_path) orelse ".";
    return allocator.dupe(u8, dirname);
}

fn resolveExtendsPath(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    extends_value: []const u8,
) ![]u8 {
    if (std.fs.path.isAbsolute(extends_value)) {
        return allocator.dupe(u8, extends_value);
    }

    const config_dir = std.fs.path.dirname(config_path) orelse ".";
    const raw_path = if (std.mem.eql(u8, config_dir, "."))
        try allocator.dupe(u8, extends_value)
    else
        try std.fs.path.join(allocator, &.{ config_dir, extends_value });
    defer allocator.free(raw_path);

    if (hasJsonSuffix(raw_path)) {
        return allocator.dupe(u8, raw_path);
    }

    const with_json = try std.fmt.allocPrint(allocator, "{s}.json", .{raw_path});
    errdefer allocator.free(with_json);
    if (std.fs.cwd().access(with_json, .{})) |_| {
        return with_json;
    } else |_| {
        allocator.free(with_json);
    }

    return allocator.dupe(u8, raw_path);
}

fn hasJsonSuffix(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".json") or std.mem.endsWith(u8, path, ".jsonc");
}

fn isDirectory(path: []const u8) bool {
    if (std.fs.cwd().openDir(path, .{})) |opened_dir| {
        var dir = opened_dir;
        dir.close();
        return true;
    } else |_| {
        return false;
    }
}

fn isSupportedSourceFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".ts") or
        std.mem.endsWith(u8, path, ".tsx") or
        std.mem.endsWith(u8, path, ".mts") or
        std.mem.endsWith(u8, path, ".cts");
}

fn freeStringList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| {
        allocator.free(item);
    }
    list.deinit();
}

fn freePathMappings(allocator: std.mem.Allocator, list: *std.ArrayList(PathMapping)) void {
    for (list.items) |*mapping| {
        allocator.free(mapping.pattern);
        freeStringList(allocator, &mapping.targets);
    }
    list.deinit();
}

fn actionLabel(action: types.CompileAction) []const u8 {
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

fn modeLabel(mode: cli_types.CompileMode) []const u8 {
    return switch (mode) {
        .normal => "normal",
        .build => "build",
        .watch => "watch",
    };
}

test "build native plan from tsconfig" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    var file = try temp.dir.createFile("tsconfig.json", .{});
    defer file.close();
    try file.writeAll(
        \\{
        \\  "compilerOptions": {
        \\    "rootDir": "src",
        \\    "outDir": "dist",
        \\    "module": "NodeNext",
        \\    "target": "ES2023",
        \\    "baseUrl": ".",
        \\    "paths": {
        \\      "@lib/*": ["src/lib/*"]
        \\    }
        \\  },
        \\  "include": ["src/**/*"],
        \\  "files": ["src/index.ts"]
        \\}
    );

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    const result = types.CompileResult{
        .exit_code = 0,
        .list_files_only = false,
        .native_failed = false,
        .action = .compile,
        .mode = .normal,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 0,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = "tsconfig.json",
        .diagnostic = null,
    };

    var plan = try buildPlan(std.testing.allocator, &request, &result);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(".", plan.config_dir.?);
    try std.testing.expectEqualStrings("src", plan.root_dir.?);
    try std.testing.expectEqualStrings("dist", plan.out_dir.?);
    try std.testing.expectEqualStrings("NodeNext", plan.module_name.?);
    try std.testing.expectEqualStrings("ES2023", plan.target_name.?);
    try std.testing.expectEqualStrings(".", plan.base_url.?);
    try std.testing.expectEqual(@as(usize, 1), plan.path_mappings.items.len);
    try std.testing.expectEqualStrings("@lib/*", plan.path_mappings.items[0].pattern);
    try std.testing.expectEqualStrings("src/lib/*", plan.path_mappings.items[0].targets.items[0]);
    try std.testing.expectEqual(@as(usize, 1), plan.include_patterns.items.len);
    try std.testing.expectEqual(@as(usize, 1), plan.explicit_files.items.len);
    try std.testing.expectEqual(@as(usize, 1), plan.discovered_sources.items.len);
    try std.testing.expectEqualStrings("src/index.ts", plan.discovered_sources.items[0]);
}

test "expand include directory recursively" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/nested");
    {
        var one = try temp.dir.createFile("src/main.ts", .{});
        defer one.close();
        try one.writeAll("export {};\n");
    }
    {
        var two = try temp.dir.createFile("src/nested/util.ts", .{});
        defer two.close();
        try two.writeAll("export {};\n");
    }
    {
        var ignored = try temp.dir.createFile("src/notes.txt", .{});
        defer ignored.close();
        try ignored.writeAll("ignore\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    const result = types.CompileResult{
        .exit_code = 0,
        .list_files_only = false,
        .native_failed = false,
        .action = .compile,
        .mode = .normal,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 0,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = "tsconfig.json",
        .diagnostic = null,
    };

    var file = try temp.dir.createFile("tsconfig.json", .{});
    defer file.close();
    try file.writeAll(
        \\{
        \\  "include": ["src/**/*"]
        \\}
    );

    var plan = try buildPlan(std.testing.allocator, &request, &result);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), plan.discovered_sources.items.len);
    try std.testing.expect(std.mem.eql(u8, "src/main.ts", plan.discovered_sources.items[0]) or std.mem.eql(u8, "src/main.ts", plan.discovered_sources.items[1]));
}

test "config-relative include resolves under project directory" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("project/src");
    {
        var file = try temp.dir.createFile("project/src/app.ts", .{});
        defer file.close();
        try file.writeAll("export {};\n");
    }
    {
        var config_file = try temp.dir.createFile("project/tsconfig.json", .{});
        defer config_file.close();
        try config_file.writeAll(
            \\{
            \\  "include": ["./src/**/*"]
            \\}
        );
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    const result = types.CompileResult{
        .exit_code = 0,
        .list_files_only = false,
        .native_failed = false,
        .action = .compile,
        .mode = .normal,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 0,
        .entry_file_count = 0,
        .project_path = "project",
        .resolved_config_path = "project/tsconfig.json",
        .diagnostic = null,
    };

    var plan = try buildPlan(std.testing.allocator, &request, &result);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("project", plan.config_dir.?);
    try std.testing.expectEqual(@as(usize, 1), plan.discovered_sources.items.len);
    try std.testing.expectEqualStrings("project/src/app.ts", plan.discovered_sources.items[0]);
}

test "extends recursively inherits parent compiler options and include" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var file = try temp.dir.createFile("src/lib/util.ts", .{});
        defer file.close();
        try file.writeAll("export const util = 1;\n");
    }
    {
        var base = try temp.dir.createFile("tsconfig.base.json", .{});
        defer base.close();
        try base.writeAll(
            \\{
            \\  "compilerOptions": {
            \\    "baseUrl": ".",
            \\    "paths": {
            \\      "@lib/*": ["src/lib/*"]
            \\    },
            \\    "module": "NodeNext"
            \\  },
            \\  "include": ["src/**/*"]
            \\}
        );
    }
    {
        var child = try temp.dir.createFile("tsconfig.json", .{});
        defer child.close();
        try child.writeAll(
            \\{
            \\  "extends": "./tsconfig.base",
            \\  "compilerOptions": {
            \\    "target": "ES2024"
            \\  }
            \\}
        );
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    const result = types.CompileResult{
        .exit_code = 0,
        .list_files_only = false,
        .native_failed = false,
        .action = .compile,
        .mode = .normal,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 0,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = "tsconfig.json",
        .diagnostic = null,
    };

    var native_plan = try buildPlan(std.testing.allocator, &request, &result);
    defer native_plan.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("./tsconfig.base.json", native_plan.extends_path.?);
    try std.testing.expectEqualStrings(".", native_plan.base_url.?);
    try std.testing.expectEqualStrings("NodeNext", native_plan.module_name.?);
    try std.testing.expectEqualStrings("ES2024", native_plan.target_name.?);
    try std.testing.expectEqual(@as(usize, 1), native_plan.path_mappings.items.len);
    try std.testing.expectEqual(@as(usize, 1), native_plan.include_patterns.items.len);
    try std.testing.expectEqual(@as(usize, 1), native_plan.discovered_sources.items.len);
}

test "extends child overrides parent files and include" {
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
        try a.writeAll("export const a = 1;\n");
    }
    {
        var b = try temp.dir.createFile("src/b.ts", .{});
        defer b.close();
        try b.writeAll("export const b = 1;\n");
    }
    {
        var base = try temp.dir.createFile("base.json", .{});
        defer base.close();
        try base.writeAll(
            \\{
            \\  "include": ["src/a.ts"],
            \\  "files": ["src/a.ts"]
            \\}
        );
    }
    {
        var child = try temp.dir.createFile("tsconfig.json", .{});
        defer child.close();
        try child.writeAll(
            \\{
            \\  "extends": "./base.json",
            \\  "include": ["src/b.ts"],
            \\  "files": ["src/b.ts"]
            \\}
        );
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();

    const result = types.CompileResult{
        .exit_code = 0,
        .list_files_only = false,
        .native_failed = false,
        .action = .compile,
        .mode = .normal,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 0,
        .entry_file_count = 0,
        .project_path = null,
        .resolved_config_path = "tsconfig.json",
        .diagnostic = null,
    };

    var native_plan = try buildPlan(std.testing.allocator, &request, &result);
    defer native_plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), native_plan.include_patterns.items.len);
    try std.testing.expectEqualStrings("src/b.ts", native_plan.include_patterns.items[0]);
    try std.testing.expectEqual(@as(usize, 1), native_plan.explicit_files.items.len);
    try std.testing.expectEqualStrings("src/b.ts", native_plan.explicit_files.items[0]);
}

test "cli entry recursively discovers relative imports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var main = try temp.dir.createFile("src/main.ts", .{});
        defer main.close();
        try main.writeAll(
            \\import { value } from "./lib/value";
            \\export { other } from "./other";
        );
    }
    {
        var value = try temp.dir.createFile("src/lib/value.ts", .{});
        defer value.close();
        try value.writeAll("export const value = 1;\n");
    }
    {
        var other = try temp.dir.createFile("src/other.ts", .{});
        defer other.close();
        try other.writeAll("export const other = 2;\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    try request.entry_files.append("src/main.ts");

    const result = types.CompileResult{
        .exit_code = 0,
        .native_failed = false,
        .action = .compile,
        .mode = .normal,
        .list_files_only = false,
        .config_resolution = .none,
        .forwarded_arg_count = 1,
        .entry_file_count = 1,
        .project_path = null,
        .resolved_config_path = null,
        .diagnostic = null,
    };

    var native_plan = try buildPlan(std.testing.allocator, &request, &result);
    defer native_plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), native_plan.discovered_sources.items.len);
    try std.testing.expectEqualStrings("src/main.ts", native_plan.discovered_sources.items[0]);

    var saw_value = false;
    var saw_other = false;
    for (native_plan.discovered_sources.items) |path| {
        if (std.mem.eql(u8, path, "src/lib/value.ts")) saw_value = true;
        if (std.mem.eql(u8, path, "src/other.ts")) saw_other = true;
    }
    try std.testing.expect(saw_value);
    try std.testing.expect(saw_other);
}

test "cli entry recursively discovers tsconfig paths imports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var config_file = try temp.dir.createFile("tsconfig.json", .{});
        defer config_file.close();
        try config_file.writeAll(
            \\{
            \\  "compilerOptions": {
            \\    "baseUrl": ".",
            \\    "paths": {
            \\      "@lib/*": ["src/lib/*"]
            \\    }
            \\  }
            \\}
        );
    }
    {
        var main = try temp.dir.createFile("src/main.ts", .{});
        defer main.close();
        try main.writeAll("import { util } from \"@lib/util\";\n");
    }
    {
        var util = try temp.dir.createFile("src/lib/util.ts", .{});
        defer util.close();
        try util.writeAll("export const util = 1;\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    try request.entry_files.append("src/main.ts");

    const result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 1,
        .entry_file_count = 1,
        .project_path = null,
        .resolved_config_path = "tsconfig.json",
        .diagnostic = null,
    };

    var native_plan = try buildPlan(std.testing.allocator, &request, &result);
    defer native_plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), native_plan.discovered_sources.items.len);
    try std.testing.expectEqualStrings("src/main.ts", native_plan.discovered_sources.items[0]);

    var saw_util = false;
    for (native_plan.discovered_sources.items) |path| {
        if (std.mem.eql(u8, path, "src/lib/util.ts")) saw_util = true;
    }
    try std.testing.expect(saw_util);
}

test "cli entry recursively discovers baseUrl imports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/shared");
    {
        var config_file = try temp.dir.createFile("tsconfig.json", .{});
        defer config_file.close();
        try config_file.writeAll(
            \\{
            \\  "compilerOptions": {
            \\    "baseUrl": "."
            \\  }
            \\}
        );
    }
    {
        var main = try temp.dir.createFile("src/main.ts", .{});
        defer main.close();
        try main.writeAll("import { shared } from \"src/shared/util\";\n");
    }
    {
        var util = try temp.dir.createFile("src/shared/util.ts", .{});
        defer util.close();
        try util.writeAll("export const shared = 1;\n");
    }

    var request = types.CompileRequest.init(std.testing.allocator, .normal);
    defer request.deinit();
    try request.entry_files.append("src/main.ts");

    const result = types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .list_files_only = false,
        .native_failed = false,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 1,
        .entry_file_count = 1,
        .project_path = null,
        .resolved_config_path = "tsconfig.json",
        .diagnostic = null,
    };

    var native_plan = try buildPlan(std.testing.allocator, &request, &result);
    defer native_plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), native_plan.discovered_sources.items.len);

    var saw_util = false;
    for (native_plan.discovered_sources.items) |path| {
        if (std.mem.eql(u8, path, "src/shared/util.ts")) saw_util = true;
    }
    try std.testing.expect(saw_util);
}
