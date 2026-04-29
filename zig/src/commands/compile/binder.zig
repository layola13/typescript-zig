const std = @import("std");
const source = @import("./source.zig");
const parser = @import("./parser.zig");

pub const SymbolSpace = enum {
    value,
    type,
};

pub const BoundSymbol = struct {
    name: []const u8,
    kind: parser.DeclarationKind,
    space: SymbolSpace,
    exported: bool,
    source_path: []const u8,
    line: usize,
    column: usize,
};

pub const BoundDiagnostic = struct {
    message: []const u8,
    name: []const u8,
    first_path: []const u8,
    second_path: []const u8,
};

pub const BindSummary = struct {
    symbol_count: usize = 0,
    exported_symbol_count: usize = 0,
    value_symbol_count: usize = 0,
    type_symbol_count: usize = 0,
    duplicate_count: usize = 0,
    symbols: std.ArrayList(BoundSymbol),
    diagnostics: std.ArrayList(BoundDiagnostic),

    pub fn init(allocator: std.mem.Allocator) BindSummary {
        return .{
            .symbol_count = 0,
            .exported_symbol_count = 0,
            .value_symbol_count = 0,
            .type_symbol_count = 0,
            .duplicate_count = 0,
            .symbols = std.ArrayList(BoundSymbol).init(allocator),
            .diagnostics = std.ArrayList(BoundDiagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *BindSummary, allocator: std.mem.Allocator) void {
        for (self.symbols.items) |symbol| {
            allocator.free(symbol.name);
            allocator.free(symbol.source_path);
        }
        self.symbols.deinit();
        for (self.diagnostics.items) |diag| {
            allocator.free(diag.message);
            allocator.free(diag.name);
            allocator.free(diag.first_path);
            allocator.free(diag.second_path);
        }
        self.diagnostics.deinit();
    }
};

pub fn bindProgram(
    allocator: std.mem.Allocator,
    summary: *const source.SourceLoadSummary,
) !BindSummary {
    var bound = BindSummary.init(allocator);
    errdefer bound.deinit(allocator);

    var seen_value = std.StringHashMap(usize).init(allocator);
    var seen_type = std.StringHashMap(usize).init(allocator);
    defer {
        var value_iterator = seen_value.keyIterator();
        while (value_iterator.next()) |key_ptr| {
            allocator.free(key_ptr.*);
        }
        seen_value.deinit();
        var type_iterator = seen_type.keyIterator();
        while (type_iterator.next()) |key_ptr| {
            allocator.free(key_ptr.*);
        }
        seen_type.deinit();
    }

    for (summary.source_files.items) |source_file| {
        for (source_file.declarations.items) |decl| {
            if (decl.name == null) continue;

            const name = decl.name.?;
            const spaces = symbolSpacesForKind(decl.kind);
            for (spaces) |space| {
                if (space == null) continue;
                const resolved_space = space.?;
                const next_index = bound.symbols.items.len;
                try bound.symbols.append(.{
                    .name = try allocator.dupe(u8, name),
                    .kind = decl.kind,
                    .space = resolved_space,
                    .exported = decl.exported,
                    .source_path = try allocator.dupe(u8, source_file.path),
                    .line = decl.start.line,
                    .column = decl.start.column,
                });
                bound.symbol_count += 1;
                if (decl.exported) bound.exported_symbol_count += 1;
                switch (resolved_space) {
                    .value => bound.value_symbol_count += 1,
                    .type => bound.type_symbol_count += 1,
                }

                const seen = switch (resolved_space) {
                    .value => &seen_value,
                    .type => &seen_type,
                };
                if (seen.get(name)) |existing_index| {
                    bound.duplicate_count += 1;
                    const first = bound.symbols.items[existing_index];
                    const second = bound.symbols.items[next_index];
                    try bound.diagnostics.append(.{
                        .message = try std.fmt.allocPrint(allocator, "Duplicate {s}-space top-level symbol", .{@tagName(resolved_space)}),
                        .name = try allocator.dupe(u8, name),
                        .first_path = try allocator.dupe(u8, first.source_path),
                        .second_path = try allocator.dupe(u8, second.source_path),
                    });
                } else {
                    try seen.put(try allocator.dupe(u8, name), next_index);
                }
            }
        }
    }

    return bound;
}

pub fn writeSummary(writer: anytype, bound: *const BindSummary) !void {
    try writer.print(
        "zts: bind summary(symbols={d}, exported={d}, value={d}, type={d}, duplicates={d})\n",
        .{
            bound.symbol_count,
            bound.exported_symbol_count,
            bound.value_symbol_count,
            bound.type_symbol_count,
            bound.duplicate_count,
        },
    );

    const preview_count = @min(bound.symbols.items.len, 8);
    for (bound.symbols.items[0..preview_count]) |symbol| {
        try writer.print(
            "zts: symbol {s}:{d}:{d} space={s} kind={s} name={s}",
            .{
                symbol.source_path,
                symbol.line,
                symbol.column,
                @tagName(symbol.space),
                declarationKindLabel(symbol.kind),
                symbol.name,
            },
        );
        if (symbol.exported) {
            try writer.writeAll(" exported");
        }
        try writer.writeAll("\n");
    }

    for (bound.diagnostics.items) |diag| {
        try writer.print(
            "zts: bind diagnostic {s}: {s} ({s}, {s})\n",
            .{ diag.name, diag.message, diag.first_path, diag.second_path },
        );
    }
}

fn symbolSpacesForKind(kind: parser.DeclarationKind) [2]?SymbolSpace {
    return switch (kind) {
        .variable_stmt, .function_decl => .{ .value, null },
        .interface_decl, .type_decl => .{ .type, null },
        .class_decl => .{ .value, .type },
        else => .{ null, null },
    };
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

test "bind program collects symbols and duplicate diagnostics" {
    var summary = source.SourceLoadSummary.init(std.testing.allocator);
    defer summary.deinit(std.testing.allocator);

    var decls_one = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls_one.append(.{
        .kind = .function_decl,
        .exported = true,
        .name = try std.testing.allocator.dupe(u8, "run"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 10,
    });
    try summary.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "a.ts"),
        .bytes = 10,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls_one,
    });

    var decls_two = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls_two.append(.{
        .kind = .function_decl,
        .exported = false,
        .name = try std.testing.allocator.dupe(u8, "run"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 10,
    });
    try summary.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "b.ts"),
        .bytes = 10,
        .token_count = 3,
        .declaration_count = 1,
        .declarations = decls_two,
    });

    var bound = try bindProgram(std.testing.allocator, &summary);
    defer bound.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), bound.symbol_count);
    try std.testing.expectEqual(@as(usize, 1), bound.exported_symbol_count);
    try std.testing.expectEqual(@as(usize, 2), bound.value_symbol_count);
    try std.testing.expectEqual(@as(usize, 0), bound.type_symbol_count);
    try std.testing.expectEqual(@as(usize, 1), bound.duplicate_count);
    try std.testing.expectEqual(@as(usize, 1), bound.diagnostics.items.len);
}

test "type and value spaces are tracked separately" {
    var summary = source.SourceLoadSummary.init(std.testing.allocator);
    defer summary.deinit(std.testing.allocator);

    var decls = std.ArrayList(parser.Declaration).init(std.testing.allocator);
    try decls.append(.{
        .kind = .type_decl,
        .exported = false,
        .name = try std.testing.allocator.dupe(u8, "Foo"),
        .start = .{ .offset = 0, .line = 1, .column = 1 },
        .end_offset = 8,
    });
    try decls.append(.{
        .kind = .variable_stmt,
        .exported = false,
        .name = try std.testing.allocator.dupe(u8, "Foo"),
        .start = .{ .offset = 9, .line = 2, .column = 1 },
        .end_offset = 18,
    });
    try summary.source_files.append(.{
        .path = try std.testing.allocator.dupe(u8, "spaces.ts"),
        .bytes = 18,
        .token_count = 6,
        .declaration_count = 2,
        .declarations = decls,
    });

    var bound = try bindProgram(std.testing.allocator, &summary);
    defer bound.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), bound.symbol_count);
    try std.testing.expectEqual(@as(usize, 1), bound.value_symbol_count);
    try std.testing.expectEqual(@as(usize, 1), bound.type_symbol_count);
    try std.testing.expectEqual(@as(usize, 0), bound.duplicate_count);
}
