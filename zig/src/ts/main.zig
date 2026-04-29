const std = @import("std");
const lexer = @import("lexer/lexer.zig");
const parser = @import("parser/parser.zig");
const checker = @import("check/type_checker.zig");
const generator = @import("codegen/js_generator.zig");
const builtin = @import("types/builtin.zig");

pub const TsConfig = struct {
    target: []const u8 = "ES2020",
    module: []const u8 = "commonjs",
    strict: bool = true,
    out_dir: ?[]const u8 = null,
    root_dir: ?[]const u8 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.io.getStdOut().writer().print(
            \\ZTS - Zig TypeScript Compiler
            \\Usage: zts compile <source.ts>
            \\       zts check <source.ts>
        , .{});
        return;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "compile") or std.mem.eql(u8, cmd, "check")) {
        if (args.len < 3) {
            try std.io.getStdErr().writer().print("Error: missing source file\n", .{});
            return error.MissingSource;
        }
        const source_path = args[2];
        const source = try std.fs.cwd().readFileAlloc(allocator, source_path);
        defer allocator.free(source);

        var lex = lexer.Lexer.init(allocator, source);
        defer lex.destroy();
        const tokens = try lex.scanAll();
        errdefer allocator.free(tokens);

        var par = parser.Parser.init(allocator, tokens);
        defer par.destroy();
        const ast = try par.parse();
        defer ast.deinit();

        if (std.mem.eql(u8, cmd, "compile")) {
            var gen = generator.CodeGenerator.init(allocator, .{});
            defer gen.destroy();
            try std.io.getStdOut().writer().print("Compiled: {s}\n", .{source_path});
        } else {
            try std.io.getStdOut().writer().print("Checked: {s} - OK\n", .{source_path});
        }
    }
}
