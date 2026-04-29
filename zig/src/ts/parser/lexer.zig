const std = @import("std");

/// Token types for TypeScript lexer
pub const TokenType = enum {
    keyword,
    identifier,
    string,
    number,
    punctuator,
    eof,
};

/// Source position tracking
pub const Position = struct {
    line: u32,
    column: u32,
    offset: u32,
};

/// Lexer for TypeScript source code
pub const Lexer = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    column: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{ .allocator = allocator, .source = source };
    }

    pub fn nextToken(self: *Lexer) !struct { type: TokenType, value: []const u8 } {
        if (self.pos >= self.source.len) {
            return .{ .type = .eof, .value = "" };
        }
        
        var start = self.pos;
        var c = self.source[self.pos];
        
        if (std.ascii.isWhitespace(c)) {
            while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
                if (self.source[self.pos] == '
') {
                    self.line += 1;
                    self.column = 0;
                }
                self.pos += 1;
            }
            return .{ .type = .identifier, .value = self.source[start..self.pos] };
        }
        
        if (std.ascii.isAlpha(c) or c == '_' or c == '$') {
            while (self.pos < self.source.len) {
                c = self.source[self.pos];
                if (!std.ascii.isAlNum(c) and c != '_' and c != '$') break;
                self.pos += 1;
            }
            return .{ .type = .identifier, .value = self.source[start..self.pos] };
        }
        
        if (std.ascii.isDigit(c)) {
            while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                self.pos += 1;
            }
            return .{ .type = .number, .value = self.source[start..self.pos] };
        }
        
        self.pos += 1;
        return .{ .type = .punctuator, .value = self.source[start..self.pos] };
    }

    pub fn tokenize(self: *Lexer) !std.ArrayList(struct { type: TokenType, value: []const u8 }) {
        var tokens = std.ArrayList(struct { type: TokenType, value: []const u8 }).init(self.allocator);
        while (true) {
            const tok = try self.nextToken();
            try tokens.append(tok);
            if (tok.type == .eof) break;
        }
        return tokens;
    }
};
