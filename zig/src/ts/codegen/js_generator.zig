const std = @import("std");

/// JavaScript code generator configuration
pub const GeneratorConfig = struct {
    target: Target = .es2020,
    strict_mode: bool = true,
    esm_compat: bool = false,
};

pub const Target = enum {
    es2020,
    es2022,
    esnext,
};

/// JavaScript code generator
pub const CodeGenerator = struct {
    allocator: std.mem.Allocator,
    config: GeneratorConfig,
    buffer: std.ArrayList(u8),
    indent: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, config: GeneratorConfig) CodeGenerator {
        return .{
            .allocator = allocator,
            .config = config,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn writeIndent(self: *CodeGenerator) void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) {
            self.buffer.appendSlice("  ") catch unreachable;
        }
    }

    pub fn writeLine(self: *CodeGenerator, text: []const u8) void {
        self.writeIndent();
        self.buffer.appendSlice(text) catch unreachable;
        self.buffer.append('
') catch unreachable;
    }

    pub fn generateVariableDeclaration(self: *CodeGenerator, name: []const u8, value: []const u8, is_const: bool) void {
        const kw = if (is_const) "const " else "let ";
        self.writeIndent();
        self.buffer.appendSlice(kw) catch unreachable;
        self.buffer.appendSlice(name) catch unreachable;
        self.buffer.appendSlice(" = ") catch unreachable;
        self.buffer.appendSlice(value) catch unreachable;
        self.buffer.append(';') catch unreachable;
        self.buffer.append('
') catch unreachable;
    }

    pub fn pushBlock(self: *CodeGenerator) void {
        self.writeLine("{");
        self.indent += 1;
    }

    pub fn popBlock(self: *CodeGenerator) void {
        if (self.indent > 0) self.indent -= 1;
        self.writeLine("}");
    }

    pub fn output(self: *CodeGenerator) []const u8 {
        return self.buffer.items;
    }

    pub fn destroy(self: *CodeGenerator) void {
        self.buffer.deinit();
    }
};
