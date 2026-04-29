const std = @import("std");

pub const InitTemplate =
    \\{
    \\  "compilerOptions": {
    \\    "module": "nodenext",
    \\    "target": "esnext",
    \\    "strict": true,
    \\    "skipLibCheck": true
    \\  }
    \\}
    \\
;

pub fn projectExists(project_path: []const u8) bool {
    const cwd = std.fs.cwd();

    if (cwd.access(project_path, .{})) |_| {
        return true;
    } else |_| {}

    if (cwd.openDir(project_path, .{})) |opened_dir| {
        var dir = opened_dir;
        defer dir.close();
        dir.access("tsconfig.json", .{}) catch return false;
        return true;
    } else |_| {}

    return false;
}

pub fn resolveProjectPath(allocator: std.mem.Allocator, project_path: []const u8) ?[]const u8 {
    const cwd = std.fs.cwd();

    if (cwd.openDir(project_path, .{})) |opened_dir| {
        var dir = opened_dir;
        defer dir.close();
        dir.access("tsconfig.json", .{}) catch return null;
        return std.fmt.allocPrint(allocator, "{s}{c}tsconfig.json", .{
            project_path,
            std.fs.path.sep,
        }) catch null;
    } else |_| {}

    if (cwd.access(project_path, .{})) |_| {
        return allocator.dupe(u8, project_path) catch null;
    } else |_| {}

    return null;
}

pub fn findAncestorTsconfigPath(allocator: std.mem.Allocator) ?[]const u8 {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_path = std.process.getCwd(&cwd_buffer) catch return null;

    var search_buffer: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(search_buffer[0..cwd_path.len], cwd_path);
    var current_len = cwd_path.len;

    while (true) {
        var candidate_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const candidate = std.fmt.bufPrint(&candidate_buffer, "{s}{c}tsconfig.json", .{
            search_buffer[0..current_len],
            std.fs.path.sep,
        }) catch return null;

        if (std.fs.accessAbsolute(candidate, .{})) |_| {
            return allocator.dupe(u8, candidate) catch null;
        } else |_| {}

        const parent = std.fs.path.dirname(search_buffer[0..current_len]) orelse return null;
        if (parent.len == current_len) {
            return null;
        }
        current_len = parent.len;
    }
}

pub fn readConfig(allocator: std.mem.Allocator, config_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(config_path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 1024 * 1024);
}

pub fn writeInitConfig(output_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_path, .{ .exclusive = true });
    defer file.close();
    try file.writeAll(InitTemplate);
}

test "resolve project directory to tsconfig file" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    try temp.dir.makePath("sample");
    var sample_dir = try temp.dir.openDir("sample", .{});
    defer sample_dir.close();
    var file = try sample_dir.createFile("tsconfig.json", .{});
    defer file.close();
    try file.writeAll("{}");

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    const resolved = resolveProjectPath(std.testing.allocator, "sample");
    defer if (resolved) |path| std.testing.allocator.free(path);

    try std.testing.expect(resolved != null);
    try std.testing.expectEqualStrings("sample/tsconfig.json", resolved.?);
}

test "find ancestor tsconfig path" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    try temp.dir.makePath("root/nested/deep");
    var root_dir = try temp.dir.openDir("root", .{});
    defer root_dir.close();
    var file = try root_dir.createFile("tsconfig.json", .{});
    defer file.close();
    try file.writeAll("{}");

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    var deep_dir = try temp.dir.openDir("root/nested/deep", .{});
    defer deep_dir.close();
    try deep_dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    const resolved = findAncestorTsconfigPath(std.testing.allocator);
    defer if (resolved) |path| std.testing.allocator.free(path);

    try std.testing.expect(resolved != null);
    try std.testing.expect(std.mem.endsWith(u8, resolved.?, "/root/tsconfig.json"));
}
