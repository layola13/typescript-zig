const std = @import("std");

pub const DeclarationKind = enum {
    import_stmt,
    variable_stmt,
    function_decl,
    class_decl,
    interface_decl,
    type_decl,
    export_stmt,
};

pub const SourcePosition = struct {
    offset: usize,
    line: usize,
    column: usize,
};

pub const Declaration = struct {
    kind: DeclarationKind,
    exported: bool = false,
    name: ?[]const u8 = null,
    module_specifier: ?[]const u8 = null,
    start: SourcePosition,
    end_offset: usize,
    initializer: ?[]const u8 = null,
    type_annotation: ?[]const u8 = null,
};


/// Parse variable declaration parts
pub fn parseVariableParts(contents: []const u8, start: usize, end: usize) struct { initializer: ?[]const u8, type_annotation: ?[]const u8 } {
    var type_annotation: ?[]const u8 = null;
    var initializer: ?[]const u8 = null;
    var eq_pos: ?usize = null;
    var colon_pos: ?usize = null;
    for (start..end) |i| {
        if (contents[i] == ':') colon_pos = i;
        if (contents[i] == '=') eq_pos = i;
    }
    if (colon_pos) |cp| type_annotation = std.mem.trim(u8, contents[cp+1..end], " ");
    if (eq_pos) |ep| initializer = std.mem.trim(u8, contents[ep+1..end], " ");
    return .{ .initializer = initializer, .type_annotation = type_annotation };
}
pub const ParseResult = struct {
    declarations: std.ArrayList(Declaration),

    pub fn init(allocator: std.mem.Allocator) ParseResult {
        return .{
            .declarations = std.ArrayList(Declaration).init(allocator),
        };
    }

    pub fn deinit(self: *ParseResult, allocator: std.mem.Allocator) void {
        for (self.declarations.items) |decl| {
            if (decl.name) |name| allocator.free(name);
            if (decl.module_specifier) |specifier| allocator.free(specifier);
            if (decl.initializer) |init_| allocator.free(init_);
            if (decl.type_annotation) |ta| allocator.free(ta);
        }
        self.declarations.deinit();
    }

    pub fn summary(self: *const ParseResult) ParseSummary {
        var stats = ParseSummary{};
        for (self.declarations.items) |decl| {
            stats.declaration_count += 1;
            if (decl.exported) stats.export_count += 1;
            switch (decl.kind) {
                .import_stmt => stats.import_count += 1,
                .variable_stmt => stats.variable_count += 1,
                .function_decl => stats.function_count += 1,
                .class_decl => stats.class_count += 1,
                .interface_decl => stats.interface_count += 1,
                .type_decl => stats.type_count += 1,
                .export_stmt => {},
            }
        }
        return stats;
    }
};

pub const ParseSummary = struct {
    declaration_count: usize = 0,
    import_count: usize = 0,
    export_count: usize = 0,
    function_count: usize = 0,
    class_count: usize = 0,
    interface_count: usize = 0,
    type_count: usize = 0,
    variable_count: usize = 0,
};

pub fn cloneDeclarations(
    allocator: std.mem.Allocator,
    declarations: []const Declaration,
) !std.ArrayList(Declaration) {
    var cloned = std.ArrayList(Declaration).init(allocator);
    errdefer {
        for (cloned.items) |decl| {
            if (decl.name) |name| allocator.free(name);
            if (decl.module_specifier) |specifier| allocator.free(specifier);
        }
        cloned.deinit();
    }

    for (declarations) |decl| {
        try cloned.append(.{
            .kind = decl.kind,
            .exported = decl.exported,
            .name = if (decl.name) |name| try allocator.dupe(u8, name) else null,
            .module_specifier = if (decl.module_specifier) |specifier| try allocator.dupe(u8, specifier) else null,
            .start = decl.start,
            .end_offset = decl.end_offset,
        });
    }

    return cloned;
}

pub fn freeDeclarations(
    allocator: std.mem.Allocator,
    declarations: *std.ArrayList(Declaration),
) void {
    for (declarations.items) |decl| {
        if (decl.name) |name| allocator.free(name);
        if (decl.module_specifier) |specifier| allocator.free(specifier);
        if (decl.initializer) |init_| allocator.free(init_);
        if (decl.type_annotation) |ta| allocator.free(ta);
    }
    declarations.deinit();
}

pub fn parseTopLevel(allocator: std.mem.Allocator, contents: []const u8) !ParseResult {
    var result = ParseResult.init(allocator);
    errdefer result.deinit(allocator);

    var brace_depth: usize = 0;
    var i: usize = 0;
    var line_start = true;
    var in_line_comment = false;
    var in_block_comment = false;
    var in_single = false;
    var in_double = false;
    var in_template = false;
    var escaped = false;
    var pending_export = false;
    var pending_export_start: usize = 0;

    while (i < contents.len) : (i += 1) {
        const ch = contents[i];
        const next = if (i + 1 < contents.len) contents[i + 1] else 0;

        if (in_line_comment) {
            if (ch == '\n') {
                in_line_comment = false;
                line_start = true;
                pending_export = false;
            }
            continue;
        }

        if (in_block_comment) {
            if (ch == '*' and next == '/') {
                in_block_comment = false;
                i += 1;
            }
            continue;
        }

        if (in_single or in_double or in_template) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if ((in_single and ch == '\'') or (in_double and ch == '"') or (in_template and ch == '`')) {
                in_single = false;
                in_double = false;
                in_template = false;
            }
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

        if (ch == '\n' or ch == '\r') {
            line_start = true;
            pending_export = false;
            continue;
        }

        if (std.ascii.isWhitespace(ch)) {
            continue;
        }

        if (ch == '{') {
            brace_depth += 1;
            line_start = false;
            continue;
        }
        if (ch == '}') {
            if (brace_depth > 0) brace_depth -= 1;
            line_start = false;
            continue;
        }

        if (ch == '\'') {
            in_single = true;
            line_start = false;
            continue;
        }
        if (ch == '"') {
            in_double = true;
            line_start = false;
            continue;
        }
        if (ch == '`') {
            in_template = true;
            line_start = false;
            continue;
        }

        if (brace_depth == 0 and (line_start or pending_export)) {
            if (readIdentifier(contents, i)) |identifier| {
                const ident = identifier.value;
                const start_offset = if (pending_export) pending_export_start else i;
                i = identifier.end - 1;
                line_start = false;

                if (std.mem.eql(u8, ident, "export")) {
                    pending_export = true;
                    pending_export_start = identifier.start;
                    continue;
                }

                if (std.mem.eql(u8, ident, "import")) {
                    try appendDeclaration(
                        allocator,
                        &result,
                        contents,
                        .import_stmt,
                        pending_export,
                        start_offset,
                        identifier.end,
                        null,
                        try extractModuleSpecifier(allocator, contents, identifier.end, .import_stmt),
                    );
                    pending_export = false;
                    continue;
                }
                if (
                    pending_export and
                    std.mem.eql(u8, ident, "type") and
                    nextNonWhitespaceChar(contents, identifier.end) == '{'
                ) {
                    try appendDeclaration(
                        allocator,
                        &result,
                        contents,
                        .export_stmt,
                        true,
                        start_offset,
                        identifier.end,
                        null,
                        try extractModuleSpecifier(allocator, contents, pending_export_start, .export_stmt),
                    );
                    pending_export = false;
                    continue;
                }
                if (std.mem.eql(u8, ident, "function")) {
                    const name = nextIdentifier(contents, identifier.end);
                    try appendDeclaration(allocator, &result, contents, .function_decl, pending_export, start_offset, identifier.end, name, null);
                    pending_export = false;
                    continue;
                }
                if (std.mem.eql(u8, ident, "class")) {
                    const name = nextIdentifier(contents, identifier.end);
                    try appendDeclaration(allocator, &result, contents, .class_decl, pending_export, start_offset, identifier.end, name, null);
                    pending_export = false;
                    continue;
                }
                if (std.mem.eql(u8, ident, "interface")) {
                    const name = nextIdentifier(contents, identifier.end);
                    try appendDeclaration(allocator, &result, contents, .interface_decl, pending_export, start_offset, identifier.end, name, null);
                    pending_export = false;
                    continue;
                }
                if (std.mem.eql(u8, ident, "type")) {
                    const name = nextIdentifier(contents, identifier.end);
                    try appendDeclaration(allocator, &result, contents, .type_decl, pending_export, start_offset, identifier.end, name, null);
                    pending_export = false;
                    continue;
                }
                if (std.mem.eql(u8, ident, "const") or std.mem.eql(u8, ident, "let") or std.mem.eql(u8, ident, "var")) {
                    const name = nextIdentifier(contents, identifier.end);
                    // Find end of statement (semicolon or end of line)
                    var end_pos = identifier.end;
                    while (end_pos < contents.len and contents[end_pos] != ';' and contents[end_pos] != '\n') end_pos += 1;
                    const parts = parseVariableParts(contents, identifier.end, end_pos);
                    try appendDeclEx(allocator, &result, contents, .variable_stmt, pending_export, start_offset, end_pos, name, null, parts.initializer, parts.type_annotation);
                    pending_export = false;
                    continue;
                }

                if (pending_export) {
                    try appendDeclaration(
                        allocator,
                        &result,
                        contents,
                        .export_stmt,
                        true,
                        start_offset,
                        identifier.end,
                        null,
                        try extractModuleSpecifier(allocator, contents, pending_export_start, .export_stmt),
                    );
                    pending_export = false;
                }
                continue;
            }
        }

        line_start = false;
        if (pending_export and ch == ';') {
            try appendDeclaration(
                allocator,
                &result,
                contents,
                .export_stmt,
                true,
                pending_export_start,
                i + 1,
                null,
                try extractModuleSpecifier(allocator, contents, pending_export_start, .export_stmt),
            );
            pending_export = false;
        }
    }

    if (pending_export) {
        try appendDeclaration(
            allocator,
            &result,
            contents,
            .export_stmt,
            true,
            pending_export_start,
            contents.len,
            null,
            try extractModuleSpecifier(allocator, contents, pending_export_start, .export_stmt),
        );
    }

    return result;
}

const Identifier = struct {
    start: usize,
    value: []const u8,
    end: usize,
};

fn appendDeclaration(
    allocator: std.mem.Allocator,
    result: *ParseResult,
    contents: []const u8,
    kind: DeclarationKind,
    exported: bool,
    start_offset: usize,
    end_offset: usize,
    name: ?Identifier,
    module_specifier: ?[]const u8,
) !void {
    try result.declarations.append(.{
        .kind = kind,
        .exported = exported,
        .name = if (name) |value| try allocator.dupe(u8, value.value) else null,
        .module_specifier = module_specifier,
        .start = positionAt(contents, start_offset),
        .end_offset = if (name) |value| value.end else end_offset,
    });
}

/// Append declaration with full options including initializer and type
fn appendDeclEx(
    allocator: std.mem.Allocator,
    result: *ParseResult,
    contents: []const u8,
    kind: DeclarationKind,
    exported: bool,
    start_offset: usize,
    end_offset: usize,
    name: ?Identifier,
    module_specifier: ?[]const u8,
    initializer: ?[]const u8,
    type_annotation: ?[]const u8,
) !void {
    try result.declarations.append(.{
        .kind = kind,
        .exported = exported,
        .name = if (name) |value| try allocator.dupe(u8, value.value) else null,
        .module_specifier = module_specifier,
        .start = positionAt(contents, start_offset),
        .end_offset = if (name) |value| value.end else end_offset,
        .initializer = if (initializer) |v| try allocator.dupe(u8, v) else null,
        .type_annotation = if (type_annotation) |v| try allocator.dupe(u8, v) else null,
    });
}

fn extractModuleSpecifier(
    allocator: std.mem.Allocator,
    contents: []const u8,
    from: usize,
    kind: DeclarationKind,
) !?[]const u8 {
    var i = from;
    var in_line_comment = false;
    var in_block_comment = false;
    var saw_from = false;
    var saw_significant = false;

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

        if (ch == ';') break;
        if (std.ascii.isWhitespace(ch)) continue;

        if (readIdentifier(contents, i)) |identifier| {
            if (std.mem.eql(u8, identifier.value, "from")) {
                saw_from = true;
            } else if (
                kind == .export_stmt and
                (std.mem.eql(u8, identifier.value, "export") or std.mem.eql(u8, identifier.value, "type"))
            ) {
                // Ignore re-export modifiers.
            } else if (!std.mem.eql(u8, identifier.value, "type")) {
                saw_significant = true;
            }
            i = identifier.end - 1;
            continue;
        }

        if (ch == '\'' or ch == '"') {
            if (readStringLiteral(contents, i)) |literal| {
                if (saw_from or !saw_significant) {
                    return try allocator.dupe(u8, literal.value);
                }
                i = literal.end - 1;
                continue;
            }
            return null;
        }

        if (!std.ascii.isWhitespace(ch)) {
            saw_significant = true;
        }
    }

    return null;
}

const StringLiteral = struct {
    value: []const u8,
    end: usize,
};

fn readStringLiteral(contents: []const u8, start: usize) ?StringLiteral {
    if (start >= contents.len) return null;
    const quote = contents[start];
    if (quote != '\'' and quote != '"') return null;

    var i = start + 1;
    var escaped = false;
    while (i < contents.len) : (i += 1) {
        const ch = contents[i];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (ch == '\\') {
            escaped = true;
            continue;
        }
        if (ch == quote) {
            return .{
                .value = contents[start + 1 .. i],
                .end = i + 1,
            };
        }
    }
    return null;
}

fn nextIdentifier(contents: []const u8, from: usize) ?Identifier {
    var i = from;
    while (i < contents.len) : (i += 1) {
        if (std.ascii.isWhitespace(contents[i])) continue;
        return readIdentifier(contents, i);
    }
    return null;
}

fn nextNonWhitespaceChar(contents: []const u8, from: usize) u8 {
    var i = from;
    while (i < contents.len) : (i += 1) {
        if (!std.ascii.isWhitespace(contents[i])) return contents[i];
    }
    return 0;
}

fn readIdentifier(contents: []const u8, start: usize) ?Identifier {
    if (start >= contents.len or !isIdentifierStart(contents[start])) return null;
    var i = start + 1;
    while (i < contents.len and isIdentifierContinue(contents[i])) : (i += 1) {}
    return .{ .start = start, .value = contents[start..i], .end = i };
}

fn positionAt(contents: []const u8, offset: usize) SourcePosition {
    var line: usize = 1;
    var column: usize = 1;
    var i: usize = 0;
    while (i < offset and i < contents.len) : (i += 1) {
        if (contents[i] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{ .offset = offset, .line = line, .column = column };
}

fn isIdentifierStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
}

fn isIdentifierContinue(ch: u8) bool {
    return isIdentifierStart(ch) or std.ascii.isDigit(ch);
}

test "parse top level declaration counts" {
    var parsed = try parseTopLevel(
        std.testing.allocator,
        \\import { x } from "./x";
        \\export const value = 1;
        \\function run() {}
        \\class Box {}
        \\interface Shape {}
        \\type Name = string;
    );
    defer parsed.deinit(std.testing.allocator);

    const summary = parsed.summary();
    try std.testing.expectEqual(@as(usize, 6), summary.declaration_count);
    try std.testing.expectEqual(@as(usize, 1), summary.import_count);
    try std.testing.expectEqual(@as(usize, 1), summary.export_count);
    try std.testing.expectEqual(@as(usize, 1), summary.function_count);
    try std.testing.expectEqual(@as(usize, 1), summary.class_count);
    try std.testing.expectEqual(@as(usize, 1), summary.interface_count);
    try std.testing.expectEqual(@as(usize, 1), summary.type_count);
    try std.testing.expectEqual(@as(usize, 1), summary.variable_count);
}

test "parse top level declarations keep exported variable as one node" {
    var parsed = try parseTopLevel(
        std.testing.allocator,
        \\export const value = 1;
        \\export function run() {}
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.declarations.items.len);
    try std.testing.expectEqual(DeclarationKind.variable_stmt, parsed.declarations.items[0].kind);
    try std.testing.expect(parsed.declarations.items[0].exported);
    try std.testing.expectEqualStrings("value", parsed.declarations.items[0].name.?);
    try std.testing.expectEqual(DeclarationKind.function_decl, parsed.declarations.items[1].kind);
    try std.testing.expect(parsed.declarations.items[1].exported);
    try std.testing.expectEqualStrings("run", parsed.declarations.items[1].name.?);
}

test "declarations include location metadata" {
    var parsed = try parseTopLevel(
        std.testing.allocator,
        \\import { x } from "./x";
        \\class Box {}
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), parsed.declarations.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.declarations.items[0].start.line);
    try std.testing.expectEqual(@as(usize, 1), parsed.declarations.items[0].start.column);
    try std.testing.expectEqual(@as(usize, 2), parsed.declarations.items[1].start.line);
    try std.testing.expectEqualStrings("Box", parsed.declarations.items[1].name.?);
}

test "import type is not misclassified as top level type declaration" {
    var parsed = try parseTopLevel(
        std.testing.allocator,
        \\import type { Foo } from "./foo";
        \\import { Bar } from "./bar";
    );
    defer parsed.deinit(std.testing.allocator);

    const summary = parsed.summary();
    try std.testing.expectEqual(@as(usize, 2), summary.declaration_count);
    try std.testing.expectEqual(@as(usize, 2), summary.import_count);
    try std.testing.expectEqual(@as(usize, 0), summary.type_count);
}

test "import declarations capture module specifiers" {
    var parsed = try parseTopLevel(
        std.testing.allocator,
        \\import { Foo } from "./foo";
        \\import "./side-effect";
        \\import type { Bar } from "../bar";
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), parsed.declarations.items.len);
    try std.testing.expectEqualStrings("./foo", parsed.declarations.items[0].module_specifier.?);
    try std.testing.expectEqualStrings("./side-effect", parsed.declarations.items[1].module_specifier.?);
    try std.testing.expectEqualStrings("../bar", parsed.declarations.items[2].module_specifier.?);
}

test "export declarations capture re-export module specifiers" {
    var parsed = try parseTopLevel(
        std.testing.allocator,
        \\export * from "./foo";
        \\export { Bar } from "../bar";
        \\export type { Baz } from "./baz";
        \\export { localValue };
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), parsed.declarations.items.len);
    try std.testing.expectEqual(DeclarationKind.export_stmt, parsed.declarations.items[0].kind);
    try std.testing.expectEqualStrings("./foo", parsed.declarations.items[0].module_specifier.?);
    try std.testing.expectEqualStrings("../bar", parsed.declarations.items[1].module_specifier.?);
    try std.testing.expectEqualStrings("./baz", parsed.declarations.items[2].module_specifier.?);
    try std.testing.expect(parsed.declarations.items[3].module_specifier == null);
}
