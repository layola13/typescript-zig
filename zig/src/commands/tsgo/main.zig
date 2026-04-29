const std = @import("std");
const sys = @import("sys.zig");
const lsp = @import("lsp.zig");
const api = @import("api.zig");
const compile = @import("../compile.zig");
const cli_types = @import("../../cli/types.zig");

/// Main entry point for the tsgo command
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var system = try sys.System.init(allocator);
    defer system.deinit();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    const exit_code = try run(&args, &system);
    std.process.exit(exit_code);
}

/// Run the tsgo command with the given arguments
pub fn run(args: *std.process.ArgIterator, system: *sys.System) !u8 {
    var argv = std.ArrayList([]const u8).init(system.allocator);
    defer argv.deinit();

    while (args.next()) |arg| {
        try argv.append(arg);
    }

    return try runSlice(argv.items, system);
}

fn runSlice(args: []const []const u8, system: *sys.System) !u8 {
    if (args.len == 0) {
        // No subcommand, run compile
        return try compileCommand(args, system);
    }

    const subcommand = args[0];
    const subargs = args[1..];

    if (std.mem.eql(u8, subcommand, "--lsp")) {
        return try lsp.run(subargs, system);
    } else if (std.mem.eql(u8, subcommand, "--api")) {
        return try api.run(subargs, system);
    }

    // Default to compile command
    return try compileCommand(args, system);
}

fn compileCommand(args: []const []const u8, system: *sys.System) !u8 {
    _ = system;
    
    // Wrap args for compile command
    var wrapped = std.ArrayList([]const u8).init(system.allocator);
    defer wrapped.deinit();
    try wrapped.appendSlice(args);

    var parsed = cli_types.ParsedArgs.init(system.allocator);
    defer parsed.deinit();

    // TODO: Parse arguments into cli_types.ParsedArgs properly
    parsed.command = .compile;

    // Run the compile command
    return try compile.run(&parsed, std.io.getStdOut().writer());
}

test "main entry point" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var system = try sys.System.init(allocator);
    defer system.deinit();

    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    const exit_code = try runSlice(args.items, &system);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}
