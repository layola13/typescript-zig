const std = @import("std");

pub const TokenizationSummary = struct {
    token_count: usize = 0,
    identifier_count: usize = 0,
    keyword_count: usize = 0,
    number_count: usize = 0,
    string_count: usize = 0,
    punctuation_count: usize = 0,
    diagnostics: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) TokenizationSummary {
        return .{
            .token_count = 0,
            .identifier_count = 0,
            .keyword_count = 0,
            .number_count = 0,
            .string_count = 0,
            .punctuation_count = 0,
            .diagnostics = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *TokenizationSummary, allocator: std.mem.Allocator) void {
        for (self.diagnostics.items) |diag| {
            allocator.free(diag);
        }
        self.diagnostics.deinit();
    }
};

pub fn tokenize(
    allocator: std.mem.Allocator,
    contents: []const u8,
) !TokenizationSummary {
    var summary = TokenizationSummary.init(allocator);
    errdefer summary.deinit(allocator);

    var i: usize = 0;
    while (i < contents.len) {
        const ch = contents[i];

        if (std.ascii.isWhitespace(ch)) {
            i += 1;
            continue;
        }

        if (ch == '/' and i + 1 < contents.len and contents[i + 1] == '/') {
            i += 2;
            while (i < contents.len and contents[i] != '\n') : (i += 1) {}
            continue;
        }

        if (ch == '/' and i + 1 < contents.len and contents[i + 1] == '*') {
            i += 2;
            var closed = false;
            while (i + 1 < contents.len) : (i += 1) {
                if (contents[i] == '*' and contents[i + 1] == '/') {
                    i += 2;
                    closed = true;
                    break;
                }
            }
            if (!closed) {
                try summary.diagnostics.append(try allocator.dupe(u8, "Unterminated block comment"));
                break;
            }
            continue;
        }

        if (isIdentifierStart(ch)) {
            const start = i;
            i += 1;
            while (i < contents.len and isIdentifierContinue(contents[i])) : (i += 1) {}
            const ident = contents[start..i];
            summary.token_count += 1;
            if (isKeyword(ident)) {
                summary.keyword_count += 1;
            } else {
                summary.identifier_count += 1;
            }
            continue;
        }

        if (std.ascii.isDigit(ch)) {
            i += 1;
            while (i < contents.len and (std.ascii.isDigit(contents[i]) or contents[i] == '.')) : (i += 1) {}
            summary.token_count += 1;
            summary.number_count += 1;
            continue;
        }

        if (ch == '\'' or ch == '"' or ch == '`') {
            const quote = ch;
            i += 1;
            var escaped = false;
            var closed = false;
            while (i < contents.len) : (i += 1) {
                const current = contents[i];
                if (escaped) {
                    escaped = false;
                    continue;
                }
                if (current == '\\') {
                    escaped = true;
                    continue;
                }
                if (current == quote) {
                    closed = true;
                    i += 1;
                    break;
                }
            }
            if (!closed) {
                const message = switch (quote) {
                    '\'' => "Unterminated single-quoted string",
                    '"' => "Unterminated double-quoted string",
                    '`' => "Unterminated template string",
                    else => unreachable,
                };
                try summary.diagnostics.append(try allocator.dupe(u8, message));
                break;
            }
            summary.token_count += 1;
            summary.string_count += 1;
            continue;
        }

        // Decorator: @identifier or @identifier(args)
        if (ch == '@') {
            i += 1;
            summary.token_count += 1;
            summary.punctuation_count += 1;
            // Skip whitespace after @
            while (i < contents.len and std.ascii.isWhitespace(contents[i])) : (i += 1) {}
            // Skip the decorator expression (identifier + optional call args)
            if (i < contents.len and (std.ascii.isAlphabetic(contents[i]) or contents[i] == '_' or contents[i] == '$')) {
                // Skip identifier
                while (i < contents.len and (std.ascii.isAlphanumeric(contents[i]) or contents[i] == '_' or contents[i] == '$')) : (i += 1) {}
                // Skip optional call arguments (...)
                if (i < contents.len and contents[i] == '(') {
                    var paren_depth: usize = 1;
                    i += 1;
                    while (i < contents.len and paren_depth > 0) {
                        const c = contents[i];
                        if (c == '\\') {
                            i += 2;
                            continue;
                        }
                        if (c == '\'' or c == '"' or c == '`') {
                            const quote = c;
                            i += 1;
                            while (i < contents.len and contents[i] != quote) {
                                if (contents[i] == '\\') i += 1;
                                i += 1;
                            }
                            if (i < contents.len) i += 1;
                        } else if (c == '(') {
                            paren_depth += 1;
                            i += 1;
                        } else if (c == ')') {
                            paren_depth -= 1;
                            i += 1;
                        } else {
                            i += 1;
                        }
                    }
                }
            }
            continue;
        }

        if (isPunctuation(ch)) {
            i += 1;
            summary.token_count += 1;
            summary.punctuation_count += 1;
            continue;
        }

        try summary.diagnostics.append(
            try std.fmt.allocPrint(allocator, "Unexpected character '{c}'", .{ch}),
        );
        i += 1;
    }

    return summary;
}

fn isIdentifierStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_' or ch == '$';
}

fn isIdentifierContinue(ch: u8) bool {
    return isIdentifierStart(ch) or std.ascii.isDigit(ch);
}

fn isPunctuation(ch: u8) bool {
    return switch (ch) {
        '(', ')', '{', '}', '[', ']', ';', ':', ',', '.', '?', '+', '-', '*', '/', '%', '=', '!', '<', '>', '&', '|', '^', '\\' => true,
        else => false,
    };
}

fn isKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "const", "let", "var", "function", "return", "if", "else", "for", "while", "class", "interface", "type", "import", "export", "from", "extends", "new", "await", "async", "switch", "case", "default", "try", "catch", "finally",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, value, keyword)) return true;
    }
    return false;
}

test "tokenize counts basic token classes" {
    var summary = try tokenize(std.testing.allocator, "export const value = 42;");
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), summary.token_count);
    try std.testing.expectEqual(@as(usize, 2), summary.keyword_count);
    try std.testing.expectEqual(@as(usize, 1), summary.identifier_count);
    try std.testing.expectEqual(@as(usize, 1), summary.number_count);
    try std.testing.expectEqual(@as(usize, 2), summary.punctuation_count);
}

test "tokenize reports unterminated strings" {
    var summary = try tokenize(std.testing.allocator, "const value = \"x;");
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), summary.diagnostics.items.len);
}
