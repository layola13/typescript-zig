const std = @import("std");
const binder = @import("./binder.zig");
const graph = @import("./graph.zig");
const parser = @import("./parser.zig");
const plan = @import("./plan.zig");
const source = @import("./source.zig");

pub const CheckDiagnostic = struct {
    message: []const u8,
    subject: []const u8,
    kind: Kind,
    space: ?binder.SymbolSpace,
    first_path: []const u8,
    second_path: ?[]const u8,

    pub const Kind = enum {
        duplicate_export,
        unresolved_import,
        import_cycle,
        unreachable_source,
    };
};

pub const CheckSummary = struct {
    exported_symbol_count: usize = 0,
    duplicate_export_count: usize = 0,
    unresolved_import_count: usize = 0,
    resolved_import_count: usize = 0,
    internal_import_count: usize = 0,
    external_import_count: usize = 0,
    import_cycle_count: usize = 0,
    reachable_source_count: usize = 0,
    unreachable_source_count: usize = 0,
    edges: std.ArrayList(graph.Edge),
    diagnostics: std.ArrayList(CheckDiagnostic),

    pub fn init(allocator: std.mem.Allocator) CheckSummary {
        return .{
            .exported_symbol_count = 0,
            .duplicate_export_count = 0,
            .edges = std.ArrayList(graph.Edge).init(allocator),
            .diagnostics = std.ArrayList(CheckDiagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *CheckSummary, allocator: std.mem.Allocator) void {
        graph.freeEdges(allocator, &self.edges);
        for (self.diagnostics.items) |diag| {
            allocator.free(diag.message);
            allocator.free(diag.subject);
            allocator.free(diag.first_path);
            if (diag.second_path) |path| allocator.free(path);
        }
        self.diagnostics.deinit();
    }
};

pub fn checkProgram(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    loaded: *const source.SourceLoadSummary,
    bound: *const binder.BindSummary,
) !CheckSummary {
    var summary = CheckSummary.init(allocator);
    errdefer summary.deinit(allocator);

    var exported_value = std.StringHashMap(usize).init(allocator);
    var exported_type = std.StringHashMap(usize).init(allocator);
    defer {
        freeKeyMap(allocator, &exported_value);
        freeKeyMap(allocator, &exported_type);
    }

    for (bound.symbols.items, 0..) |symbol, index| {
        if (!symbol.exported) continue;
        summary.exported_symbol_count += 1;

        const seen = switch (symbol.space) {
            .value => &exported_value,
            .type => &exported_type,
        };

        if (seen.get(symbol.name)) |existing_index| {
            summary.duplicate_export_count += 1;
            const first = bound.symbols.items[existing_index];
            try summary.diagnostics.append(.{
                .message = try std.fmt.allocPrint(allocator, "Duplicate exported {s}-space symbol", .{@tagName(symbol.space)}),
                .subject = try allocator.dupe(u8, symbol.name),
                .kind = .duplicate_export,
                .space = symbol.space,
                .first_path = try allocator.dupe(u8, first.source_path),
                .second_path = try allocator.dupe(u8, symbol.source_path),
            });
        } else {
            try seen.put(try allocator.dupe(u8, symbol.name), index);
        }
    }

    try checkImports(allocator, compile_plan, loaded, &summary);

    return summary;
}

pub fn writeSummary(writer: anytype, summary: *const CheckSummary) !void {
    try writer.print(
        "zts: check summary(exported={d}, duplicate-exports={d}, unresolved-imports={d}, resolved-imports={d}, internal-imports={d}, external-imports={d}, import-cycles={d}, reachable-sources={d}, unreachable-sources={d})\n",
        .{
            summary.exported_symbol_count,
            summary.duplicate_export_count,
            summary.unresolved_import_count,
            summary.resolved_import_count,
            summary.internal_import_count,
            summary.external_import_count,
            summary.import_cycle_count,
            summary.reachable_source_count,
            summary.unreachable_source_count,
        },
    );

    for (summary.diagnostics.items) |diag| {
        switch (diag.kind) {
            .duplicate_export => try writer.print(
                "zts: check diagnostic {s}: {s} ({s}, {s})\n",
                .{ diag.subject, diag.message, diag.first_path, diag.second_path.? },
            ),
            .unresolved_import => try writer.print(
                "zts: check diagnostic {s}: {s} ({s})\n",
                .{ diag.subject, diag.message, diag.first_path },
            ),
            .import_cycle => try writer.print(
                "zts: check diagnostic {s}: {s} ({s}, {s})\n",
                .{ diag.subject, diag.message, diag.first_path, diag.second_path.? },
            ),
            .unreachable_source => try writer.print(
                "zts: check diagnostic {s}: {s} ({s})\n",
                .{ diag.subject, diag.message, diag.first_path },
            ),
        }
    }

    const preview_count = @min(summary.edges.items.len, 8);
    for (summary.edges.items[0..preview_count]) |edge| {
        try writer.print(
            "zts: graph edge kind={s} from={s} specifier={s}",
            .{ @tagName(edge.kind), edge.from_path, edge.specifier },
        );
        if (edge.target_path) |target| {
            try writer.print(" to={s}", .{target});
        }
        try writer.writeAll("\n");
    }
}

pub fn writeGraphJsonPayload(writer: anytype, summary: *const CheckSummary) !void {
    try writer.writeAll("{\"summary\":{");
    try writer.print(
        "\"exported\":{d},\"duplicateExports\":{d},\"unresolvedImports\":{d},\"resolvedImports\":{d},\"internalImports\":{d},\"externalImports\":{d},\"importCycles\":{d},\"reachableSources\":{d},\"unreachableSources\":{d}",
        .{
            summary.exported_symbol_count,
            summary.duplicate_export_count,
            summary.unresolved_import_count,
            summary.resolved_import_count,
            summary.internal_import_count,
            summary.external_import_count,
            summary.import_cycle_count,
            summary.reachable_source_count,
            summary.unreachable_source_count,
        },
    );
    try writer.writeAll("},\"diagnostics\":[");
    for (summary.diagnostics.items, 0..) |diag, index| {
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
    try writer.writeAll("],\"edges\":[");
    for (summary.edges.items, 0..) |edge, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.print(
            "{{\"kind\":\"{s}\",\"from\":",
            .{@tagName(edge.kind)},
        );
        try std.json.encodeJsonString(edge.from_path, .{}, writer);
        try writer.writeAll(",\"specifier\":");
        try std.json.encodeJsonString(edge.specifier, .{}, writer);
        if (edge.target_path) |target| {
            try writer.writeAll(",\"to\":");
            try std.json.encodeJsonString(target, .{}, writer);
        }
        try writer.writeAll("}");
    }
    try writer.writeAll("]}");
}

pub fn writeGraphJson(writer: anytype, summary: *const CheckSummary) !void {
    try writeGraphJsonPayload(writer, summary);
    try writer.writeAll("\n");
}

fn checkImports(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    loaded: *const source.SourceLoadSummary,
    summary: *CheckSummary,
) !void {
    for (loaded.source_files.items) |source_file| {
        for (source_file.declarations.items) |decl| {
            if (decl.kind != .import_stmt and decl.kind != .export_stmt) continue;
            const specifier = decl.module_specifier orelse continue;
            if (try resolveImport(allocator, compile_plan, source_file.path, specifier)) |resolved| {
                defer allocator.free(resolved);
                summary.resolved_import_count += 1;
                const from_index = try graph.findSourceFileIndex(allocator, loaded, source_file.path) orelse continue;
                const to_index = try graph.findSourceFileIndex(allocator, loaded, resolved);
                if (to_index != null) {
                    summary.internal_import_count += 1;
                } else {
                    summary.external_import_count += 1;
                }
                const normalized_from = try normalizePath(allocator, source_file.path);
                errdefer allocator.free(normalized_from);
                const normalized_target = try normalizePath(allocator, resolved);
                errdefer allocator.free(normalized_target);
                try summary.edges.append(.{
                    .from_index = from_index,
                    .to_index = to_index,
                    .specifier = specifier,
                    .from_path = normalized_from,
                    .kind = if (to_index != null) .internal else .external,
                    .target_path = normalized_target,
                });
                continue;
            }

            if (!shouldReportUnresolvedImport(compile_plan, specifier)) continue;

            summary.unresolved_import_count += 1;
            const from_index = try graph.findSourceFileIndex(allocator, loaded, source_file.path) orelse continue;
            const normalized_from = try normalizePath(allocator, source_file.path);
            errdefer allocator.free(normalized_from);
            try summary.edges.append(.{
                .from_index = from_index,
                .to_index = null,
                .specifier = specifier,
                .from_path = normalized_from,
                .kind = .unresolved,
                .target_path = null,
            });
            try summary.diagnostics.append(.{
                .message = try allocator.dupe(u8, "Cannot resolve relative import"),
                .subject = try allocator.dupe(u8, specifier),
                .kind = .unresolved_import,
                .space = null,
                .first_path = try allocator.dupe(u8, source_file.path),
                .second_path = null,
            });
        }
    }

    var analysis = try graph.analyze(allocator, compile_plan, loaded, summary.edges.items);
    defer analysis.deinit(allocator);

    summary.import_cycle_count = analysis.cycle_infos.items.len;
    summary.reachable_source_count = analysis.reachable_source_count;
    summary.unreachable_source_count = analysis.unreachable_source_count;

    for (analysis.cycle_infos.items) |cycle| {
        try summary.diagnostics.append(.{
            .message = try std.fmt.allocPrint(allocator, "Import cycle detected: {s}", .{cycle.path}),
            .subject = try allocator.dupe(u8, loaded.source_files.items[cycle.first_index].path),
            .kind = .import_cycle,
            .space = null,
            .first_path = try allocator.dupe(u8, loaded.source_files.items[cycle.first_index].path),
            .second_path = try allocator.dupe(u8, loaded.source_files.items[cycle.second_index].path),
        });
    }

    for (analysis.unreachable_indices.items) |index| {
        const path = loaded.source_files.items[index].path;
        try summary.diagnostics.append(.{
            .message = try allocator.dupe(u8, "Source file is not reachable from an explicit entry"),
            .subject = try allocator.dupe(u8, path),
            .kind = .unreachable_source,
            .space = null,
            .first_path = try allocator.dupe(u8, path),
            .second_path = null,
        });
    }
}

fn normalizePath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    return std.fs.cwd().realpathAlloc(allocator, path) catch |err| switch (err) {
        error.FileNotFound => std.fs.path.resolve(allocator, &.{path}),
        else => err,
    };
}

fn shouldReportUnresolvedImport(compile_plan: *const plan.CompilePlan, specifier: []const u8) bool {
    if (isRelativeImport(specifier)) return true;
    if (isPackageImportSpecifier(specifier)) return true;
    return findPathMapping(compile_plan, specifier) != null;
}

fn isRelativeImport(specifier: []const u8) bool {
    return std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../");
}

fn isPackageImportSpecifier(specifier: []const u8) bool {
    return specifier.len > 1 and specifier[0] == '#';
}

fn resolveImport(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    source_path: []const u8,
    specifier: []const u8,
) !?[]u8 {
    if (isRelativeImport(specifier)) {
        return resolveRelativeImport(allocator, source_path, specifier);
    }

    if (isPackageImportSpecifier(specifier)) {
        return resolvePackageJsonImport(allocator, source_path, specifier);
    }

    if (try resolvePathMappedImport(allocator, compile_plan, specifier)) |resolved| {
        return resolved;
    }

    if (try resolveBaseUrlImport(allocator, compile_plan, specifier)) |resolved| {
        return resolved;
    }

    if (try resolveNodeModulesImport(allocator, source_path, specifier)) |resolved| {
        return resolved;
    }

    return null;
}

fn resolvePackageJsonImport(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    specifier: []const u8,
) !?[]u8 {
    var current_dir = try allocator.dupe(u8, std.fs.path.dirname(source_path) orelse ".");
    defer allocator.free(current_dir);

    while (true) {
        const package_json_path = try std.fmt.allocPrint(allocator, "{s}/package.json", .{current_dir});
        defer allocator.free(package_json_path);

        const file = std.fs.cwd().openFile(package_json_path, .{}) catch {
            const parent = parentDir(current_dir) orelse break;
            if (std.mem.eql(u8, parent, current_dir)) break;
            const next_dir = try allocator.dupe(u8, parent);
            allocator.free(current_dir);
            current_dir = next_dir;
            continue;
        };
        defer file.close();

        const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(contents);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, contents, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root == .object) {
            if (try resolvePackageJsonImports(allocator, current_dir, root.object, specifier)) |resolved| {
                return resolved;
            }
        }

        break;
    }

    return null;
}

const PackageSpecifier = struct {
    package_name: []const u8,
    subpath: ?[]const u8,
};

fn resolveNodeModulesImport(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    specifier: []const u8,
) !?[]u8 {
    const parsed = parsePackageSpecifier(specifier) orelse return null;
    var current_dir = try allocator.dupe(u8, std.fs.path.dirname(source_path) orelse ".");
    defer allocator.free(current_dir);

    while (true) {
        const package_root = try std.fs.path.join(allocator, &.{ current_dir, "node_modules", parsed.package_name });
        defer allocator.free(package_root);

        if (parsed.subpath) |subpath| {
            const target_path = try std.fs.path.join(allocator, &.{ package_root, subpath });
            defer allocator.free(target_path);

            if (try resolvePackageJsonEntry(allocator, target_path)) |resolved| {
                return resolved;
            }
            if (try resolvePathCandidates(allocator, target_path)) |resolved| {
                return resolved;
            }
        } else {
            if (try resolvePackageJsonEntry(allocator, package_root)) |resolved| {
                return resolved;
            }
            if (try resolvePathCandidates(allocator, package_root)) |resolved| {
                return resolved;
            }
            if (try resolveAtTypesFallback(allocator, current_dir, parsed.package_name)) |resolved| {
                return resolved;
            }
        }

        const parent = parentDir(current_dir) orelse break;
        if (std.mem.eql(u8, parent, current_dir)) break;
        const next_dir = try allocator.dupe(u8, parent);
        allocator.free(current_dir);
        current_dir = next_dir;
    }

    return null;
}

fn resolveAtTypesFallback(
    allocator: std.mem.Allocator,
    current_dir: []const u8,
    package_name: []const u8,
) !?[]u8 {
    const types_package_name = try mangleAtTypesPackageName(allocator, package_name);
    defer allocator.free(types_package_name);

    const package_root = try std.fs.path.join(allocator, &.{ current_dir, "node_modules", "@types", types_package_name });
    defer allocator.free(package_root);

    if (try resolvePackageJsonEntry(allocator, package_root)) |resolved| {
        return resolved;
    }
    if (try resolvePathCandidates(allocator, package_root)) |resolved| {
        return resolved;
    }
    return null;
}

fn mangleAtTypesPackageName(
    allocator: std.mem.Allocator,
    package_name: []const u8,
) ![]u8 {
    if (package_name.len > 0 and package_name[0] == '@') {
        const slash = std.mem.indexOfScalar(u8, package_name, '/') orelse return allocator.dupe(u8, package_name[1..]);
        return std.fmt.allocPrint(allocator, "{s}__{s}", .{
            package_name[1..slash],
            package_name[slash + 1 ..],
        });
    }
    return allocator.dupe(u8, package_name);
}

fn parsePackageSpecifier(specifier: []const u8) ?PackageSpecifier {
    if (specifier.len == 0) return null;
    if (specifier[0] == '.' or specifier[0] == '/' or specifier[0] == '#') return null;

    if (specifier[0] == '@') {
        const first_slash = std.mem.indexOfScalar(u8, specifier, '/') orelse return null;
        const second_rel = std.mem.indexOfScalarPos(u8, specifier, first_slash + 1, '/') orelse {
            return .{ .package_name = specifier, .subpath = null };
        };
        return .{
            .package_name = specifier[0..second_rel],
            .subpath = specifier[second_rel + 1 ..],
        };
    }

    const slash = std.mem.indexOfScalar(u8, specifier, '/') orelse {
        return .{ .package_name = specifier, .subpath = null };
    };
    return .{
        .package_name = specifier[0..slash],
        .subpath = specifier[slash + 1 ..],
    };
}

fn resolveRelativeImport(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    specifier: []const u8,
) !?[]u8 {
    const base_dir = std.fs.path.dirname(source_path) orelse ".";
    const joined = try std.fs.path.join(allocator, &.{ base_dir, specifier });
    defer allocator.free(joined);

    if (try resolvePathCandidates(allocator, joined)) |resolved| {
        return resolved;
    }

    if (try resolvePackageJsonEntry(allocator, joined)) |resolved| {
        return resolved;
    }

    return null;
}

fn resolvePathMappedImport(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    specifier: []const u8,
) !?[]u8 {
    const mapping = findPathMapping(compile_plan, specifier) orelse return null;
    const captures = extractPathCapture(mapping.pattern, specifier) orelse return null;

    const base_root = try baseRootForPlan(allocator, compile_plan);
    defer allocator.free(base_root);

    for (mapping.targets.items) |target_pattern| {
        const target = try substitutePathCapture(allocator, target_pattern, captures);
        defer allocator.free(target);

        const joined = try std.fs.path.join(allocator, &.{ base_root, target });
        defer allocator.free(joined);

        if (try resolvePathCandidates(allocator, joined)) |resolved| {
            return resolved;
        }
        if (try resolvePackageJsonEntry(allocator, joined)) |resolved| {
            return resolved;
        }
    }

    return null;
}

fn resolveBaseUrlImport(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    specifier: []const u8,
) !?[]u8 {
    const base_url = compile_plan.base_url orelse return null;
    const config_dir = compile_plan.config_dir orelse ".";
    const joined_base = try std.fs.path.join(allocator, &.{ config_dir, base_url, specifier });
    defer allocator.free(joined_base);

    if (try resolvePathCandidates(allocator, joined_base)) |resolved| {
        return resolved;
    }
    if (try resolvePackageJsonEntry(allocator, joined_base)) |resolved| {
        return resolved;
    }
    return null;
}

fn baseRootForPlan(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
) ![]u8 {
    const config_dir = compile_plan.config_dir orelse ".";
    if (compile_plan.base_url) |base_url| {
        return std.fs.path.join(allocator, &.{ config_dir, base_url });
    }
    return allocator.dupe(u8, config_dir);
}

fn findPathMapping(
    compile_plan: *const plan.CompilePlan,
    specifier: []const u8,
) ?plan.PathMapping {
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

fn resolvePathCandidates(
    allocator: std.mem.Allocator,
    joined: []const u8,
) !?[]u8 {
    const candidates = [_][]const u8{
        "",
        ".d.ts",
        ".ts",
        ".tsx",
        ".mts",
        ".cts",
        ".js",
        ".jsx",
        ".mjs",
        ".cjs",
        "/index.d.ts",
        "/index.ts",
        "/index.tsx",
        "/index.mts",
        "/index.cts",
        "/index.js",
        "/index.jsx",
        "/index.mjs",
        "/index.cjs",
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

fn resolvePackageJsonEntry(
    allocator: std.mem.Allocator,
    joined: []const u8,
) !?[]u8 {
    var current_dir = try allocator.dupe(u8, joined);
    defer allocator.free(current_dir);

    while (true) {
        const package_json_path = try std.fmt.allocPrint(allocator, "{s}/package.json", .{current_dir});
        defer allocator.free(package_json_path);

        const file = std.fs.cwd().openFile(package_json_path, .{}) catch {
            const parent = parentDir(current_dir) orelse break;
            if (std.mem.eql(u8, parent, current_dir)) break;
            const next_dir = try allocator.dupe(u8, parent);
            allocator.free(current_dir);
            current_dir = next_dir;
            continue;
        };
        defer file.close();

        const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(contents);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, contents, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root == .object) {
            const export_key = try exportKeyForJoinedPath(allocator, current_dir, joined);
            defer allocator.free(export_key);

            if (try resolvePackageJsonExports(allocator, current_dir, root.object, export_key)) |resolved| {
                return resolved;
            }

            if (std.mem.eql(u8, export_key, ".")) {
                if (try resolveLegacyPackageJsonFields(allocator, current_dir, root.object)) |resolved| {
                    return resolved;
                }
            }
        }

        break;
    }

    return null;
}

fn parentDir(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, ".")) return null;
    return std.fs.path.dirname(path) orelse ".";
}

fn exportKeyForJoinedPath(
    allocator: std.mem.Allocator,
    package_root: []const u8,
    joined: []const u8,
) ![]u8 {
    const relative = try std.fs.path.relative(allocator, package_root, joined);
    defer allocator.free(relative);

    if (relative.len == 0 or std.mem.eql(u8, relative, ".")) {
        return allocator.dupe(u8, ".");
    }
    return std.fmt.allocPrint(allocator, "./{s}", .{relative});
}

fn resolvePackageJsonExports(
    allocator: std.mem.Allocator,
    package_root: []const u8,
    object: std.json.ObjectMap,
    export_key: []const u8,
) !?[]u8 {
    const exports_value = object.get("exports") orelse return null;

    if (export_key.len == 1 and export_key[0] == '.') {
        if (try resolvePackageJsonExportTarget(allocator, package_root, exports_value)) |resolved| {
            return resolved;
        }
    }

    if (exports_value != .object) return null;
    if (exports_value.object.get(export_key)) |export_entry| {
        return resolvePackageJsonExportTarget(allocator, package_root, export_entry);
    }

    var iterator = exports_value.object.iterator();
    while (iterator.next()) |entry| {
        const capture = extractPathCapture(entry.key_ptr.*, export_key) orelse continue;
        if (try resolvePackageJsonExportTargetWithCapture(allocator, package_root, entry.value_ptr.*, capture)) |resolved| {
            return resolved;
        }
    }

    return null;
}

fn resolvePackageJsonExportTarget(
    allocator: std.mem.Allocator,
    package_root: []const u8,
    value: std.json.Value,
) !?[]u8 {
    switch (value) {
        .string => |string| {
            return resolvePackageJsonTargetPath(allocator, package_root, string);
        },
        .object => |object| {
            const preferred_fields = [_][]const u8{ "types", "import", "default", "node", "browser", "require" };
            for (preferred_fields) |field| {
                const entry = object.get(field) orelse continue;
                if (entry == .string) {
                    if (try resolvePackageJsonTargetPath(allocator, package_root, entry.string)) |resolved| {
                        return resolved;
                    }
                }
            }
            return null;
        },
        else => return null,
    }
}

fn resolvePackageJsonExportTargetWithCapture(
    allocator: std.mem.Allocator,
    package_root: []const u8,
    value: std.json.Value,
    capture: []const u8,
) !?[]u8 {
    switch (value) {
        .string => |string| {
            const substituted = try substitutePathCapture(allocator, string, capture);
            defer allocator.free(substituted);
            return resolvePackageJsonTargetPath(allocator, package_root, substituted);
        },
        .object => |object| {
            const preferred_fields = [_][]const u8{ "types", "import", "default", "node", "browser", "require" };
            for (preferred_fields) |field| {
                const entry = object.get(field) orelse continue;
                if (entry != .string) continue;
                const substituted = try substitutePathCapture(allocator, entry.string, capture);
                defer allocator.free(substituted);
                if (try resolvePackageJsonTargetPath(allocator, package_root, substituted)) |resolved| {
                    return resolved;
                }
            }
            return null;
        },
        else => return null,
    }
}

fn resolvePackageJsonTargetPath(
    allocator: std.mem.Allocator,
    package_root: []const u8,
    target: []const u8,
) !?[]u8 {
    if (target.len == 0) return null;
    if (std.fs.path.isAbsolute(target)) return null;

    const candidate = try std.fs.path.join(allocator, &.{ package_root, target });
    defer allocator.free(candidate);

    if (try resolvePathCandidates(allocator, candidate)) |resolved| {
        return resolved;
    }
    return null;
}

fn resolveLegacyPackageJsonFields(
    allocator: std.mem.Allocator,
    package_root: []const u8,
    object: std.json.ObjectMap,
) !?[]u8 {
    const preferred_fields = [_][]const u8{ "types", "module", "main" };
    for (preferred_fields) |field| {
        const entry = object.get(field) orelse continue;
        if (entry != .string) continue;
        if (entry.string.len == 0) continue;
        if (std.fs.path.isAbsolute(entry.string)) continue;

        if (try resolvePackageJsonTargetPath(allocator, package_root, entry.string)) |resolved| {
            return resolved;
        }
    }

    return null;
}

fn resolvePackageJsonImports(
    allocator: std.mem.Allocator,
    package_root: []const u8,
    object: std.json.ObjectMap,
    specifier: []const u8,
) !?[]u8 {
    const imports_value = object.get("imports") orelse return null;
    if (imports_value != .object) return null;

    if (imports_value.object.get(specifier)) |entry| {
        return resolvePackageJsonExportTarget(allocator, package_root, entry);
    }

    var iterator = imports_value.object.iterator();
    while (iterator.next()) |entry| {
        const capture = extractPathCapture(entry.key_ptr.*, specifier) orelse continue;
        if (try resolvePackageJsonExportTargetWithCapture(allocator, package_root, entry.value_ptr.*, capture)) |resolved| {
            return resolved;
        }
    }

    return null;
}

fn freeKeyMap(
    allocator: std.mem.Allocator,
    map: *std.StringHashMap(usize),
) void {
    var iterator = map.keyIterator();
    while (iterator.next()) |key_ptr| {
        allocator.free(key_ptr.*);
    }
    map.deinit();
}

test "checker reports duplicate exported symbols in same space" {
    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    try bound.symbols.append(.{
        .name = try std.testing.allocator.dupe(u8, "Foo"),
        .kind = .function_decl,
        .space = .value,
        .exported = true,
        .source_path = try std.testing.allocator.dupe(u8, "a.ts"),
        .line = 1,
        .column = 1,
    });
    try bound.symbols.append(.{
        .name = try std.testing.allocator.dupe(u8, "Foo"),
        .kind = .variable_stmt,
        .space = .value,
        .exported = true,
        .source_path = try std.testing.allocator.dupe(u8, "b.ts"),
        .line = 1,
        .column = 1,
    });

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), summary.exported_symbol_count);
    try std.testing.expectEqual(@as(usize, 1), summary.duplicate_export_count);
    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics.items.len);
}

test "checker allows duplicate export names across value and type spaces" {
    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    try bound.symbols.append(.{
        .name = try std.testing.allocator.dupe(u8, "Foo"),
        .kind = .type_decl,
        .space = .type,
        .exported = true,
        .source_path = try std.testing.allocator.dupe(u8, "a.ts"),
        .line = 1,
        .column = 1,
    });
    try bound.symbols.append(.{
        .name = try std.testing.allocator.dupe(u8, "Foo"),
        .kind = .class_decl,
        .space = .value,
        .exported = true,
        .source_path = try std.testing.allocator.dupe(u8, "b.ts"),
        .line = 1,
        .column = 1,
    });

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), summary.exported_symbol_count);
    try std.testing.expectEqual(@as(usize, 0), summary.duplicate_export_count);
}

test "checker reports unresolved relative imports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./missing"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 24,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 24,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics.items.len);
    try std.testing.expectEqual(CheckDiagnostic.Kind.unresolved_import, summary.diagnostics.items[0].kind);
    try std.testing.expectEqualStrings("./missing", summary.diagnostics.items[0].subject);
}

test "checker accepts resolvable relative imports" {
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

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./lib/util"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 25,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 25,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), summary.resolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker reports unresolved relative re-exports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .export_stmt,
        .exported = true,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./missing"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 28,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/index.ts"),
        .bytes = 28,
        .token_count = 4,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics.items.len);
    try std.testing.expectEqual(CheckDiagnostic.Kind.unresolved_import, summary.diagnostics.items[0].kind);
    try std.testing.expectEqualStrings("./missing", summary.diagnostics.items[0].subject);
}

test "checker accepts declaration file imports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/types");
    {
        var file = try temp.dir.createFile("src/types/api.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Api {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./types/api"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 28,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 28,
        .token_count = 4,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts directory index imports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var file = try temp.dir.createFile("src/lib/index.ts", .{});
        defer file.close();
        try file.writeAll("export const value = 1;\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./lib"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 18,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 18,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts package json types entry" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/pkg/dist");
    {
        var pkg = try temp.dir.createFile("src/pkg/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"types":"./dist/index.d.ts"}
        );
    }
    {
        var file = try temp.dir.createFile("src/pkg/dist/index.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Api {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./pkg"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 18,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 18,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts tsconfig paths mapping" {
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

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "@lib/util"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 24,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 24,
        .token_count = 4,
        .declaration_count = 1,
        .declarations = decls,
    });

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);
    compile_plan.config_dir = try std.testing.allocator.dupe(u8, ".");
    compile_plan.base_url = try std.testing.allocator.dupe(u8, ".");
    var mapping = plan.PathMapping{
        .pattern = try std.testing.allocator.dupe(u8, "@lib/*"),
        .targets = std.ArrayList([]const u8).init(std.testing.allocator),
    };
    try mapping.targets.append(try std.testing.allocator.dupe(u8, "src/lib/*"));
    try compile_plan.path_mappings.append(mapping);

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker reports unresolved tsconfig paths mapping target" {
    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "@lib/missing"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 27,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 27,
        .token_count = 4,
        .declaration_count = 1,
        .declarations = decls,
    });

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);
    compile_plan.config_dir = try std.testing.allocator.dupe(u8, ".");
    compile_plan.base_url = try std.testing.allocator.dupe(u8, ".");
    var mapping = plan.PathMapping{
        .pattern = try std.testing.allocator.dupe(u8, "@lib/*"),
        .targets = std.ArrayList([]const u8).init(std.testing.allocator),
    };
    try mapping.targets.append(try std.testing.allocator.dupe(u8, "src/lib/*"));
    try compile_plan.path_mappings.append(mapping);

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics.items.len);
}

test "checker accepts package json main entry" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/pkg/lib");
    {
        var pkg = try temp.dir.createFile("src/pkg/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"main":"./lib/index.js"}
        );
    }
    {
        var file = try temp.dir.createFile("src/pkg/lib/index.js", .{});
        defer file.close();
        try file.writeAll("export const value = 1;\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./pkg"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 18,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 18,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts package json exports root entry" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/pkg/lib/common");
    {
        var pkg = try temp.dir.createFile("src/pkg/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"exports":{".":{"types":"./lib/common/api.d.ts","default":"./lib/common/api.js"}}}
        );
    }
    {
        var file = try temp.dir.createFile("src/pkg/lib/common/api.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Api {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./pkg"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 18,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 18,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts package json exports subpath entry" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/vendor/pkg/lib/node");
    {
        var pkg = try temp.dir.createFile("src/vendor/pkg/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"exports":{"./node":{"types":"./lib/node/main.d.ts","node":"./lib/node/main.js"}}}
        );
    }
    {
        var file = try temp.dir.createFile("src/vendor/pkg/lib/node/main.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Api {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./vendor/pkg/node"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 30,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 30,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts package json exports wildcard entry" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/vendor/pkg/lib/features");
    {
        var pkg = try temp.dir.createFile("src/vendor/pkg/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"exports":{"./features/*":{"types":"./lib/features/*.d.ts","default":"./lib/features/*.js"}}}
        );
    }
    {
        var file = try temp.dir.createFile("src/vendor/pkg/lib/features/foo.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Foo {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "./vendor/pkg/features/foo"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 38,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 38,
        .token_count = 4,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts package json imports exact entry" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var pkg = try temp.dir.createFile("package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"imports":{"#getExePath":"./src/lib/getExePath.ts"}}
        );
    }
    {
        var file = try temp.dir.createFile("src/lib/getExePath.ts", .{});
        defer file.close();
        try file.writeAll("export const getExePath = 1;\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "#getExePath"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 23,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 23,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts package json imports wildcard entry" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/enums");
    {
        var pkg = try temp.dir.createFile("package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"imports":{"#enums/*":{"types":"./src/enums/*.enum.ts","default":"./src/enums/*.ts"}}}
        );
    }
    {
        var file = try temp.dir.createFile("src/enums/foo.enum.ts", .{});
        defer file.close();
        try file.writeAll("export const Foo = 1;\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "#enums/foo"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 20,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 20,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.diagnostics.items.len);
}

test "checker accepts node_modules bare package" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    try temp.dir.makePath("node_modules/lodash");
    {
        var pkg = try temp.dir.createFile("node_modules/lodash/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"types":"./index.d.ts"}
        );
    }
    {
        var file = try temp.dir.createFile("node_modules/lodash/index.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface LoDashStatic {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "lodash"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 16,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 16,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
    try std.testing.expectEqual(@as(usize, 1), summary.external_import_count);
}

test "checker accepts node_modules scoped package" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    try temp.dir.makePath("node_modules/@types/node");
    {
        var pkg = try temp.dir.createFile("node_modules/@types/node/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"types":"./index.d.ts"}
        );
    }
    {
        var file = try temp.dir.createFile("node_modules/@types/node/index.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Process {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "@types/node"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 21,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 21,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
}

test "checker accepts node_modules package subpath" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    try temp.dir.makePath("node_modules/vscode-jsonrpc/lib/node");
    {
        var pkg = try temp.dir.createFile("node_modules/vscode-jsonrpc/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"exports":{"./node":{"types":"./lib/node/main.d.ts","node":"./lib/node/main.js"}}}
        );
    }
    {
        var file = try temp.dir.createFile("node_modules/vscode-jsonrpc/lib/node/main.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Api {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "vscode-jsonrpc/node"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 26,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 26,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
}

test "checker falls back to @types for bare package" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    try temp.dir.makePath("node_modules/foo");
    try temp.dir.makePath("node_modules/@types/foo");
    {
        var pkg = try temp.dir.createFile("node_modules/foo/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"name":"foo"}
        );
    }
    {
        var types_pkg = try temp.dir.createFile("node_modules/@types/foo/package.json", .{});
        defer types_pkg.close();
        try types_pkg.writeAll(
            \\{"types":"./index.d.ts"}
        );
    }
    {
        var file = try temp.dir.createFile("node_modules/@types/foo/index.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Foo {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "foo"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 12,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 12,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
}

test "checker falls back to @types for scoped package" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    try temp.dir.makePath("node_modules/@scope/pkg");
    try temp.dir.makePath("node_modules/@types/scope__pkg");
    {
        var pkg = try temp.dir.createFile("node_modules/@scope/pkg/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"name":"@scope/pkg"}
        );
    }
    {
        var types_pkg = try temp.dir.createFile("node_modules/@types/scope__pkg/package.json", .{});
        defer types_pkg.close();
        try types_pkg.writeAll(
            \\{"types":"./index.d.ts"}
        );
    }
    {
        var file = try temp.dir.createFile("node_modules/@types/scope__pkg/index.d.ts", .{});
        defer file.close();
        try file.writeAll("export interface Pkg {}\n");
    }

    var loaded = source.SourceLoadSummary.init(std.testing.allocator);
    defer loaded.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .import_stmt,
        .exported = false,
        .name = null,
        .module_specifier = try std.testing.allocator.dupe(u8, "@scope/pkg"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 19,
    });
    try loaded.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "src/main.ts"),
        .bytes = 19,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls,
    });

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), summary.unresolved_import_count);
}

test "checker reports import cycles" {
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
        try a.writeAll("import { b } from \"./b\";\nexport const a = 1;\n");
    }
    {
        var b = try temp.dir.createFile("src/b.ts", .{});
        defer b.close();
        try b.writeAll("import { a } from \"./a\";\nexport const b = 1;\n");
    }

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/a.ts"));
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/b.ts"));

    var loaded = try source.loadSources(std.testing.allocator, &compile_plan);
    defer loaded.deinit(std.testing.allocator);

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), summary.resolved_import_count);
    try std.testing.expectEqual(@as(usize, 2), summary.internal_import_count);
    try std.testing.expectEqual(@as(usize, 1), summary.import_cycle_count);
    try std.testing.expect(summary.diagnostics.items.len >= 1);
    try std.testing.expectEqual(CheckDiagnostic.Kind.import_cycle, summary.diagnostics.items[0].kind);
    try std.testing.expect(std.mem.indexOf(u8, summary.diagnostics.items[0].message, "src/a.ts") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary.diagnostics.items[0].message, "src/b.ts") != null);
}

test "checker reports unreachable sources from explicit entries" {
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
        try a.writeAll("import { b } from \"./b\";\nexport const a = b;\n");
    }
    {
        var b = try temp.dir.createFile("src/b.ts", .{});
        defer b.close();
        try b.writeAll("export const b = 1;\n");
    }
    {
        var c = try temp.dir.createFile("src/c.ts", .{});
        defer c.close();
        try c.writeAll("export const c = 1;\n");
    }

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);
    try compile_plan.cli_entry_files.append(try std.testing.allocator.dupe(u8, "src/a.ts"));
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/a.ts"));
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/b.ts"));
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/c.ts"));

    var loaded = try source.loadSources(std.testing.allocator, &compile_plan);
    defer loaded.deinit(std.testing.allocator);

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), summary.reachable_source_count);
    try std.testing.expectEqual(@as(usize, 1), summary.unreachable_source_count);

    var found = false;
    for (summary.diagnostics.items) |diag| {
        if (diag.kind == .unreachable_source and std.mem.eql(u8, diag.first_path, "src/c.ts")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "checker records graph edge kinds" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    try temp.dir.makePath("node_modules/lodash");
    {
        var main = try temp.dir.createFile("src/main.ts", .{});
        defer main.close();
        try main.writeAll(
            \\import { local } from "./lib/local";
            \\import type { LoDashStatic } from "lodash";
            \\import { missing } from "./missing";
        );
    }
    {
        var local = try temp.dir.createFile("src/lib/local.ts", .{});
        defer local.close();
        try local.writeAll("export const local = 1;\n");
    }
    {
        var pkg = try temp.dir.createFile("node_modules/lodash/package.json", .{});
        defer pkg.close();
        try pkg.writeAll(
            \\{"types":"./index.d.ts"}
        );
    }
    {
        var dts = try temp.dir.createFile("node_modules/lodash/index.d.ts", .{});
        defer dts.close();
        try dts.writeAll("export interface LoDashStatic {}\n");
    }

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/main.ts"));
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/lib/local.ts"));

    var loaded = try source.loadSources(std.testing.allocator, &compile_plan);
    defer loaded.deinit(std.testing.allocator);

    var bound = binder.BindSummary.init(std.testing.allocator);
    defer bound.deinit(std.testing.allocator);

    var summary = try checkProgram(std.testing.allocator, &compile_plan, &loaded, &bound);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), summary.edges.items.len);

    var internal_count: usize = 0;
    var external_count: usize = 0;
    var unresolved_count: usize = 0;
    for (summary.edges.items) |edge| {
        switch (edge.kind) {
            .internal => internal_count += 1,
            .external => external_count += 1,
            .unresolved => unresolved_count += 1,
        }
    }

    try std.testing.expectEqual(@as(usize, 1), internal_count);
    try std.testing.expectEqual(@as(usize, 1), external_count);
    try std.testing.expectEqual(@as(usize, 1), unresolved_count);
}

test "checker writes graph json" {
    var summary = CheckSummary.init(std.testing.allocator);
    defer summary.deinit(std.testing.allocator);

    try summary.edges.append(.{
        .from_index = 0,
        .to_index = 1,
        .specifier = "foo",
        .from_path = try std.testing.allocator.dupe(u8, "/tmp/a.ts"),
        .kind = .internal,
        .target_path = try std.testing.allocator.dupe(u8, "/tmp/b.ts"),
    });
    try summary.edges.append(.{
        .from_index = 0,
        .to_index = null,
        .specifier = "./missing",
        .from_path = try std.testing.allocator.dupe(u8, "/tmp/a.ts"),
        .kind = .unresolved,
        .target_path = null,
    });
    try summary.diagnostics.append(.{
        .message = try std.testing.allocator.dupe(u8, "Cannot resolve relative import"),
        .subject = try std.testing.allocator.dupe(u8, "./missing"),
        .kind = .unresolved_import,
        .space = null,
        .first_path = try std.testing.allocator.dupe(u8, "/tmp/a.ts"),
        .second_path = null,
    });
    summary.unresolved_import_count = 1;
    summary.resolved_import_count = 1;
    summary.internal_import_count = 1;

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try writeGraphJson(buffer.writer(), &summary);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"summary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"diagnostics\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"edges\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"unresolvedImports\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"kind\":\"unresolved_import\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"kind\":\"internal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"kind\":\"unresolved\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"to\":\"/tmp/b.ts\"") != null);
}

