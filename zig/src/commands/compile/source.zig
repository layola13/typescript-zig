const std = @import("std");
const plan = @import("./plan.zig");
const tokenizer = @import("./tokenizer.zig");
const parser = @import("./parser.zig");

pub const SourceDiagnostic = struct {
    path: []const u8,
    message: []const u8,
};

pub const SourceFile = struct {
    path: []const u8,
    bytes: usize,
    token_count: usize,
    declaration_count: usize,
    declarations: std.ArrayList(parser.Declaration),
};

pub const LoadedSource = SourceFile;

pub const SourceLoadSummary = struct {
    loaded_count: usize = 0,
    loaded_bytes: usize = 0,
    token_count: usize = 0,
    keyword_count: usize = 0,
    declaration_count: usize = 0,
    import_count: usize = 0,
    export_count: usize = 0,
    function_count: usize = 0,
    class_count: usize = 0,
    source_files: std.ArrayList(SourceFile),
    diagnostics: std.ArrayList(SourceDiagnostic),

    pub fn init(allocator: std.mem.Allocator) SourceLoadSummary {
        return .{
            .loaded_count = 0,
            .loaded_bytes = 0,
            .token_count = 0,
            .keyword_count = 0,
            .declaration_count = 0,
            .import_count = 0,
            .export_count = 0,
            .function_count = 0,
            .class_count = 0,
            .source_files = std.ArrayList(SourceFile).init(allocator),
            .diagnostics = std.ArrayList(SourceDiagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *SourceLoadSummary, allocator: std.mem.Allocator) void {
        for (self.source_files.items) |source| {
            allocator.free(source.path);
            var decls = source.declarations;
            parser.freeDeclarations(allocator, &decls);
        }
        self.source_files.deinit();
        for (self.diagnostics.items) |diag| {
            allocator.free(diag.path);
            allocator.free(diag.message);
        }
        self.diagnostics.deinit();
    }
};

pub fn loadSources(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
) !SourceLoadSummary {
    var summary = SourceLoadSummary.init(allocator);
    errdefer summary.deinit(allocator);

    for (compile_plan.discovered_sources.items) |source_path| {
        const result = try tryReadFile(allocator, source_path);
        switch (result) {
            .success => |source_info| {
                var token_summary = try tokenizer.tokenize(allocator, source_info.contents);
                defer token_summary.deinit(allocator);
                var parse_result = try parser.parseTopLevel(allocator, source_info.contents);
                defer parse_result.deinit(allocator);
                const parse_summary = parse_result.summary();
                summary.loaded_count += 1;
                summary.loaded_bytes += source_info.bytes;
                summary.token_count += token_summary.token_count;
                summary.keyword_count += token_summary.keyword_count;
                summary.declaration_count += parse_summary.declaration_count;
                summary.import_count += parse_summary.import_count;
                summary.export_count += parse_summary.export_count;
                summary.function_count += parse_summary.function_count;
                summary.class_count += parse_summary.class_count;
                try summary.source_files.append(.{
                    .path = try allocator.dupe(u8, source_path),
                    .bytes = source_info.bytes,
                    .token_count = token_summary.token_count,
                    .declaration_count = parse_summary.declaration_count,
                    .declarations = try parser.cloneDeclarations(allocator, parse_result.declarations.items),
                });
                try scanSource(allocator, &summary, source_path, source_info.contents);
                for (token_summary.diagnostics.items) |diag| {
                    try appendDiagnostic(allocator, &summary, source_path, diag);
                }
                allocator.free(source_info.contents);
            },
            .failure => |message| {
                errdefer allocator.free(message);
                try summary.diagnostics.append(.{
                    .path = try allocator.dupe(u8, source_path),
                    .message = message,
                });
            },
        }
    }

    return summary;
}

pub fn writeSummary(
    writer: anytype,
    compile_plan: *const plan.CompilePlan,
    summary: *const SourceLoadSummary,
) !void {
    try writer.print(
        "zts: source summary(discovered={d}, loaded={d}, bytes={d}, diagnostics={d})\n",
        .{
            compile_plan.discovered_sources.items.len,
            summary.loaded_count,
            summary.loaded_bytes,
            summary.diagnostics.items.len,
        },
    );
    try writer.print(
        "zts: token summary(tokens={d}, keywords={d})\n",
        .{ summary.token_count, summary.keyword_count },
    );
    try writer.print(
        "zts: parse summary(decls={d}, imports={d}, exports={d}, functions={d}, classes={d})\n",
        .{
            summary.declaration_count,
            summary.import_count,
            summary.export_count,
            summary.function_count,
            summary.class_count,
        },
    );

    for (summary.diagnostics.items) |diag| {
        try writer.print("zts: diagnostic {s}: {s}\n", .{ diag.path, diag.message });
    }

    for (summary.source_files.items) |source_file| {
        const preview_count = @min(source_file.declarations.items.len, 3);
        for (source_file.declarations.items[0..preview_count]) |decl| {
            try writer.print(
                "zts: decl {s}:{d}:{d} kind={s}",
                .{
                    source_file.path,
                    decl.start.line,
                    decl.start.column,
                    declarationKindLabel(decl.kind),
                },
            );
            if (decl.exported) {
                try writer.writeAll(" exported");
            }
            if (decl.name) |name| {
                try writer.print(" name={s}", .{name});
            }
            try writer.writeAll("\n");
        }
    }
}

const ReadResult = union(enum) {
    success: struct {
        bytes: usize,
        contents: []u8,
    },
    failure: []u8,
};

fn tryReadFile(allocator: std.mem.Allocator, path: []const u8) !ReadResult {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return .{ .failure = try allocator.dupe(u8, @errorName(err)) };
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch |err| {
        return .{ .failure = try allocator.dupe(u8, @errorName(err)) };
    };
    return .{ .success = .{
        .bytes = contents.len,
        .contents = contents,
    } };
}

fn scanSource(
    allocator: std.mem.Allocator,
    summary: *SourceLoadSummary,
    path: []const u8,
    contents: []const u8,
) !void {
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var i: usize = 0;
    var in_line_comment = false;
    var in_block_comment = false;
    var in_single = false;
    var in_double = false;
    var in_template = false;
    var escaped = false;

    while (i < contents.len) : (i += 1) {
        const ch = contents[i];
        const next = if (i + 1 < contents.len) contents[i + 1] else 0;

        if (in_line_comment) {
            if (ch == '\n') in_line_comment = false;
            continue;
        }

        if (in_block_comment) {
            if (ch == '*' and next == '/') {
                in_block_comment = false;
                i += 1;
            }
            continue;
        }

        if (in_single) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if (ch == '\'') in_single = false;
            continue;
        }

        if (in_double) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if (ch == '"') in_double = false;
            continue;
        }

        if (in_template) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if (ch == '`') in_template = false;
            continue;
        }

        if (ch == '/' and next == '/') {
            in_line_comment = true;
            i += 1;
            continue;
        }

        if (ch == '/' and next == '*') {
            in_block_comment = true;
            i += 1;
            continue;
        }

        switch (ch) {
            '\'' => in_single = true,
            '"' => in_double = true,
            '`' => in_template = true,
            '(' => paren_depth += 1,
            ')' => if (paren_depth == 0) {
                try appendDiagnostic(allocator, summary, path, "Unmatched closing parenthesis");
            } else {
                paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => if (brace_depth == 0) {
                try appendDiagnostic(allocator, summary, path, "Unmatched closing brace");
            } else {
                brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => if (bracket_depth == 0) {
                try appendDiagnostic(allocator, summary, path, "Unmatched closing bracket");
            } else {
                bracket_depth -= 1;
            },
            else => {},
        }
    }

    if (in_block_comment) try appendDiagnostic(allocator, summary, path, "Unterminated block comment");
    if (in_single) try appendDiagnostic(allocator, summary, path, "Unterminated single-quoted string");
    if (in_double) try appendDiagnostic(allocator, summary, path, "Unterminated double-quoted string");
    if (in_template) try appendDiagnostic(allocator, summary, path, "Unterminated template string");
    if (paren_depth > 0) try appendDiagnostic(allocator, summary, path, "Unclosed parenthesis");
    if (brace_depth > 0) try appendDiagnostic(allocator, summary, path, "Unclosed brace");
    if (bracket_depth > 0) try appendDiagnostic(allocator, summary, path, "Unclosed bracket");
}

fn appendDiagnostic(
    allocator: std.mem.Allocator,
    summary: *SourceLoadSummary,
    path: []const u8,
    message: []const u8,
) !void {
    for (summary.diagnostics.items) |existing| {
        if (std.mem.eql(u8, existing.path, path) and std.mem.eql(u8, existing.message, message)) {
            return;
        }
    }
    try summary.diagnostics.append(.{
        .path = try allocator.dupe(u8, path),
        .message = try allocator.dupe(u8, message),
    });
}

fn declarationKindLabel(kind: parser.DeclarationKind) []const u8 {
    return switch (kind) {
        .import_stmt => "import",
        .variable_stmt => "variable",
        .function_decl => "function",
        .class_decl => "class",
        .interface_decl => "interface",
        .type_decl => "type",
        .export_stmt => "export",
    };
}

test "load sources records missing files as diagnostics" {
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

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/main.ts"));
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/missing.ts"));

    var summary = try loadSources(std.testing.allocator, &compile_plan);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), summary.loaded_count);
    try std.testing.expect(summary.loaded_bytes > 0);
    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics.items.len);
    try std.testing.expectEqualStrings("src/missing.ts", summary.diagnostics.items[0].path);
    try std.testing.expect(summary.token_count > 0);
    try std.testing.expect(summary.declaration_count > 0);
    try std.testing.expectEqualStrings("value", summary.source_files.items[0].declarations.items[0].name.?);
}

test "scan source reports unclosed syntax constructs" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var file = try temp.dir.createFile("src/bad.ts", .{});
        defer file.close();
        try file.writeAll("export const broken = { value: \"x\";\n/*\n");
    }

    var compile_plan = plan.CompilePlan.init(std.testing.allocator);
    defer compile_plan.deinit(std.testing.allocator);
    try compile_plan.discovered_sources.append(try std.testing.allocator.dupe(u8, "src/bad.ts"));

    var summary = try loadSources(std.testing.allocator, &compile_plan);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), summary.loaded_count);
    try std.testing.expect(summary.diagnostics.items.len >= 2);
}

test "duplicate diagnostics are deduplicated" {
    var summary = SourceLoadSummary.init(std.testing.allocator);
    defer summary.deinit(std.testing.allocator);

    try appendDiagnostic(std.testing.allocator, &summary, "a.ts", "Unterminated block comment");
    try appendDiagnostic(std.testing.allocator, &summary, "a.ts", "Unterminated block comment");

    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics.items.len);
}
