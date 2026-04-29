const std = @import("std");
const cli_types = @import("./cli/types.zig");
const cli_parse = @import("./cli/parse.zig");
const cli_help = @import("./cli/help.zig");
const version_info = @import("./version.zig");
const compile_cmd = @import("./commands/compile.zig");
const lsp_cmd = @import("./commands/lsp.zig");
const api_cmd = @import("./commands/api.zig");
const compile_config = @import("./commands/compile/config.zig");
const compile_execute = @import("./commands/compile/execute.zig");
const compile_parse = @import("./commands/compile/parse.zig");
const compile_plan = @import("./commands/compile/plan.zig");
const compile_source = @import("./commands/compile/source.zig");
const compile_tokenizer = @import("./commands/compile/tokenizer.zig");
const compile_parser = @import("./commands/compile/parser.zig");
const compile_binder = @import("./commands/compile/binder.zig");
const compile_graph = @import("./commands/compile/graph.zig");
const compile_checker = @import("./commands/compile/checker.zig");
const compile_runtime = @import("./commands/compile/runtime.zig");

pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();

    _ = args.next();
    const status = try run(&args, stdin, stdout, stderr);
    std.process.exit(status);
}

fn run(
    args: *std.process.ArgIterator,
    stdin: anytype,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    _ = stderr;

    var argv = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer argv.deinit();
    while (args.next()) |arg| {
        try argv.append(arg);
    }

    return try runSlice(argv.items, stdin, stdout);
}

fn runSlice(
    argv: []const []const u8,
    stdin: anytype,
    stdout: anytype,
) !u8 {
    const graph_json = hasGraphJson(argv);

    var parsed = try cli_parse.parseArgsSlice(std.heap.page_allocator, argv);
    defer parsed.deinit();

    switch (parsed.command) {
        .help => {
            if (graph_json) {
                try writeTopLevelActionGraphJson(stdout, "help", "help", argv, cli_help.text);
                return 0;
            }
            try cli_help.printHelp(stdout);
            return 0;
        },
        .version => {
            if (graph_json) {
                try writeTopLevelActionGraphJson(stdout, "version", "version", argv, version_info.value);
                return 0;
            }
            try stdout.print("zts {s}\n", .{version_info.value});
            return 0;
        },
        .compile => return try compile_cmd.run(&parsed, stdout),
        .lsp => return try lsp_cmd.run(&parsed, stdin, stdout),
        .api => return try api_cmd.run(&parsed, stdin, stdout),
    }
}

fn hasGraphJson(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--graphJson")) return true;
    }
    return false;
}

fn writeTopLevelActionGraphJson(
    writer: anytype,
    stage: []const u8,
    action: []const u8,
    argv: []const []const u8,
    content: []const u8,
) !void {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    try writer.writeAll("{\"status\":\"ok\",\"schemaVersion\":1,\"cwd\":");
    try std.json.encodeJsonString(cwd, .{}, writer);
    try writer.writeAll(",\"exitCode\":0,\"stage\":");
    try std.json.encodeJsonString(stage, .{}, writer);
    try writer.writeAll(",\"action\":");
    try std.json.encodeJsonString(action, .{}, writer);
    try writer.writeAll(",\"command\":");
    try std.json.encodeJsonString(action, .{}, writer);
    try writer.writeAll(",\"passthrough\":[");
    for (argv, 0..) |arg, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(arg, .{}, writer);
    }
    try writer.writeAll("],\"content\":");
    try std.json.encodeJsonString(content, .{}, writer);
    try writer.writeAll("}\n");
}

test {
    _ = cli_types;
    _ = cli_parse;
    _ = compile_cmd;
    _ = compile_parse;
    _ = compile_config;
    _ = compile_execute;
    _ = compile_plan;
    _ = compile_source;
    _ = compile_tokenizer;
    _ = compile_parser;
    _ = compile_binder;
    _ = compile_graph;
    _ = compile_checker;
    _ = compile_runtime;
}

test "top-level help with graphJson emits pure json" {
    const argv = [_][]const u8{ "--help", "--graphJson" };
    var input = std.io.fixedBufferStream("");
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try runSlice(argv[0..], input.reader(), buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"help\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"passthrough\":[\"--help\",\"--graphJson\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"content\":\"zts - Zig TypeScript compiler prototype") != null);
}

test "top-level version with graphJson emits pure json" {
    const argv = [_][]const u8{ "--version", "--graphJson" };
    var input = std.io.fixedBufferStream("");
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try runSlice(argv[0..], input.reader(), buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"passthrough\":[\"--version\",\"--graphJson\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"content\":\"0.0.0-dev\"") != null);
}

test "top-level lsp with graphJson emits pure json" {
    const argv = [_][]const u8{ "lsp", "--stdio", "--graphJson" };
    var input = std.io.fixedBufferStream("");
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try runSlice(argv[0..], input.reader(), buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"lsp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"implemented\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"requestMethods\":[\"textDocument/hover\",\"textDocument/definition\",\"textDocument/declaration\",\"textDocument/typeDefinition\",\"textDocument/implementation\",\"textDocument/foldingRange\",\"textDocument/selectionRange\",\"textDocument/linkedEditingRange\",\"textDocument/inlayHint\",\"textDocument/documentColor\",\"textDocument/colorPresentation\",\"textDocument/documentLink\",\"textDocument/codeLens\",\"textDocument/documentSymbol\",\"textDocument/references\",\"textDocument/documentHighlight\",\"textDocument/codeAction\",\"textDocument/formatting\",\"textDocument/rangeFormatting\",\"textDocument/onTypeFormatting\",\"textDocument/rename\",\"textDocument/prepareRename\",\"workspace/symbol\",\"textDocument/completion\",\"completionItem/resolve\",\"textDocument/semanticTokens/full\",\"textDocument/signatureHelp\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"passthrough\":[\"--stdio\",\"--graphJson\"]") != null);
}

test "top-level api with graphJson emits pure json" {
    const argv = [_][]const u8{ "api", "--socket", "demo.sock", "--graphJson" };
    var input = std.io.fixedBufferStream("");
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    const exit_code = try runSlice(argv[0..], input.reader(), buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.startsWith(u8, buffer.items, "{\"status\":\"ok\""));
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"stage\":\"api\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"implemented\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"methods\":[\"initialize\",\"ping\",\"echo\",\"updateSnapshot\",\"release\",\"getDefaultProjectForFile\",\"parseConfigFile\",\"shutdown\",\"exit\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"passthrough\":[\"--socket\",\"demo.sock\",\"--graphJson\"]") != null);
}
