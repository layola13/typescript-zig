const std = @import("std");
const plan = @import("./plan.zig");
const source = @import("./source.zig");

pub const EmitResult = struct {
    js_output: std.ArrayList(u8),
    dts_output: std.ArrayList(u8),
    diagnostics: std.ArrayList(EmitDiagnostic),
    exit_code: u8 = 0,

    pub fn init(allocator: std.mem.Allocator) EmitResult {
        return .{
            .js_output = std.ArrayList(u8).init(allocator),
            .dts_output = std.ArrayList(u8).init(allocator),
            .diagnostics = std.ArrayList(EmitDiagnostic).init(allocator),
        };
    }

    pub fn deinit(self: *EmitResult) void {
        self.js_output.deinit();
        self.dts_output.deinit();
        for (self.diagnostics.items) |diag| {
            std.heap.page_allocator.free(diag.path);
            std.heap.page_allocator.free(diag.message);
        }
        self.diagnostics.deinit();
    }
};

pub const EmitDiagnostic = struct {
    path: []const u8,
    message: []const u8,
};

pub const EmitOptions = struct {
    emit_declarations: bool = true,
    emit_js: bool = true,
    out_dir: ?[]const u8 = null,
    root_dir: ?[]const u8 = null,
    config_dir: ?[]const u8 = null,
};


pub fn emitProgram(
    allocator: std.mem.Allocator,
    
    loaded: *const source.SourceLoadSummary,
    options: EmitOptions,
) !EmitResult {
    var result = EmitResult.init(allocator);
    errdefer result.deinit();

    for (loaded.source_files.items) |source_file| {
        if (options.emit_js) {
            try emitJsFile(allocator, &result, source_file.path, options.out_dir, options.config_dir, options.root_dir);
        }

        if (options.emit_declarations) {
            try emitDtsFile(allocator, &result, source_file.path, options.out_dir, options.config_dir, options.root_dir);
        }
    }

    return result;
}

fn emitJsFile(
    allocator: std.mem.Allocator,
    result: *EmitResult,
    source_path: []const u8,
    out_dir: ?[]const u8,
    config_dir: ?[]const u8,
    root_dir: ?[]const u8,
) !void {
    const contents = std.fs.cwd().readFileAlloc(allocator, source_path, 4 * 1024 * 1024) catch {
        try result.diagnostics.append(.{
            .path = try allocator.dupe(u8, source_path),
            .message = try allocator.dupe(u8, "cannot read source file for emit"),
        });
        return;
    };
    defer allocator.free(contents);

    var emitter = TypeScriptEmitter.init(allocator, contents);
    const js_code = emitter.emit() catch {
        try result.diagnostics.append(.{
            .path = try allocator.dupe(u8, source_path),
            .message = try allocator.dupe(u8, "emission failed"),
        });
        return;
    };
    defer allocator.free(js_code);

    try result.js_output.writer().print("/// {s}\n{s}", .{ source_path, js_code });
    // Write to file if out_dir is specified
    if (out_dir) |dir| {
        const abs_out_dir = if (std.fs.path.isAbsolute(dir)) try allocator.dupe(u8, dir) else if (config_dir) |cd| try std.fs.path.join(allocator, &.{ cd, dir }) else try std.fs.path.resolve(allocator, &.{dir});
        const js_path = try computeOutputPath(allocator, source_path, abs_out_dir, config_dir, root_dir, ".js");
        defer allocator.free(abs_out_dir);
        defer allocator.free(js_path);
        // Create parent directory if needed
        const parent = std.fs.path.dirname(js_path);
        try std.fs.cwd().makePath(parent orelse ".");
        const file = try std.fs.cwd().createFile(js_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(js_code);
    }
}

fn computeOutputPath(allocator: std.mem.Allocator, source_path: []const u8, out_dir: []const u8, config_dir: ?[]const u8, root_dir: ?[]const u8, ext: []const u8) ![]u8 {
    // Compute relative path from config_dir + root_dir if available
    var relative_path: []const u8 = source_path;
    if (config_dir != null and root_dir != null) {
        // Build absolute root path
        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.process.getCwd(&cwd_buffer);
        var abs_cwd: []u8 = undefined;
        if (std.fs.path.isAbsolute(config_dir orelse unreachable)) { // config_dir already absolute
                abs_cwd = try allocator.dupe(u8, config_dir.?);
            } else {
                abs_cwd = try std.fs.path.join(allocator, &.{ cwd, config_dir.? });
        }
        defer allocator.free(abs_cwd);

        const abs_root: []u8 = if (std.fs.path.isAbsolute(root_dir orelse unreachable))
            try std.fs.path.join(allocator, &.{ abs_cwd, root_dir orelse unreachable })
        else
            try std.fs.path.join(allocator, &.{ abs_cwd, root_dir orelse unreachable });
        defer allocator.free(abs_root);

        // Normalize source_path to absolute
        const abs_source: []u8 = if (std.fs.path.isAbsolute(source_path))
            try std.fs.path.resolve(allocator, &.{source_path})
        else
            try std.fs.path.join(allocator, &.{ cwd, source_path });
        defer allocator.free(abs_source);

        // Strip abs_root prefix if it matches
        if (std.mem.startsWith(u8, abs_source, abs_root)) {
            relative_path = abs_source[abs_root.len..];
            if (relative_path.len > 0 and relative_path[0] == std.fs.path.sep) {
                relative_path = relative_path[1..];
            }
        }
    }
    // Get filename without extension
    var filename = std.fs.path.basename(relative_path);
    // Remove .ts extension
    if (std.mem.endsWith(u8, filename, ".ts")) {
        filename = filename[0..filename.len - 3];
    } else if (std.mem.endsWith(u8, filename, ".tsx")) {
        filename = filename[0..filename.len - 4];
    }
    // Build output path
    const basename = try std.mem.concat(allocator, u8, &.{ filename, ext });
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ out_dir, basename });
    return output_path;
}

fn emitDtsFile(
    allocator: std.mem.Allocator,
    result: *EmitResult,
    source_path: []const u8,
    out_dir: ?[]const u8,
    config_dir: ?[]const u8,
    root_dir: ?[]const u8,
) !void {
    std.debug.print("zts-emit: out_dir={s} config_dir={s} root_dir={s}\n", .{
        out_dir orelse "null",
        config_dir orelse "null",
        root_dir orelse "null",
    });
    const contents = std.fs.cwd().readFileAlloc(allocator, source_path, 4 * 1024 * 1024) catch {
        return;
    };
    defer allocator.free(contents);

    var emitter = TypeScriptEmitter.init(allocator, contents);
    const dts_code = emitter.emitDeclarations() catch return;
    defer allocator.free(dts_code);

    if (dts_code.len > 0) {
        try result.dts_output.writer().print("/// {s}\n{s}", .{ source_path, dts_code });

        // Write to file if out_dir is specified
        if (out_dir) |dir| {
        const abs_out_dir = if (std.fs.path.isAbsolute(dir)) try allocator.dupe(u8, dir) else if (config_dir) |cd| try std.fs.path.join(allocator, &.{ cd, dir }) else try std.fs.path.resolve(allocator, &.{dir});
            const dts_path = try computeOutputPath(allocator, source_path, abs_out_dir, config_dir, root_dir, ".d.ts");
            defer allocator.free(abs_out_dir);
            defer allocator.free(dts_path);
            const file = try std.fs.cwd().createFile(dts_path, .{ .truncate = true });
            defer file.close();
            try file.writeAll(dts_code);
        }
    }
}

pub const TypeScriptEmitter = struct {
    allocator: std.mem.Allocator,
    contents: []const u8,
    pos: usize = 0,
    is_declaration: bool = false,
    in_class_body: bool = false,
    class_body_brace_depth: usize = 0,
    in_import_or_export_region: bool = false,

    pub fn init(allocator: std.mem.Allocator, contents: []const u8) TypeScriptEmitter {
        return .{
            .allocator = allocator,
            .contents = contents,
            .pos = 0,
            .is_declaration = false,
            .in_class_body = false,
            .class_body_brace_depth = 0,
            .in_import_or_export_region = false,
        };
    }

    pub fn emit(self: *TypeScriptEmitter) ![]u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        var at_stmt_start = true;
        var brace_depth: usize = 0;

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];

            if (ch == '\n') {
                try output.writer().writeAll("\n");
                self.pos += 1;
                at_stmt_start = true;
                continue;
            }

            if (ch == '/') {
                self.pos += 1;
                if (self.pos < self.contents.len) {
                    const next_ch = self.contents[self.pos];
                    if (next_ch == '/') {
                        while (self.pos < self.contents.len and self.contents[self.pos] != '\n') {
                            self.pos += 1;
                        }
                        continue;
                    } else if (next_ch == '*') {
                        // Check if this is a JSDoc comment
                        if (self.pos < self.contents.len and self.contents[self.pos] == '*') {
                            // Try to preserve JSDoc for declarations at statement start
                            if (at_stmt_start) {
                                try output.writer().writeAll("/**");
                                self.pos += 2;
                                while (self.pos + 1 < self.contents.len) {
                                    if (self.contents[self.pos] == '*' and self.contents[self.pos + 1] == '/') {
                                        try output.writer().writeAll("*/");
                                        self.pos += 2;
                                        break;
                                    }
                                    try output.writer().writeByte(self.contents[self.pos]);
                                    self.pos += 1;
                                }
                                continue;
                            }
                        }
                        self.pos += 1;
                        while (self.pos + 1 < self.contents.len) {
                            if (self.contents[self.pos] == '*' and self.contents[self.pos + 1] == '/') {
                                self.pos += 2;
                                break;
                            }
                            self.pos += 1;
                        }
                        continue;
                    }
                }
                try output.writer().writeByte('/');
                continue;
            }

            if (ch == '\'' or ch == '"' or ch == '`') {
                const quote = ch;
                try output.writer().writeByte(ch);
                self.pos += 1;
                while (self.pos < self.contents.len) {
                    const c = self.contents[self.pos];
                    if (c == '\\') {
                        try output.writer().writeByte(c);
                        self.pos += 1;
                        if (self.pos < self.contents.len) {
                            try output.writer().writeByte(self.contents[self.pos]);
                            self.pos += 1;
                        }
                        continue;
                    }
                    if (c == quote) {
                        try output.writer().writeByte(c);
                        self.pos += 1;
                        break;
                    }
                    try output.writer().writeByte(c);
                    self.pos += 1;
                }
                continue;
            }

            // Decorator at statement start: skip @expression and any following newlines
            if (ch == '@' and at_stmt_start) {
                self.pos += 1;
                // Skip whitespace and newlines after decorator
                while (self.pos < self.contents.len) {
                    const c = self.contents[self.pos];
                    if (std.ascii.isWhitespace(c)) {
                        self.pos += 1;
                    } else if (c == '/' and self.pos + 1 < self.contents.len) {
                        const next = self.contents[self.pos + 1];
                        if (next == '/') {
                            while (self.pos < self.contents.len and self.contents[self.pos] != '\n') self.pos += 1;
                        } else if (next == '*') {
                            self.pos += 2;
                            while (self.pos + 1 < self.contents.len) {
                                if (self.contents[self.pos] == '*' and self.contents[self.pos + 1] == '/') {
                                    self.pos += 2;
                                    break;
                                }
                                self.pos += 1;
                            }
                        } else break;
                    } else break;
                }
                // Skip the decorator expression itself
                if (self.pos < self.contents.len) {
                    // Simple decorator: just an identifier
                    if (std.ascii.isAlphabetic(self.contents[self.pos]) or self.contents[self.pos] == '_' or self.contents[self.pos] == '$') {
                        while (self.pos < self.contents.len) {
                            const c = self.contents[self.pos];
                            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                                self.pos += 1;
                            } else break;
                        }
                        // Check for call expression (...)
                        if (self.pos < self.contents.len and self.contents[self.pos] == '(') {
                            var paren_depth: usize = 1;
                            self.pos += 1;
                            while (self.pos < self.contents.len and paren_depth > 0) {
                                const c = self.contents[self.pos];
                                if (c == '\\') {
                                    self.pos += 2;
                                    continue;
                                }
                                if (c == '\'' or c == '"' or c == '`') {
                                    const quote = c;
                                    self.pos += 1;
                                    while (self.pos < self.contents.len and self.contents[self.pos] != quote) {
                                        if (self.contents[self.pos] == '\\') self.pos += 1;
                                        self.pos += 1;
                                    }
                                    if (self.pos < self.contents.len) self.pos += 1;
                                } else if (c == '(') {
                                    paren_depth += 1;
                                    self.pos += 1;
                                } else if (c == ')') {
                                    paren_depth -= 1;
                                    self.pos += 1;
                                } else {
                                    self.pos += 1;
                                }
                            }
                        }
                    }
                }
                at_stmt_start = true;
                continue;
            }

            if (std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$') {
                const word_start = self.pos;
                while (self.pos < self.contents.len) {
                    const c = self.contents[self.pos];
                    if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
                const word = self.contents[word_start..self.pos];

                // Type-only keyword at statement start -> skip entirely
                if (at_stmt_start and isTypeOnlyKeyword(word)) {
                    try self.skipTypeDeclJS(word);
                    at_stmt_start = false;
                    continue;
                }

                // Import keyword at statement start: track for as-alias handling
                if (at_stmt_start and std.mem.eql(u8, word, "import")) {
                    try output.writer().writeAll(word);
                    self.in_import_or_export_region = true;
                    at_stmt_start = false;
                    // Strip `type` keyword after import (import type { X } → import { X })
                    const after_import = self.pos;
                    try self.skipWhitespaceAndComments();
                    if (self.pos < self.contents.len) {
                        const peek_start = self.pos;
                        if (std.ascii.isAlphabetic(self.contents[self.pos]) or self.contents[self.pos] == '_' or self.contents[self.pos] == '$') {
                            while (self.pos < self.contents.len) {
                                const c = self.contents[self.pos];
                                if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                                    self.pos += 1;
                                } else break;
                            }
                            if (std.mem.eql(u8, self.contents[peek_start..self.pos], "type")) {
                                continue;
                            }
                        }
                    }
                    self.pos = after_import;
                    continue;
                }

                // Export keyword: look ahead to check if followed by type-only
                if (at_stmt_start and std.mem.eql(u8, word, "export")) {
                    const after_export = self.pos;
                    try self.skipWhitespaceAndComments();
                    if (self.pos < self.contents.len) {
                        const peek_start = self.pos;
                        if (std.ascii.isAlphabetic(self.contents[self.pos]) or self.contents[self.pos] == '_' or self.contents[self.pos] == '$') {
                            while (self.pos < self.contents.len) {
                                const c = self.contents[self.pos];
                                if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                                    self.pos += 1;
                                } else break;
                            }
                            const next_word = self.contents[peek_start..self.pos];
                            if (isTypeOnlyKeyword(next_word)) {
                                // Check for export type { X } or export type * (re-export, not type alias)
                                if (std.mem.eql(u8, next_word, "type")) {
                                    try self.skipWhitespaceAndComments();
                                    if (self.pos < self.contents.len and (self.contents[self.pos] == '{' or self.contents[self.pos] == '*')) {
                                        self.pos = word_start;
                                        if (self.matchWord("export")) {
                                            _ = self.matchWord("type");
                                            try output.writer().writeAll("export");
                                            self.in_import_or_export_region = true;
                                            at_stmt_start = false;
                                            continue;
                                        }
                                    }
                                }
                                // Type-only declaration (interface, type alias) — skip entirely
                                self.pos = word_start;
                                if (self.matchWord("export")) {
                                    if (self.matchWord("interface") or self.matchWord("type")) {
                                        try self.skipTypeDeclJS(next_word);
                                    }
                                }
                                at_stmt_start = false;
                                continue;
                            }
                            if (std.mem.eql(u8, next_word, "declare")) {
                                self.pos = word_start;
                                if (self.matchWord("export")) {
                                    try self.skipWhitespaceAndComments();
                                }
                                self.skipDeclareDeclaration();
                                at_stmt_start = false;
                                continue;
                            }
                        }
                        // Check if export is followed by { or * (specifier list)
                        if (self.pos < self.contents.len) {
                            if (self.contents[self.pos] == '{' or self.contents[self.pos] == '*') {
                                self.in_import_or_export_region = true;
                            }
                        }
                    }
                    // Not followed by type-only or declare: output "export"
                    self.pos = after_export;
                    try output.writer().writeAll(word);
                    at_stmt_start = true;
                    continue;
                }

                // In class body: handle abstract keyword (may be method or class)
                if (at_stmt_start and self.in_class_body and std.mem.eql(u8, word, "abstract")) {
                    // Look ahead: if next word is "class", strip abstract only
                    const saved = self.pos;
                    try self.skipWhitespaceAndComments();
                    if (self.pos < self.contents.len) {
                        const la_start = self.pos;
                        if (std.ascii.isAlphabetic(self.contents[self.pos]) or self.contents[self.pos] == '_' or self.contents[self.pos] == '$') {
                            while (self.pos < self.contents.len) {
                                const c = self.contents[self.pos];
                                if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                                    self.pos += 1;
                                } else break;
                            }
                            if (std.mem.eql(u8, self.contents[la_start..self.pos], "class")) {
                                // abstract class — strip "abstract" only
                                self.pos = la_start;
                                at_stmt_start = true;
                                continue;
                            }
                        }
                    }
                    // Abstract method — skip entire declaration to ;
                    self.pos = saved;
                    while (self.pos < self.contents.len) {
                        if (self.contents[self.pos] == ';') {
                            self.pos += 1;
                            break;
                        }
                        if (self.contents[self.pos] == '}') break;
                        self.pos += 1;
                    }
                    at_stmt_start = false;
                    continue;
                }

                // In class body: strip TypeScript-only member modifiers
                if (at_stmt_start and self.in_class_body and isClassMemberModifier(word)) {
                    // Consume trailing whitespace after stripped modifier
                    while (self.pos < self.contents.len and std.ascii.isWhitespace(self.contents[self.pos])) {
                        self.pos += 1;
                    }
                    at_stmt_start = true;
                    continue;
                }

                // Abstract keyword at statement start: strip before class
                if (at_stmt_start and std.mem.eql(u8, word, "abstract")) {
                    const after_abstract = self.pos;
                    try self.skipWhitespaceAndComments();
                    if (self.pos < self.contents.len) {
                        const peek_start = self.pos;
                        if (std.ascii.isAlphabetic(self.contents[self.pos]) or self.contents[self.pos] == '_' or self.contents[self.pos] == '$') {
                            while (self.pos < self.contents.len) {
                                const c = self.contents[self.pos];
                                if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                                    self.pos += 1;
                                } else break;
                            }
                            const next_word = self.contents[peek_start..self.pos];
                            if (std.mem.eql(u8, next_word, "class")) {
                                self.pos = peek_start; // restore before "class"
                                at_stmt_start = true;
                                continue;
                            }
                        }
                    }
                    // Not followed by class: output "abstract"
                    self.pos = after_abstract;
                    try output.writer().writeAll(word);
                    at_stmt_start = false;
                    continue;
                }

                // Declare keyword at statement start: strip entire declaration
                if (at_stmt_start and std.mem.eql(u8, word, "declare")) {
                    self.pos = word_start + word.len;
                    try self.skipWhitespaceAndComments();
                    self.skipDeclareDeclaration();
                    at_stmt_start = false;
                    continue;
                }

                // Type assertions: skip "as Type" or "satisfies Type"
                if (!at_stmt_start and !self.in_import_or_export_region) {
                    if (std.mem.eql(u8, word, "as")) {
                        try output.writer().writeByte(' ');
                        try self.skipWhitespaceAndComments();
                        try self.skipTypeAnnotation(";,)]}=>");
                        at_stmt_start = false;
                        continue;
                    }
                    if (std.mem.eql(u8, word, "satisfies")) {
                        var lookback = word_start;
                        while (lookback > 0) {
                            lookback -= 1;
                            if (!std.ascii.isWhitespace(self.contents[lookback])) break;
                        }
                        const prev = self.contents[lookback];
                        const is_expr_end = std.ascii.isAlphanumeric(prev) or prev == '_' or prev == '$' or prev == ')' or prev == ']';
                        if (is_expr_end) {
                            try self.skipWhitespaceAndComments();
                            try self.skipTypeAnnotation(";,)]}=>");
                            at_stmt_start = false;
                            continue;
                        }
                    }
                }

                try output.writer().writeAll(word);
                try self.emitPostKeywordJS(&output, word);
                if (std.mem.eql(u8, word, "class")) {
                    self.in_class_body = true;
                }
                at_stmt_start = false;
                continue;
            }

            if (ch == '{') {
                try output.writer().writeByte(ch);
                self.pos += 1;
                brace_depth += 1;
                if (self.in_class_body and self.class_body_brace_depth == 0) {
                    self.class_body_brace_depth = brace_depth;
                }
                at_stmt_start = true;
                continue;
            }

            if (ch == '}') {
                try output.writer().writeByte(ch);
                self.pos += 1;
                if (brace_depth > 0) brace_depth -= 1;
                if (self.class_body_brace_depth > 0 and brace_depth < self.class_body_brace_depth) {
                    self.class_body_brace_depth = 0;
                }
                if (brace_depth == 0) self.in_class_body = false;
                at_stmt_start = brace_depth > 0;
                continue;
            }

            if (ch == ';') {
                try output.writer().writeByte(ch);
                self.pos += 1;
                self.in_import_or_export_region = false;
                at_stmt_start = true;
                continue;
            }

            // Inside a block (class body, etc.), handle parens with type stripping
            // Arrow function: look ahead for => after matching )
            if (ch == '(' and brace_depth == 0) {
                var la = self.pos + 1;
                var paren_d: usize = 1;
                while (la < self.contents.len and paren_d > 0) {
                    switch (self.contents[la]) {
                        '(' => paren_d += 1,
                        ')' => paren_d -= 1,
                        '\'', '"', '`' => {
                            const q = self.contents[la];
                            la += 1;
                            while (la < self.contents.len and self.contents[la] != q) {
                                if (self.contents[la] == '\\') la += 1;
                                la += 1;
                            }
                        },
                        else => {},
                    }
                    la += 1;
                }
                // Skip whitespace and comments after )
                while (la < self.contents.len) {
                    if (std.ascii.isWhitespace(self.contents[la])) { la += 1; continue; }
                    if (self.contents[la] == '/' and la + 1 < self.contents.len) {
                        if (self.contents[la + 1] == '/') {
                            la += 2;
                            while (la < self.contents.len and self.contents[la] != '\n') la += 1;
                            continue;
                        } else if (self.contents[la + 1] == '*') {
                            la += 2;
                            while (la + 1 < self.contents.len) {
                                if (self.contents[la] == '*' and self.contents[la + 1] == '/') { la += 2; break; }
                                la += 1;
                            }
                            continue;
                        }
                    }
                    break;
                }
                // Skip return type annotation if present
                if (la < self.contents.len and self.contents[la] == ':') {
                    la += 1;
                    var depth: usize = 0;
                    var in_str: bool = false;
                    var str_c: u8 = 0;
                    while (la < self.contents.len) {
                        const c = self.contents[la];
                        if (in_str) {
                            if (c == str_c) in_str = false;
                        } else {
                            switch (c) {
                                '\'', '"', '`' => { in_str = true; str_c = c; },
                                '<', '{', '(', '[' => depth += 1,
                                '>', '}', ')', ']' => { if (depth > 0) depth -= 1; },
                                ';', '=' => { if (depth == 0) break; },
                                else => {},
                            }
                        }
                        la += 1;
                    }
                }
                // Skip whitespace again after return type
                while (la < self.contents.len and std.ascii.isWhitespace(self.contents[la])) la += 1;
                if (la + 1 < self.contents.len and self.contents[la] == '=' and self.contents[la + 1] == '>') {
                    try output.writer().writeByte('(');
                    self.pos += 1;
                    try self.emitParamListJS(&output);
                    try self.emitWhitespaceAndComments(&output);
                    if (self.pos < self.contents.len and self.contents[self.pos] == ':') {
                        self.pos += 1;
                        try self.skipTypeAnnotation("{;=");
                    }
                    continue;
                }
            }

            if (ch == '(' and self.in_class_body) {
                try output.writer().writeByte('(');
                self.pos += 1;
                try self.emitParamListJS(&output);
                // Strip return type annotation after method params
                try self.emitWhitespaceAndComments(&output);
                if (self.pos < self.contents.len and self.contents[self.pos] == ':') {
                    self.pos += 1;
                    try self.skipTypeAnnotation("{;");
                }
                continue;
            }

            // Property type annotation in class body: strip ": Type" down to = or ;
            if (ch == ':' and self.class_body_brace_depth > 0 and brace_depth == self.class_body_brace_depth) {
                self.pos += 1;
                try self.skipWhitespaceAndComments();
                try self.skipTypeAnnotation(";=");
                continue;
            }

            // Non-null assertion: skip postfix ! (but not != or !== operators)
            if (ch == '!' and self.pos > 0) {
                if (self.pos + 1 < self.contents.len and self.contents[self.pos + 1] == '=') {
                    // != or !== operator — do not strip
                } else {
                    var lookback = self.pos;
                    while (lookback > 0) {
                        lookback -= 1;
                        if (!std.ascii.isWhitespace(self.contents[lookback])) break;
                    }
                    const prev = self.contents[lookback];
                    const is_expr_end = std.ascii.isAlphanumeric(prev) or prev == '_' or prev == '$' or prev == ')' or prev == ']';
                    if (is_expr_end) {
                        self.pos += 1;
                        continue;
                    }
                }
            }

            try output.writer().writeByte(ch);
            self.pos += 1;
        }

        return output.toOwnedSlice();
    }

    fn emitWhitespaceAndComments(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];
            if (std.ascii.isWhitespace(ch)) {
                try output.writer().writeByte(ch);
                self.pos += 1;
            } else if (ch == '/' and self.pos + 1 < self.contents.len) {
                const next = self.contents[self.pos + 1];
                if (next == '/') {
                    try output.writer().writeAll("//");
                    self.pos += 2;
                    while (self.pos < self.contents.len and self.contents[self.pos] != '\n') {
                        try output.writer().writeByte(self.contents[self.pos]);
                        self.pos += 1;
                    }
                } else if (next == '*') {
                    try output.writer().writeAll("/*");
                    self.pos += 2;
                    while (self.pos + 1 < self.contents.len) {
                        if (self.contents[self.pos] == '*' and self.contents[self.pos + 1] == '/') {
                            try output.writer().writeAll("*/");
                            self.pos += 2;
                            break;
                        }
                        try output.writer().writeByte(self.contents[self.pos]);
                        self.pos += 1;
                    }
                } else break;
            } else break;
        }
    }

    fn emitPostKeywordJS(self: *TypeScriptEmitter, output: *std.ArrayList(u8), word: []const u8) !void {
        if (isVarKeyword(word)) {
            try self.emitVarDeclJS(output);
        } else if (std.mem.eql(u8, word, "function")) {
            try self.emitFunctionJS(output);
        } else if (std.mem.eql(u8, word, "class")) {
            try self.emitClassJS(output);
        }
    }

    fn emitVarDeclJS(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        try self.emitWhitespaceAndComments(output);
        if (self.pos >= self.contents.len) return;

        const ch = self.contents[self.pos];
        if (ch == '{' or ch == '[') {
            try self.emitDestructuringPatternJS(output);
        } else if (std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$') {
            const name_start = self.pos;
            while (self.pos < self.contents.len) {
                const c = self.contents[self.pos];
                if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                    self.pos += 1;
                } else break;
            }
            try output.writer().writeAll(self.contents[name_start..self.pos]);
        }

        try self.skipWhitespaceAndComments();
        if (self.pos < self.contents.len and self.contents[self.pos] == ':') {
            self.pos += 1;
            try self.skipTypeAnnotation("=;");
        }
    }

    fn emitDestructuringPatternJS(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        const open = self.contents[self.pos];
        const close: u8 = if (open == '{') '}' else ']';
        try output.writer().writeByte(open);
        self.pos += 1;
        var depth: usize = 1;

        while (self.pos < self.contents.len and depth > 0) {
            const c = self.contents[self.pos];
            if (c == '\'' or c == '"' or c == '`') {
                try output.writer().writeByte(c);
                self.pos += 1;
                while (self.pos < self.contents.len and self.contents[self.pos] != c) {
                    try output.writer().writeByte(self.contents[self.pos]);
                    self.pos += 1;
                }
                if (self.pos < self.contents.len) {
                    try output.writer().writeByte(self.contents[self.pos]);
                    self.pos += 1;
                }
                continue;
            }
            if (c == open) {
                depth += 1;
                try output.writer().writeByte(c);
                self.pos += 1;
            } else if (c == close) {
                depth -= 1;
                if (depth == 0) {
                    try output.writer().writeByte(c);
                    self.pos += 1;
                    break;
                }
                try output.writer().writeByte(c);
                self.pos += 1;
            } else if (c == ':' and depth == 1) {
                try output.writer().writeByte(c);
                self.pos += 1;
            } else {
                try output.writer().writeByte(c);
                self.pos += 1;
            }
        }
    }

    fn emitFunctionJS(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        try self.emitWhitespaceAndComments(output);
        if (self.pos >= self.contents.len) return;

        // Skip type params <...>
        if (self.contents[self.pos] == '<') {
            try self.skipTypeParams();
            try self.skipWhitespaceAndComments();
        }

        // Read function name
        if (self.pos < self.contents.len) {
            const c = self.contents[self.pos];
            if (std.ascii.isAlphabetic(c) or c == '_' or c == '$') {
                const name_start = self.pos;
                while (self.pos < self.contents.len) {
                    const ch = self.contents[self.pos];
                    if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$') {
                        self.pos += 1;
                    } else break;
                }
                try output.writer().writeAll(self.contents[name_start..self.pos]);
                try self.skipWhitespaceAndComments();
            }
        }

        // Process params
        if (self.pos < self.contents.len and self.contents[self.pos] == '(') {
            try output.writer().writeByte('(');
            self.pos += 1;
            try self.emitParamListJS(output);
        }

        // Check for return type
        try self.emitWhitespaceAndComments(output);
        if (self.pos < self.contents.len and self.contents[self.pos] == ':') {
            self.pos += 1;
            try self.skipTypeAnnotation("{;");
        }
    }

    fn emitParamListJS(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        var paren_depth: usize = 1;

        while (self.pos < self.contents.len and paren_depth > 0) {
            try self.skipWhitespaceAndComments();
            if (self.pos >= self.contents.len) break;

            const c = self.contents[self.pos];

            if (c == '(') {
                try output.writer().writeByte('(');
                self.pos += 1;
                paren_depth += 1;
                continue;
            }

            if (c == ')') {
                try output.writer().writeByte(')');
                self.pos += 1;
                paren_depth -= 1;
                continue;
            }

            if (c == ',') {
                try output.writer().writeByte(',');
                self.pos += 1;
                continue;
            }

            // Destructuring param
            if (c == '{' or c == '[') {
                try self.emitDestructuringPatternJS(output);
                try self.skipWhitespaceAndComments();
                if (self.pos < self.contents.len and self.contents[self.pos] == ':') {
                    self.pos += 1;
                    try self.skipTypeAnnotation(",)");
                }
                try self.skipWhitespaceAndComments();
                if (self.pos < self.contents.len and self.contents[self.pos] == '=') {
                    try self.emitDefaultValueJS(output);
                }
                continue;
            }

            // Regular parameter: read name (skipping TS parameter property modifiers), skip type, skip default
            if (std.ascii.isAlphabetic(c) or c == '_' or c == '$') {
                const pname_start = self.pos;
                while (self.pos < self.contents.len) {
                    const pc = self.contents[self.pos];
                    if (std.ascii.isAlphanumeric(pc) or pc == '_' or pc == '$') {
                        self.pos += 1;
                    } else break;
                }
                const first_word = self.contents[pname_start..self.pos];
                if (isClassMemberModifier(first_word)) {
                    try self.skipWhitespaceAndComments();
                    if (self.pos >= self.contents.len) break;
                    if (std.ascii.isAlphabetic(self.contents[self.pos]) or self.contents[self.pos] == '_' or self.contents[self.pos] == '$') {
                        const actual_start = self.pos;
                        while (self.pos < self.contents.len) {
                            const pc = self.contents[self.pos];
                            if (std.ascii.isAlphanumeric(pc) or pc == '_' or pc == '$') {
                                self.pos += 1;
                            } else break;
                        }
                        try output.writer().writeAll(self.contents[actual_start..self.pos]);
                    }
                } else if (std.mem.eql(u8, first_word, "this")) {
                    // Strip TypeScript 'this' parameter (always first param)
                    try self.skipWhitespaceAndComments();
                    if (self.pos < self.contents.len and self.contents[self.pos] == ':') {
                        self.pos += 1;
                        try self.skipTypeAnnotation(",)");
                    }
                    // Also consume the trailing comma since 'this' is always first
                    try self.skipWhitespaceAndComments();
                    if (self.pos < self.contents.len and self.contents[self.pos] == ',') {
                        self.pos += 1;
                    }
                    continue;
                } else {
                    try output.writer().writeAll(self.contents[pname_start..self.pos]);
                }

                try self.skipWhitespaceAndComments();
                if (self.pos < self.contents.len and self.contents[self.pos] == ':') {
                    self.pos += 1;
                    try self.skipTypeAnnotation(",)");
                }
                // Also handle "as Type" in parameter context
                try self.skipWhitespaceAndComments();
                if (self.pos + 1 < self.contents.len and self.contents[self.pos] == 'a' and self.contents[self.pos+1] == 's') {
                    self.pos += 2;
                    try self.skipWhitespaceAndComments();
                    try self.skipTypeAnnotation(",)");
                }

                try self.skipWhitespaceAndComments();
                if (self.pos < self.contents.len and self.contents[self.pos] == '=') {
                    try self.emitDefaultValueJS(output);
                }
                continue;
            }

            // Skip unknown characters
            try output.writer().writeByte(c);
            self.pos += 1;
        }
    }

    fn emitClassJS(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        try self.emitWhitespaceAndComments(output);
        if (self.pos >= self.contents.len) return;

        // Read and output class name
        if (self.pos < self.contents.len) {
            const c = self.contents[self.pos];
            if (std.ascii.isAlphabetic(c) or c == '_' or c == '$') {
                const name_start = self.pos;
                while (self.pos < self.contents.len) {
                    const ch = self.contents[self.pos];
                    if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$') {
                        self.pos += 1;
                    } else break;
                }
                try output.writer().writeAll(self.contents[name_start..self.pos]);
                try self.emitWhitespaceAndComments(output);
            }
        }

        // Skip class type params <...>
        if (self.pos < self.contents.len and self.contents[self.pos] == '<') {
            try self.skipTypeParams();
            try self.emitWhitespaceAndComments(output);
        }
    }

    fn emitDefaultValueJS(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        try output.writer().writeByte('=');
        self.pos += 1;
        var depth: usize = 1;
        var in_string: bool = false;
        var string_char: u8 = 0;

        while (self.pos < self.contents.len and depth > 0) {
            const c = self.contents[self.pos];
            if (in_string) {
                try output.writer().writeByte(c);
                self.pos += 1;
                if (c == string_char) in_string = false;
                continue;
            }
            if (c == '\'' or c == '"' or c == '`') {
                try output.writer().writeByte(c);
                self.pos += 1;
                in_string = true;
                string_char = c;
                continue;
            }
            if (c == '(' or c == '{' or c == '[') {
                depth += 1;
                try output.writer().writeByte(c);
                self.pos += 1;
                continue;
            }
            if ((c == ')' or c == '}' or c == ']') and depth > 0) {
                depth -= 1;
                if (depth == 0) break;
                try output.writer().writeByte(c);
                self.pos += 1;
                continue;
            }
            if (c == ',' and depth == 1) break;
            try output.writer().writeByte(c);
            self.pos += 1;
        }
    }

    fn skipTypeAnnotation(self: *TypeScriptEmitter, terminators: []const u8) !void {
        var brace_depth: usize = 0;
        var paren_depth: usize = 0;
        var bracket_depth: usize = 0;
        var angle_depth: usize = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;
        var last_was_gt: bool = false;

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];

            if (in_string) {
                if (ch == string_char and prev_ch != '\\') {
                    in_string = false;
                }
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            if (ch == '\'' or ch == '"' or ch == '`') {
                in_string = true;
                string_char = ch;
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            // Check terminators at depth 0
            if (brace_depth == 0 and paren_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
                for (terminators) |t| {
                    if (ch == t) return;
                }
            }

            switch (ch) {
                '{' => brace_depth += 1,
                '}' => {
                    if (brace_depth > 0) brace_depth -= 1 else return;
                },
                '(' => paren_depth += 1,
                ')' => {
                    if (paren_depth > 0) paren_depth -= 1 else return;
                },
                '[' => bracket_depth += 1,
                ']' => {
                    if (bracket_depth > 0) bracket_depth -= 1 else return;
                },
                '<' => {
                    if (last_was_gt or angle_depth > 0 or brace_depth > 0 or paren_depth > 0 or bracket_depth > 0) {
                        angle_depth += 1;
                    }
                },
                '>' => {
                    if (angle_depth > 0) angle_depth -= 1;
                },
                else => {},
            }

            last_was_gt = ch == '>';
            prev_ch = ch;
            self.pos += 1;
        }
    }

    fn skipTypeParams(self: *TypeScriptEmitter) !void {
        if (self.pos >= self.contents.len or self.contents[self.pos] != '<') return;
        var depth: usize = 1;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;

        self.pos += 1;
        while (self.pos < self.contents.len and depth > 0) {
            const ch = self.contents[self.pos];
            if (in_string) {
                if (ch == string_char and prev_ch != '\\') in_string = false;
                prev_ch = ch;
                self.pos += 1;
                continue;
            }
            if (ch == '\'' or ch == '"' or ch == '`') {
                in_string = true;
                string_char = ch;
                prev_ch = ch;
                self.pos += 1;
                continue;
            }
            if (ch == '<') {
                depth += 1;
            } else if (ch == '>') {
                depth -= 1;
            }
            prev_ch = ch;
            self.pos += 1;
        }
    }

    fn skipTypeDeclJS(self: *TypeScriptEmitter, kind: []const u8) !void {
        try self.skipWhitespaceAndComments();
        if (self.pos >= self.contents.len) return;

        // Read (skip) the declaration name
        if (std.ascii.isAlphabetic(self.contents[self.pos]) or self.contents[self.pos] == '_' or self.contents[self.pos] == '$') {
            while (self.pos < self.contents.len) {
                const c = self.contents[self.pos];
                if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$') {
                    self.pos += 1;
                } else break;
            }
        }

        try self.skipWhitespaceAndComments();

        // Skip type params <...>
        if (self.pos < self.contents.len and self.contents[self.pos] == '<') {
            try self.skipTypeParams();
            try self.skipWhitespaceAndComments();
        }

        if (std.mem.eql(u8, kind, "interface")) {
            while (self.pos < self.contents.len) {
                try self.skipWhitespaceAndComments();
                if (self.pos >= self.contents.len) break;
                const ch = self.contents[self.pos];
                if (ch == '{') {
                    self.pos += 1;
                    self.skipBalancedBraces();
                    break;
                }
                self.pos += 1;
            }
        } else if (std.mem.eql(u8, kind, "type")) {
            while (self.pos < self.contents.len and self.contents[self.pos] != '=') {
                try self.skipWhitespaceAndComments();
                if (self.pos >= self.contents.len) break;
                if (self.contents[self.pos] == '=') break;
                self.pos += 1;
            }
            if (self.pos < self.contents.len) {
                self.pos += 1; // skip '='
            }
            try self.skipTypeAnnotation(";");
            if (self.pos < self.contents.len and self.contents[self.pos] == ';') {
                self.pos += 1;
            }
        }
    }


    fn emitJSDocAndWhitespace(self: *TypeScriptEmitter, output: *std.ArrayList(u8)) !void {
        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];
            if (std.ascii.isWhitespace(ch)) {
                try output.writer().writeByte(ch);
                self.pos += 1;
            } else if (ch == '/' and self.pos + 2 < self.contents.len) {
                const next1 = self.contents[self.pos + 1];
                const next2 = self.contents[self.pos + 2];
                if (next1 == '*' and next2 == '*') {
                    // JSDoc comment - emit it
                    try output.writer().writeAll("/**");
                    self.pos += 3;
                    while (self.pos + 1 < self.contents.len) {
                        if (self.contents[self.pos] == '*' and self.contents[self.pos + 1] == '/') {
                            try output.writer().writeAll("*/");
                            self.pos += 2;
                            break;
                        }
                        try output.writer().writeByte(self.contents[self.pos]);
                        self.pos += 1;
                    }
                } else if (next1 == '/') {
                    // Line comment - skip
                    while (self.pos < self.contents.len and self.contents[self.pos] != '\n') {
                        self.pos += 1;
                    }
                } else if (next1 == '*') {
                    // Block comment (not JSDoc) - skip
                    self.pos += 2;
                    while (self.pos + 1 < self.contents.len) {
                        if (self.contents[self.pos] == '*' and self.contents[self.pos + 1] == '/') {
                            self.pos += 2;
                            break;
                        }
                        self.pos += 1;
                    }
                } else {
                    break;
                }
            } else {
                break;
            }
        }
    }

    pub fn emitDeclarations(self: *TypeScriptEmitter) ![]u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        var self_copy = TypeScriptEmitter{
            .allocator = self.allocator,
            .contents = self.contents,
            .pos = 0,
            .is_declaration = true,
        };

        while (self_copy.pos < self_copy.contents.len) {
            // Capture JSDoc comments before declarations
            try self_copy.emitJSDocAndWhitespace(&output);
            if (self_copy.pos >= self_copy.contents.len) break;

            const start = self_copy.pos;
            if (self_copy.tryParseTopLevelDeclaration()) {
                const end = self_copy.pos;
                if (end > start) {
                    var slice = self_copy.contents[start..end];
                    while (slice.len > 0 and std.ascii.isWhitespace(slice[slice.len - 1])) {
                        slice = slice[0..slice.len - 1];
                    }
                    if (isVarDeclSlice(slice)) {
                        slice = stripDeclInitializer(slice);
                    }
                    try output.writer().writeAll(slice);
                    if (slice.len > 0 and slice[slice.len - 1] == '{') {
                        try output.writer().writeAll("};\n");
                    } else if (isDeclarationFunctionSlice(slice)) {
                        if (slice.len > 0 and slice[slice.len - 1] == ';') {
                            try output.writer().writeAll("\n");
                        } else {
                            try output.writer().writeAll(";\n");
                        }
                        try self_copy.skipWhitespaceAndComments();
                        if (self_copy.pos < self_copy.contents.len and self_copy.contents[self_copy.pos] == '{') {
                            self_copy.pos += 1;
                            self_copy.skipBalancedBraces();
                        }
                    } else {
                        if (slice.len > 0 and slice[slice.len - 1] != ';') {
                            try output.writer().writeAll(";\n");
                        } else {
                            try output.writer().writeAll("\n");
                        }
                    }
                }
            } else {
                self_copy.skipTopLevelStatement();
            }
        }

        return output.toOwnedSlice();
    }

    fn tryParseTopLevelDeclaration(self: *TypeScriptEmitter) bool {
        if (self.matchWord("export")) {
            try self.skipWhitespaceAndComments();
        }

        if (self.tryParseInterface()) return true;
        if (self.tryParseType()) return true;
        if (self.tryParseFunction()) return true;
        if (self.is_declaration) {
            if (self.tryParseAbstractClassDeclaration()) return true;
            if (self.tryParseClassDeclaration()) return true;
            if (self.tryParseEnumDeclaration()) return true;
            if (self.tryParseNamespaceDeclaration()) return true;
        } else {
            if (self.tryParseClass()) return true;
        }
        if (self.tryParseConstLetVar()) return true;

        if (self.tryParseDeclareDeclaration()) return true;

        return false;
    }

    fn tryParseInterface(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("interface")) return false;

        while (self.pos < self.contents.len and self.contents[self.pos] != '{') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            self.skipBalancedBraces();
        }
        return true;
    }

    fn tryParseType(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("type")) return false;

        while (self.pos < self.contents.len and self.contents[self.pos] != '=') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            while (self.pos < self.contents.len) {
                const ch = self.contents[self.pos];
                if (ch == ';') {
                    self.pos += 1;
                    break;
                }
                if (ch == '{' or ch == '}') break;
                self.pos += 1;
            }
        }
        return true;
    }

    fn tryParseFunction(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("function")) return false;

        while (self.pos < self.contents.len and self.contents[self.pos] != '(') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            self.skipBalancedParens();
        }

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];
            if (ch == ';') {
                self.pos += 1;
                return true;
            }
            if (ch == '{') {
                return true;
            }
            self.pos += 1;
        }
        return true;
    }

    fn tryParseAbstractClassDeclaration(self: *TypeScriptEmitter) bool {
        const saved = self.pos;
        if (!self.matchWord("abstract")) return false;
        if (!self.matchWord("class")) {
            self.pos = saved;
            return false;
        }

        while (self.pos < self.contents.len and self.contents[self.pos] != '{') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            if (self.is_declaration) {
                return true;
            }
            try self.stripClassBodyForDeclaration();
        }
        return true;
    }

    fn tryParseClassDeclaration(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("class")) return false;

        while (self.pos < self.contents.len and self.contents[self.pos] != '{') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            if (self.is_declaration) {
                return true;
            }
            try self.stripClassBodyForDeclaration();
        }
        return true;
    }

    fn tryParseEnumDeclaration(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("enum")) return false;

        while (self.pos < self.contents.len and self.contents[self.pos] != '{') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            self.skipBalancedBraces();
        }
        return true;
    }

    fn tryParseNamespaceDeclaration(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("namespace") and !self.matchWord("module") and !self.matchWord("global")) {
            return false;
        }

        if (self.pos < self.contents.len and self.contents[self.pos] == '"') {
            self.pos += 1;
            while (self.pos < self.contents.len and self.contents[self.pos] != '"') {
                if (self.contents[self.pos] == '\\') self.pos += 1;
                self.pos += 1;
            }
            if (self.pos < self.contents.len) self.pos += 1;
        }

        while (self.pos < self.contents.len and self.contents[self.pos] != '{') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            self.skipBalancedBraces();
        }
        return true;
    }

    fn tryParseDeclareDeclaration(self: *TypeScriptEmitter) bool {
        const saved = self.pos;
        if (!self.matchWord("declare")) return false;
        try self.skipWhitespaceAndComments();

        if (self.tryParseInterface()) return true;
        if (self.tryParseType()) return true;
        if (self.tryParseFunction()) return true;
        if (self.tryParseAbstractClassDeclaration()) return true;
        if (self.tryParseClassDeclaration()) return true;
        if (self.tryParseEnumDeclaration()) return true;
        if (self.tryParseNamespaceDeclaration()) return true;
        if (self.tryParseConstLetVar()) return true;

        self.pos = saved;
        return false;
    }

    fn stripClassBodyForDeclaration(self: *TypeScriptEmitter) !void {
        var brace_depth: usize = 1;
        var paren_depth: usize = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;

        while (self.pos < self.contents.len and brace_depth > 0) {
            const ch = self.contents[self.pos];

            if (in_string) {
                if (ch == string_char and prev_ch != '\\') {
                    in_string = false;
                }
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            if (ch == '\'' or ch == '"' or ch == '`') {
                in_string = true;
                string_char = ch;
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            if (ch == '(') {
                paren_depth += 1;
            } else if (ch == ')') {
                if (paren_depth > 0) paren_depth -= 1;
            } else if (ch == '{') {
                brace_depth += 1;
            } else if (ch == '}') {
                brace_depth -= 1;
                if (brace_depth == 0) {
                    self.pos += 1;
                    break;
                }
            } else if (ch == ';' and paren_depth == 0 and brace_depth == 1) {
                self.pos += 1;
                try self.skipWhitespaceAndComments();
                if (self.pos < self.contents.len and self.contents[self.pos] == '}') {
                    continue;
                }
                continue;
            }

            prev_ch = ch;
            self.pos += 1;
        }
    }

    fn writeClassDeclarationWithStrippedBody(self: *TypeScriptEmitter, writer: anytype, slice: []const u8) !void {
        var i: usize = 0;

        while (i < slice.len) {
            const ch = slice[i];

            if (ch == '{') {
                try writer.writeAll(" { ");
                i += 1;
                while (i < slice.len and std.ascii.isWhitespace(slice[i])) {
                    i += 1;
                }
                try self.writeClassBodyWithStrippedMethods(writer, slice, &i);
                continue;
            }

            try writer.writeByte(ch);
            i += 1;
        }
    }

    fn writeClassBodyWithStrippedMethods(self: *TypeScriptEmitter, writer: anytype, slice: []const u8, idx: *usize) !void {
        var brace_depth: usize = 1;

        while (idx.* < slice.len and brace_depth >= 0) {
            const ch = slice[idx.*];

            if (ch == '{') {
                brace_depth += 1;
                try self.skipMethodBody(slice, idx);
                if (brace_depth == 1) {
                    try writer.writeAll("; ");
                }
            } else if (ch == '}') {
                brace_depth -= 1;
                if (brace_depth == 0) {
                    try writer.writeAll(" }");
                    idx.* += 1;
                    break;
                }
                try writer.writeByte(ch);
                idx.* += 1;
            } else if (ch == ';') {
                try writer.writeAll("; ");
                idx.* += 1;
            } else {
                try writer.writeByte(ch);
                idx.* += 1;
            }
        }

        while (idx.* < slice.len and std.ascii.isWhitespace(slice[idx.*])) {
            idx.* += 1;
        }
    }

    fn skipMethodBody(_: *TypeScriptEmitter, slice: []const u8, idx: *usize) !void {
        var depth: usize = 1;
        var paren_depth: usize = 0;
        var prev_ch: u8 = 0;

        idx.* += 1;

        while (idx.* < slice.len and depth > 0) {
            const ch = slice[idx.*];

            if (ch == '(' and prev_ch != '\\') {
                paren_depth += 1;
            } else if (ch == ')' and prev_ch != '\\') {
                if (paren_depth > 0) paren_depth -= 1;
            } else if (ch == '{' and paren_depth == 0) {
                depth += 1;
            } else if (ch == '}' and paren_depth == 0) {
                depth -= 1;
                if (depth == 0) {
                    idx.* += 1;
                    break;
                }
            }

            prev_ch = ch;
            idx.* += 1;
        }
    }

    fn tryParseClass(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("class")) return false;

        while (self.pos < self.contents.len and self.contents[self.pos] != '{') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) {
            self.pos += 1;
            self.skipBalancedBraces();
        }
        return true;
    }

    fn tryParseConstLetVar(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("const") and !self.matchWord("let") and !self.matchWord("var")) return false;

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];
            if (ch == '=') {
                self.pos += 1;
                while (self.pos < self.contents.len) {
                    const ec = self.contents[self.pos];
                    if (ec == ';' or ec == '{' or ec == '}') {
                        self.pos += 1;
                        break;
                    }
                    self.pos += 1;
                }
                break;
            }
            if (ch == ';') {
                self.pos += 1;
                break;
            }
            self.pos += 1;
        }
        return true;
    }

    fn skipToSemicolonOrBrace(self: *TypeScriptEmitter) void {
        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];
            if (ch == ';' or ch == '{' or ch == '}') {
                return;
            }
            self.pos += 1;
        }
    }

    fn endsWithNewline(_: *TypeScriptEmitter, slice: []const u8) bool {
        if (slice.len == 0) return false;
        return slice[slice.len - 1] == '\n';
    }

    fn isDeclarationFunctionSlice(slice: []const u8) bool {
        if (slice.len < 9) return false;
        if (std.mem.startsWith(u8, slice, "function")) return true;
        if (std.mem.startsWith(u8, slice, "export function")) return true;
        if (std.mem.startsWith(u8, slice, "declare function")) return true;
        if (std.mem.startsWith(u8, slice, "export declare function")) return true;
        return false;
    }

    /// Strips the = value initializer from a const/let/var declaration slice.
    /// Returns the slice trimmed to just the type annotation.
    fn stripDeclInitializer(slice: []const u8) []const u8 {
        var depth: usize = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_c: u8 = 0;
        for (slice, 0..) |c, i| {
            if (in_string) {
                if (c == string_char and prev_c != '\\') in_string = false;
                prev_c = c;
                continue;
            }
            switch (c) {
                '\'', '"', '`' => {
                    in_string = true;
                    string_char = c;
                },
                '<', '{', '[' => depth += 1,
                '>', '}', ']' => {
                    if (depth > 0) depth -= 1;
                },
                '=' => {
                    if (depth == 0 and !in_string) {
                        var end = i;
                        while (end > 0 and (slice[end - 1] == ' ' or slice[end - 1] == '\t')) {
                            end -= 1;
                        }
                        return slice[0..end];
                    }
                },
                else => {},
            }
            prev_c = c;
        }
        return slice;
    }

    fn isTypeOnlyKeyword(word: []const u8) bool {
        return std.mem.eql(u8, word, "interface") or
            std.mem.eql(u8, word, "type");
    }

    fn isClassMemberModifier(word: []const u8) bool {
        return std.mem.eql(u8, word, "public") or
            std.mem.eql(u8, word, "private") or
            std.mem.eql(u8, word, "protected") or
            std.mem.eql(u8, word, "readonly") or
            std.mem.eql(u8, word, "override") or
            std.mem.eql(u8, word, "abstract");
    }

    fn isVarKeyword(word: []const u8) bool {
        return std.mem.eql(u8, word, "const") or
            std.mem.eql(u8, word, "let") or
            std.mem.eql(u8, word, "var");
    }

    fn isVarDeclSlice(slice: []const u8) bool {
        var s = slice;
        if (std.mem.startsWith(u8, s, "export ")) s = s[7..];
        if (std.mem.startsWith(u8, s, "declare ")) s = s[8..];
        return std.mem.startsWith(u8, s, "const") or
            std.mem.startsWith(u8, s, "let") or
            std.mem.startsWith(u8, s, "var");
    }

    fn skipWhitespaceAndComments(self: *TypeScriptEmitter) !void {
        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];
            if (std.ascii.isWhitespace(ch)) {
                self.pos += 1;
            } else if (ch == '/' and self.pos + 1 < self.contents.len) {
                const next = self.contents[self.pos + 1];
                if (next == '/') {
                    while (self.pos < self.contents.len and self.contents[self.pos] != '\n') {
                        self.pos += 1;
                    }
                } else if (next == '*') {
                    self.pos += 2;
                    while (self.pos + 1 < self.contents.len) {
                        if (self.contents[self.pos] == '*' and self.contents[self.pos + 1] == '/') {
                            self.pos += 2;
                            break;
                        }
                        self.pos += 1;
                    }
                } else {
                    break;
                }
            } else {
                break;
            }
        }
    }

    fn parseTopLevelStatement(self: *TypeScriptEmitter) !void {
        try self.skipWhitespaceAndComments();
        if (self.pos >= self.contents.len) return;

        if (self.tryParseImport()) return;
        if (self.tryParseExport()) return;
        if (self.tryParseInterface()) return;
        if (self.tryParseType()) return;
        if (self.tryParseClass()) return;
        if (self.tryParseFunction()) return;
        if (self.tryParseConstLetVar()) return;

        self.skipStatement();
    }

    fn skipStatement(self: *TypeScriptEmitter) void {
        var brace_depth: usize = 0;
        var paren_depth: usize = 0;
        var bracket_depth: usize = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];

            if (in_string) {
                if (ch == string_char and prev_ch != '\\') {
                    in_string = false;
                }
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            switch (ch) {
                '\'', '"', '`' => {
                    in_string = true;
                    string_char = ch;
                },
                '{' => brace_depth += 1,
                '}' => {
                    if (brace_depth > 0) {
                        brace_depth -= 1;
                    } else {
                        self.pos += 1;
                        return;
                    }
                },
                '(' => paren_depth += 1,
                ')' => {
                    if (paren_depth > 0) paren_depth -= 1;
                },
                '[' => bracket_depth += 1,
                ']' => {
                    if (bracket_depth > 0) bracket_depth -= 1;
                },
                ';', '<' => {
                    self.pos += 1;
                    return;
                },
                else => {},
            }

            prev_ch = ch;
            self.pos += 1;
        }
    }

    fn skipTopLevelStatement(self: *TypeScriptEmitter) void {
        var brace_depth: usize = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];

            if (in_string) {
                if (ch == string_char and prev_ch != '\\') {
                    in_string = false;
                }
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            if (ch == '\'' or ch == '"' or ch == '`') {
                in_string = true;
                string_char = ch;
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            switch (ch) {
                '{' => brace_depth += 1,
                '}' => {
                    if (brace_depth == 0) {
                        self.pos += 1;
                        return;
                    }
                    brace_depth -= 1;
                },
                ';' => {
                    self.pos += 1;
                    return;
                },
                else => {},
            }

            prev_ch = ch;
            self.pos += 1;
        }
    }

    fn tryParseImport(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("import")) return false;
        try self.skipTypeAnnotations();
        while (self.pos < self.contents.len and self.contents[self.pos] != ';') {
            self.pos += 1;
        }
        if (self.pos < self.contents.len) self.pos += 1;
        return true;
    }

    fn tryParseExport(self: *TypeScriptEmitter) bool {
        if (!self.matchWord("export")) return false;

        try self.skipWhitespaceAndComments();

        if (self.tryParseInterface()) return true;
        if (self.tryParseType()) return true;
        if (self.tryParseFunction()) return true;
        if (self.tryParseClass()) return true;
        if (self.tryParseConstLetVar()) return true;

        if (self.matchWord("{")) {
            while (self.pos < self.contents.len and self.contents[self.pos] != ';') {
                self.pos += 1;
            }
            if (self.pos < self.contents.len) self.pos += 1;
            return true;
        }

        return false;
    }

    fn skipExpression(self: *TypeScriptEmitter) void {
        var paren_depth: usize = 0;
        var bracket_depth: usize = 0;
        var brace_depth: usize = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];

            if (in_string) {
                if (ch == string_char) {
                    in_string = false;
                }
                self.pos += 1;
                continue;
            }

            if (ch == '\'' or ch == '"' or ch == '`') {
                in_string = true;
                string_char = ch;
                self.pos += 1;
                continue;
            }

            if (ch == ':' and brace_depth == 0 and paren_depth == 0 and bracket_depth == 0) {
                try self.skipTypeAnnotations();
                continue;
            }

            if (std.ascii.isDigit(ch)) {
                self.pos += 1;
                continue;
            }

            switch (ch) {
                '(' => paren_depth += 1,
                ')' => {
                    if (paren_depth == 0) break;
                    paren_depth -= 1;
                },
                '[' => bracket_depth += 1,
                ']' => {
                    if (bracket_depth == 0) break;
                    bracket_depth -= 1;
                },
                '{' => brace_depth += 1,
                '}' => {
                    if (brace_depth == 0) break;
                    brace_depth -= 1;
                },
                ',', ';', '=' => {
                    if (brace_depth == 0 and paren_depth == 0 and bracket_depth == 0) {
                        break;
                    }
                },
                else => {},
            }

            self.pos += 1;
        }
    }

    fn skipTypeAnnotations(self: *TypeScriptEmitter) !void {
        if (self.pos >= self.contents.len or self.contents[self.pos] != ':') return;

        self.pos += 1;
        var angle_bracket_depth: usize = 0;

        while (self.pos < self.contents.len) {
            const ch = self.contents[self.pos];

            if (ch == '<') angle_bracket_depth += 1;
            if (ch == '>') angle_bracket_depth -= 1;

            if (ch == ',' or ch == ';' or ch == '=' or ch == ')' or ch == ']' or ch == '{' or ch == '\n') {
                if (angle_bracket_depth == 0) break;
            }

            self.pos += 1;
        }
    }

    fn skipBalancedBraces(self: *TypeScriptEmitter) void {
        var depth: usize = 1;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;

        while (self.pos < self.contents.len and depth > 0) {
            const ch = self.contents[self.pos];

            if (in_string) {
                if (ch == string_char and prev_ch != '\\') {
                    in_string = false;
                }
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            if (ch == '\'' or ch == '"' or ch == '`') {
                in_string = true;
                string_char = ch;
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            switch (ch) {
                '{' => depth += 1,
                '}' => depth -= 1,
                else => {},
            }

            prev_ch = ch;
            self.pos += 1;
        }
    }

    fn skipBalancedParens(self: *TypeScriptEmitter) void {
        var depth: usize = 1;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;

        while (self.pos < self.contents.len and depth > 0) {
            const ch = self.contents[self.pos];

            if (in_string) {
                if (ch == string_char and prev_ch != '\\') {
                    in_string = false;
                }
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            if (ch == '\'' or ch == '"' or ch == '`') {
                in_string = true;
                string_char = ch;
                prev_ch = ch;
                self.pos += 1;
                continue;
            }

            switch (ch) {
                '(' => depth += 1,
                ')' => depth -= 1,
                else => {},
            }

            prev_ch = ch;
            self.pos += 1;
        }
    }

    fn matchWord(self: *TypeScriptEmitter, word: []const u8) bool {
        const start = self.pos;
        try self.skipWhitespaceAndComments();

        if (self.pos + word.len > self.contents.len) {
            self.pos = start;
            return false;
        }

        for (word, 0..) |c, i| {
            if (self.contents[self.pos + i] != c) {
                self.pos = start;
                return false;
            }
        }

        const next_pos = self.pos + word.len;
        if (next_pos < self.contents.len) {
            const next_ch = self.contents[next_pos];
            if (std.ascii.isAlphanumeric(next_ch) or next_ch == '_' or next_ch == '$') {
                self.pos = start;
                return false;
            }
        }

        self.pos = next_pos;
        return true;
    }

    /// Skip past a declare-style declaration entirely.
    fn skipDeclareDeclaration(self: *TypeScriptEmitter) void {
        var brace_depth: usize = 0;
        var in_string: bool = false;
        var string_char: u8 = 0;
        var prev_ch: u8 = 0;

        while (self.pos < self.contents.len) {
            const c = self.contents[self.pos];

            if (in_string) {
                if (c == string_char and prev_ch != '\\') in_string = false;
                prev_ch = c;
                self.pos += 1;
                continue;
            }

            if (c == '\'' or c == '"' or c == '`') {
                in_string = true;
                string_char = c;
                prev_ch = c;
                self.pos += 1;
                continue;
            }

            if (c == '{' and brace_depth == 0) {
                self.pos += 1;
                self.skipBalancedBraces();
                return;
            }
            if (c == ';' and brace_depth == 0) {
                self.pos += 1;
                return;
            }
            if (c == '{') {
                brace_depth += 1;
            } else if (c == '}') {
                if (brace_depth == 0) return;
                brace_depth -= 1;
            }

            prev_ch = c;
            self.pos += 1;
        }
    }
};

pub fn writeEmitResult(
    writer: anytype,
    result: *const EmitResult,
) !void {
    if (result.diagnostics.items.len > 0) {
        try writer.writeAll("zts: emit diagnostics:\n");
        for (result.diagnostics.items) |diag| {
            try writer.print("  {s}: {s}\n", .{ diag.path, diag.message });
        }
    }

    if (result.js_output.items.len > 0) {
        try writer.writeAll("\n--- JS output ---\n");
        try writer.writeAll(result.js_output.items);
    }

    if (result.dts_output.items.len > 0) {
        try writer.writeAll("\n--- Declaration output ---\n");
        try writer.writeAll(result.dts_output.items);
    }
}

fn testEmitResult(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var emitter = TypeScriptEmitter.init(allocator, input);
    return emitter.emit();
}

fn testDtsResult(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var emitter = TypeScriptEmitter.init(allocator, input);
    return emitter.emitDeclarations();
}

test "emit: empty file" {
    const result = try testEmitResult(std.testing.allocator, "");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: only comments" {
    const result = try testEmitResult(std.testing.allocator, "// just a comment");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: strips const type annotation" {
    const result = try testEmitResult(std.testing.allocator, "const x: number = 1;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const x="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
}

test "emit: strips let type annotation" {
    const result = try testEmitResult(std.testing.allocator, "let y: string = \"hello\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "let y="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": string"));
}

test "emit: strips var type annotation" {
    const result = try testEmitResult(std.testing.allocator, "var z: boolean = true;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "var z="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": boolean"));
}

test "emit: strips function parameter and return type" {
    const result = try testEmitResult(std.testing.allocator, "function greet(name: string): void {}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function greet(name)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ":"));
}

test "emit: strips multiple function parameter types" {
    const result = try testEmitResult(std.testing.allocator, "function add(a: number, b: number): number { return a + b; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function add(a,b)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "return a + b"));
}

test "emit: removes interface declaration" {
    const result = try testEmitResult(std.testing.allocator, "interface Point {\n    x: number;\n    y: number;\n}");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: removes type alias" {
    const result = try testEmitResult(std.testing.allocator, "type ID = string | number;");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: removes export interface" {
    const result = try testEmitResult(std.testing.allocator, "export interface Foo {\n    x: number;\n}");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: removes export type" {
    const result = try testEmitResult(std.testing.allocator, "export type Result<T> = T | null;");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: preserves export function with type erasure" {
    const result = try testEmitResult(std.testing.allocator, "export function foo(a: number): void {}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export function foo(a)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
}

test "emit: preserves export const with type erasure" {
    const result = try testEmitResult(std.testing.allocator, "export const value: string = \"hello\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export const value="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": string"));
}

test "emit: preserves string literals unchanged" {
    const result = try testEmitResult(std.testing.allocator, "const msg: string = 'hello world';");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "'hello world'"));
}

test "emit: preserves template literals" {
    const result = try testEmitResult(std.testing.allocator, "const msg: string = `hello ${name}`;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "`hello ${name}`"));
}

test "emit: multiple declarations mixed" {
    const input = "const x: number = 1;\ninterface Point { x: number; }\nfunction greet(name: string): void {}\ntype ID = number;";
    const result = try testEmitResult(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const x="));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function greet(name)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "interface Point"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "type ID"));
}

test "emit: preserves import statements" {
    const result = try testEmitResult(std.testing.allocator, "import { foo } from \"./bar\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "import"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "foo"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "bar"));
}

test "emit: preserves export declarations" {
    const result = try testEmitResult(std.testing.allocator, "export { foo, bar };");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export { foo, bar };"));
}

test "emit: string literal with type-like content is preserved" {
    const result = try testEmitResult(std.testing.allocator, "const data: string = 'x: number = 1';");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "'x: number = 1'"));
}

test "emit: multiple independent lines all stripped" {
    const input = "const a: number = 1;\nconst b: boolean = false;\nconst c: string = \"x\";";
    const result = try testEmitResult(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const a="));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const b="));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const c="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": boolean"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": string"));
}

test "emit: preserves class declaration" {
    const result = try testEmitResult(std.testing.allocator, "class C { constructor(x: number) { this.x = x; } }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "this.x = x"));
}

test "emit: strips class type params" {
    const result = try testEmitResult(std.testing.allocator, "class C<T> { foo(): void { return; } }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C {"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "<T>"));
}

test "emit: strips class method param types" {
    const result = try testEmitResult(std.testing.allocator, "class C { foo(x: number, y: string): boolean { return true; } }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C { foo(x,"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": string"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": boolean"));
}

test "emit: strips class method return types" {
    const result = try testEmitResult(std.testing.allocator, "class C { foo(x: number): string { return \"\"; } }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C { foo(x)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": string"));
}

test "emit: multiple class methods with type erasure" {
    const input = "class C { add(a: number, b: number): number { return a + b; } greet(name: string): void { } }";
    const result = try testEmitResult(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "add(a,"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "greet(name)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": void"));
}

// --- Declaration emit tests ---

test "declaration: interface preserved" {
    const result = try testDtsResult(std.testing.allocator, "interface Point { x: number; y: number; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "interface Point"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "{"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "}"));
}

test "declaration: type alias preserved" {
    const result = try testDtsResult(std.testing.allocator, "type ID = string | number;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "type ID = string | number"));
}

test "declaration: function ends with semicolon" {
    const result = try testDtsResult(std.testing.allocator, "function greet(name: string): void { console.log(name); }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function greet(name: string): void;"));
}

test "declaration: class body stripped" {
    const result = try testDtsResult(std.testing.allocator, "class C { foo(): number { return 1; } bar(): string { return \"hello\"; } }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "};"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "return 1"));
}

test "declaration: generic class" {
    const result = try testDtsResult(std.testing.allocator, "class Animal<T> { name: T; age: number; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class Animal<T>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "};"));
}

test "declaration: const variable" {
    const result = try testDtsResult(std.testing.allocator, "const x: number = 1;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const x: number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "= 1"));
}

test "declaration: let variable strips initializer" {
    const result = try testDtsResult(std.testing.allocator, "let y: string = \"hello\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "let y: string"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "hello"));
}

test "declaration: export const strips initializer" {
    const result = try testDtsResult(std.testing.allocator, "export const value: number = 42;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export const value: number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "= 42"));
}

test "declaration: const without initializer unchanged" {
    const result = try testDtsResult(std.testing.allocator, "const x: number;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const x: number"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, ";"));
}

test "declaration: export class" {
    const result = try testDtsResult(std.testing.allocator, "export class C { foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export class C {"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "};"));
}

test "declaration: multiple declarations" {
    const input = "export class C { foo(): void {} }\ninterface Point { x: number; }\ntype ID = number;\nfunction hello(): void {}\nconst value: string = \"test\";";
    const result = try testDtsResult(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export class C"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "interface Point"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "type ID = number"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function hello(): void;"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const value: string"));
}

test "declaration: generic interface" {
    const result = try testDtsResult(std.testing.allocator, "interface Pair<T, U> { first: T; second: U; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "interface Pair<T, U>"));
}

test "declaration: abstract class" {
    const result = try testDtsResult(std.testing.allocator, "abstract class Animal { abstract makeSound(): void; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "abstract class Animal"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "};"));
}

test "declaration: export abstract class" {
    const result = try testDtsResult(std.testing.allocator, "export abstract class Foo { abstract bar(): void; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export abstract class Foo"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "};"));
}

test "declaration: declare function" {
    const result = try testDtsResult(std.testing.allocator, "declare function foo(x: number): void;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "declare function foo(x: number): void;"));
}

test "declaration: declare class" {
    const result = try testDtsResult(std.testing.allocator, "declare class C { foo(): void; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "declare class C"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "};"));
}

test "declaration: declare const" {
    const result = try testDtsResult(std.testing.allocator, "declare const x: number;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "declare const x: number;"));
}

test "declaration: declare enum" {
    const result = try testDtsResult(std.testing.allocator, "declare enum Color { Red, Green, Blue }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "declare enum Color"));
}

test "declaration: declare namespace" {
    const result = try testDtsResult(std.testing.allocator, "declare namespace MyLib { export function foo(): void; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "declare namespace MyLib"));
}

test "declaration: export declare function" {
    const result = try testDtsResult(std.testing.allocator, "export declare function foo(): void;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export declare function foo(): void;"));
}

test "emit: strips declare function" {
    const result = try testEmitResult(std.testing.allocator, "declare function foo(x: number): void;");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: strips declare class" {
    const result = try testEmitResult(std.testing.allocator, "declare class C { foo(): void; }");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: strips export declare" {
    const result = try testEmitResult(std.testing.allocator, "export declare function foo(): void;");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: strips abstract from abstract class" {
    const result = try testEmitResult(std.testing.allocator, "abstract class C { foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C {"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "abstract"));
}

test "emit: strips abstract from export abstract class" {
    const result = try testEmitResult(std.testing.allocator, "export abstract class C { foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export class C {"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "abstract"));
}

test "emit: enum with declare stripped" {
    const result = try testEmitResult(std.testing.allocator, "declare enum Color { Red, Green, Blue }");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

// --- Overload tests ---

test "declaration: overload signatures each produce a declaration" {
    const input =
        \\function foo(x: number): number;
        \\function foo(x: string): string;
        \\function foo(x: any): any { return x; }
    ;
    const result = try testDtsResult(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function foo(x: number): number;"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function foo(x: string): string;"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function foo(x: any): any;"));
}

test "declaration: function without body ends with semicolon (no double ;)" {
    const input = "declare function foo(): void;";
    const result = try testDtsResult(std.testing.allocator, input);
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "declare function foo(): void;"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ";;"));
}

// --- Type assertion stripping tests ---

test "emit: strips as type assertion" {
    const result = try testEmitResult(std.testing.allocator, "const x = foo as string;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const x="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "as string"));
}

test "emit: strips as with complex type" {
    const result = try testEmitResult(std.testing.allocator, "const y = (expr) as SomeType<T>[];");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const y="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "as SomeType"));
}

test "emit: preserves as in import specifier" {
    const result = try testEmitResult(std.testing.allocator, "import { foo as bar } from \"./mod\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "foo as bar"));
}

test "emit: preserves as in export specifier" {
    const result = try testEmitResult(std.testing.allocator, "export { foo as bar };");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "foo as bar"));
}

test "emit: preserves as in import star" {
    const result = try testEmitResult(std.testing.allocator, "import * as foo from \"./mod\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "* as foo"));
}

test "emit: strips satisfies type assertion" {
    const result = try testEmitResult(std.testing.allocator, "const x = foo satisfies string;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const x="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "satisfies string"));
}

test "emit: preserves satisfies as identifier when not expression" {
    const result = try testEmitResult(std.testing.allocator, "const satisfies = 5;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const satisfies"));
}

// --- Non-null assertion stripping tests ---

test "emit: strips non-null assertion before semicolon" {
    const result = try testEmitResult(std.testing.allocator, "const x = foo!;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "const x="));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "!"));
}

test "emit: strips non-null assertion before property access" {
    const result = try testEmitResult(std.testing.allocator, "const x = foo!.bar;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "foo.bar"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "!"));
}

test "emit: strips non-null assertion before bracket access" {
    const result = try testEmitResult(std.testing.allocator, "const x = foo![0];");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "foo[0]"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "!"));
}

test "emit: strips non-null assertion before comma" {
    const result = try testEmitResult(std.testing.allocator, "const x = fn(a!, b);");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "fn(a,"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "!"));
}

test "emit: preserves logical NOT operator" {
    const result = try testEmitResult(std.testing.allocator, "const x = !condition;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "!condition"));
}

test "emit: preserves not-equal operator" {
    const result = try testEmitResult(std.testing.allocator, "if (x != y) {}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "!="));
}

// --- Visibility modifier stripping tests ---

test "emit: strips public modifier in class body" {
    const result = try testEmitResult(std.testing.allocator, "class C { public foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C { foo()"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "public"));
}

test "emit: strips private modifier in class body" {
    const result = try testEmitResult(std.testing.allocator, "class C { private foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C { foo()"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "private"));
}

test "emit: strips protected modifier in class body" {
    const result = try testEmitResult(std.testing.allocator, "class C { protected foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C { foo()"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "protected"));
}

test "emit: strips readonly in class body" {
    const result = try testEmitResult(std.testing.allocator, "class C { readonly x: number = 5; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "readonly"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "x="));
}

test "emit: strips class property type annotation" {
    const result = try testEmitResult(std.testing.allocator, "class C { x: number = 5; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "x="));
}

test "emit: strips class property type annotation without initializer" {
    const result = try testEmitResult(std.testing.allocator, "class C { x: string; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": string"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "x;"));
}

test "emit: strips class property with complex type annotation" {
    const result = try testEmitResult(std.testing.allocator, "class C { items: Array<string> = []; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": Array<string>"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "items="));
}

test "emit: strips multiple class property type annotations" {
    const result = try testEmitResult(std.testing.allocator, "class C { a: number = 1; b: string = \"x\"; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": string"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "a="));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "b="));
}

test "emit: strips method return type alongside property type annotations" {
    const result = try testEmitResult(std.testing.allocator, "class C { x: number = 1; foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, ": void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "x="));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "foo()"));
}

test "emit: strips override modifier in class body" {
    const result = try testEmitResult(std.testing.allocator, "class C extends B { override foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C extends B { foo()"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "override"));
}

test "emit: strips abstract method in class body" {
    const result = try testEmitResult(std.testing.allocator, "class C { abstract foo(): void; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "abstract"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "foo"));
}

test "emit: strips abstract method with param types entirely" {
    const result = try testEmitResult(std.testing.allocator, "class C { abstract bar(x: number, y: string): void; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "abstract"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "bar"));
}

test "emit: preserves abstract class inside class body" {
    const result = try testEmitResult(std.testing.allocator, "class C { abstract class Inner { } }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C { class Inner"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "abstract"));
}

test "emit: strips visibility modifier before static" {
    const result = try testEmitResult(std.testing.allocator, "class C { public static foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "static foo()"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "public"));
}

test "emit: preserves static (not a visibility modifier)" {
    const result = try testEmitResult(std.testing.allocator, "class C { static foo(): void {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "static"));
}

test "emit: preserves public as identifier outside class" {
    const result = try testEmitResult(std.testing.allocator, "const obj = { public: 1 };");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "public: 1"));
}

test "emit: strips constructor parameter property" {
    const result = try testEmitResult(std.testing.allocator, "class C { constructor(private x: number) {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "constructor(x)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "private"));
}

test "emit: strips multiple constructor parameter properties" {
    const result = try testEmitResult(std.testing.allocator, "class C { constructor(public a: string, protected b: number, private c: boolean) {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "constructor(a,b,c)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "public"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "protected"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "private"));
}

test "emit: strips readonly in constructor parameter" {
    const result = try testEmitResult(std.testing.allocator, "class C { constructor(readonly x: number) {} }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "constructor(x)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "readonly"));
}

// --- Import/export type stripping tests ---

test "emit: strips type from import type { }" {
    const result = try testEmitResult(std.testing.allocator, "import type { X } from \"./mod\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "import { X }"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "import type"));
}

test "emit: strips type from export type { }" {
    const result = try testEmitResult(std.testing.allocator, "export type { X };");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export { X }"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "export type"));
}

test "emit: strips type from export type *" {
    const result = try testEmitResult(std.testing.allocator, "export type * from \"./mod\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "export * from"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "export type *"));
}

test "emit: still strips type alias after export" {
    const result = try testEmitResult(std.testing.allocator, "export type Foo = string | number;");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "emit: preserves regular import" {
    const result = try testEmitResult(std.testing.allocator, "import { X } from \"./mod\";");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "import { X }"));
}

// --- this parameter stripping tests ---

test "emit: strips this parameter from function" {
    const result = try testEmitResult(std.testing.allocator, "function fn(this: MyType, x: number): void {}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function fn(x){}"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "this"));
}

test "emit: strips this parameter alone (no other params)" {
    const result = try testEmitResult(std.testing.allocator, "function fn(this: MyType): void {}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function fn(){}"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "this"));
}

test "emit: strips this parameter with callback type" {
    const result = try testEmitResult(std.testing.allocator, "function fn(this: { x: number }, cb: () => void): void {}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function fn(cb){}"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "this"));
}

test "emit: preserves regular function without this param" {
    const result = try testEmitResult(std.testing.allocator, "function fn(x: number): void {}");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function fn(x)"));
}

// --- Decorator stripping tests ---

test "emit: strips simple decorator before class" {
    const result = try testEmitResult(std.testing.allocator, "@decorator\nclass C { }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "@decorator"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C"));
}

test "emit: strips decorator with call expression before class" {
    const result = try testEmitResult(std.testing.allocator, "@decorator(arg)\nclass C { }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "@decorator"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "class C"));
}

test "emit: strips decorator before function" {
    const result = try testEmitResult(std.testing.allocator, "@myDecorator\nfunction foo() { }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "@myDecorator"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "function foo()"));
}

test "emit: strips decorator before method" {
    const result = try testEmitResult(std.testing.allocator, "class C { @readonly prop = 1; }");
    defer std.testing.allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "@readonly"));
}

test "emit: preserves @ as numerical operator" {
    const result = try testEmitResult(std.testing.allocator, "const x = a @ b;");
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "@"));
}

// --- JSDoc preservation tests ---

test "declaration: preserves JSDoc comment before function" {
    const input = "/**\n * Adds two numbers\n * @param a First number\n * @param b Second number\n */\nexport function add(a: number, b: number): number {\n    return a + b;\n}";
    const expected = "/**\n * Adds two numbers\n * @param a First number\n * @param b Second number\n */\nexport function add(a: number, b: number): number;\n";

    var emitter = TypeScriptEmitter.init(std.testing.allocator, input);
    const result = try emitter.emitDeclarations();
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(expected, result);
}

test "declaration: preserves JSDoc comment before interface" {
    const input = "/** Interface for a person */\ninterface Person {\n    name: string;\n}";
    const expected = "/** Interface for a person */\ninterface Person {\n    name: string;\n};\n";

    var emitter = TypeScriptEmitter.init(std.testing.allocator, input);
    const result = try emitter.emitDeclarations();
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(expected, result);
}


test "declaration: preserves JSDoc comment before class" {
    const input = "/**\n * A simple class example\n */\nclass Greeter {\n    greeting: string;\n}";
    
    var emitter = TypeScriptEmitter.init(std.testing.allocator, input);
    const result = try emitter.emitDeclarations();
    defer std.testing.allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "/**") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "class Greeter") != null);
}

test "emit: preserves JSDoc comment before function" {
    const input = "/**\n * Adds two numbers\n * @param a First number\n * @param b Second number\n */\nexport function add(a: number, b: number): number {\n    return a + b;\n}";

    var emitter = TypeScriptEmitter.init(std.testing.allocator, input);
    const result = try emitter.emit();
    defer std.testing.allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "/**") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "@param") != null);
}

test "emit: preserves JSDoc comment before class" {
    const input = "/** Class description */\n@sealed\nclass MyClass {\n    value: number;\n}";

    var emitter = TypeScriptEmitter.init(std.testing.allocator, input);
    const result = try emitter.emit();
    defer std.testing.allocator.free(result);
    
    try std.testing.expect(std.mem.indexOf(u8, result, "/** Class description */") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "@sealed") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "class MyClass") != null);
}
