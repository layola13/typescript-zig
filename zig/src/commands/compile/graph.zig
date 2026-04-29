const std = @import("std");
const plan = @import("./plan.zig");
const source = @import("./source.zig");

pub const EdgeKind = enum {
    internal,
    external,
    unresolved,
};

pub const Edge = struct {
    from_index: usize,
    to_index: ?usize,
    specifier: []const u8,
    from_path: []const u8,
    kind: EdgeKind,
    target_path: ?[]const u8 = null,
};

pub const CycleInfo = struct {
    first_index: usize,
    second_index: usize,
    path: []const u8,
};

pub const Analysis = struct {
    cycle_infos: std.ArrayList(CycleInfo),
    unreachable_indices: std.ArrayList(usize),
    reachable_source_count: usize = 0,
    unreachable_source_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Analysis {
        return .{
            .cycle_infos = std.ArrayList(CycleInfo).init(allocator),
            .unreachable_indices = std.ArrayList(usize).init(allocator),
            .reachable_source_count = 0,
            .unreachable_source_count = 0,
        };
    }

    pub fn deinit(self: *Analysis, allocator: std.mem.Allocator) void {
        for (self.cycle_infos.items) |info| {
            allocator.free(info.path);
        }
        self.cycle_infos.deinit();
        self.unreachable_indices.deinit();
    }
};

pub fn findSourceFileIndex(
    allocator: std.mem.Allocator,
    loaded: *const source.SourceLoadSummary,
    path: []const u8,
) !?usize {
    const normalized_path = try normalizeComparablePath(allocator, path);
    defer allocator.free(normalized_path);

    for (loaded.source_files.items, 0..) |source_file, index| {
        if (std.mem.eql(u8, source_file.path, path)) return index;

        const normalized_source = try normalizeComparablePath(allocator, source_file.path);
        defer allocator.free(normalized_source);
        if (std.mem.eql(u8, normalized_source, normalized_path)) return index;
    }
    return null;
}

fn normalizeComparablePath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    return std.fs.cwd().realpathAlloc(allocator, path) catch |err| switch (err) {
        error.FileNotFound => std.fs.path.resolve(allocator, &.{path}),
        else => err,
    };
}

pub fn analyze(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    loaded: *const source.SourceLoadSummary,
    edges: []const Edge,
) !Analysis {
    var analysis = Analysis.init(allocator);
    errdefer analysis.deinit(allocator);

    try detectImportCycles(allocator, loaded, edges, &analysis);
    try detectReachability(allocator, compile_plan, loaded, edges, &analysis);

    return analysis;
}

fn detectImportCycles(
    allocator: std.mem.Allocator,
    loaded: *const source.SourceLoadSummary,
    edges: []const Edge,
    analysis: *Analysis,
) !void {
    const source_count = loaded.source_files.items.len;
    if (source_count == 0) return;

    var adjacency = std.ArrayList(std.ArrayList(usize)).init(allocator);
    defer {
        for (adjacency.items) |*bucket| bucket.deinit();
        adjacency.deinit();
    }

    for (0..source_count) |_| {
        try adjacency.append(std.ArrayList(usize).init(allocator));
    }

    for (edges) |edge| {
        if (edge.kind != .internal) continue;
        const to_index = edge.to_index orelse continue;
        try appendUniqueIndex(&adjacency.items[edge.from_index], to_index);
    }

    var index: usize = 0;
    const indices = try allocator.alloc(?usize, source_count);
    defer allocator.free(indices);
    const lowlinks = try allocator.alloc(usize, source_count);
    defer allocator.free(lowlinks);
    const on_stack = try allocator.alloc(bool, source_count);
    defer allocator.free(on_stack);
    for (indices) |*value| value.* = null;
    @memset(lowlinks, 0);
    @memset(on_stack, false);

    var stack = std.ArrayList(usize).init(allocator);
    defer stack.deinit();

    for (0..source_count) |node| {
        if (indices[node] == null) {
            try strongConnect(
                allocator,
                loaded,
                &adjacency,
                &index,
                indices,
                lowlinks,
                on_stack,
                &stack,
                node,
                analysis,
            );
        }
    }
}

fn strongConnect(
    allocator: std.mem.Allocator,
    loaded: *const source.SourceLoadSummary,
    adjacency: *const std.ArrayList(std.ArrayList(usize)),
    index: *usize,
    indices: []?usize,
    lowlinks: []usize,
    on_stack: []bool,
    stack: *std.ArrayList(usize),
    node: usize,
    analysis: *Analysis,
) !void {
    indices[node] = index.*;
    lowlinks[node] = index.*;
    index.* += 1;
    try stack.append(node);
    on_stack[node] = true;

    for (adjacency.items[node].items) |neighbor| {
        if (indices[neighbor] == null) {
            try strongConnect(allocator, loaded, adjacency, index, indices, lowlinks, on_stack, stack, neighbor, analysis);
            lowlinks[node] = @min(lowlinks[node], lowlinks[neighbor]);
        } else if (on_stack[neighbor]) {
            lowlinks[node] = @min(lowlinks[node], indices[neighbor].?);
        }
    }

    if (lowlinks[node] != indices[node].?) return;

    var component = std.ArrayList(usize).init(allocator);
    defer component.deinit();

    while (stack.items.len > 0) {
        const popped = stack.pop().?;
        on_stack[popped] = false;
        try component.append(popped);
        if (popped == node) break;
    }

    if (component.items.len > 1 or hasSelfLoop(adjacency.items[node].items, node)) {
        const first = component.items[0];
        const second = if (component.items.len > 1) component.items[1] else component.items[0];
        try analysis.cycle_infos.append(.{
            .first_index = first,
            .second_index = second,
            .path = try formatCyclePath(allocator, loaded, component.items),
        });
    }
}

fn detectReachability(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    loaded: *const source.SourceLoadSummary,
    edges: []const Edge,
    analysis: *Analysis,
) !void {
    const source_count = loaded.source_files.items.len;
    if (source_count == 0) return;

    var roots = std.ArrayList(usize).init(allocator);
    defer roots.deinit();

    for (compile_plan.cli_entry_files.items) |entry| {
        if (try findEntryRootIndex(allocator, compile_plan, loaded, entry)) |index| {
            try appendUniqueIndex(&roots, index);
        }
    }
    for (compile_plan.explicit_files.items) |entry| {
        if (try findEntryRootIndex(allocator, compile_plan, loaded, entry)) |index| {
            try appendUniqueIndex(&roots, index);
        }
    }

    if (roots.items.len == 0) return;

    var adjacency = std.ArrayList(std.ArrayList(usize)).init(allocator);
    defer {
        for (adjacency.items) |*bucket| bucket.deinit();
        adjacency.deinit();
    }

    for (0..source_count) |_| {
        try adjacency.append(std.ArrayList(usize).init(allocator));
    }
    for (edges) |edge| {
        if (edge.kind != .internal) continue;
        const to_index = edge.to_index orelse continue;
        try appendUniqueIndex(&adjacency.items[edge.from_index], to_index);
    }

    const visited = try allocator.alloc(bool, source_count);
    defer allocator.free(visited);
    @memset(visited, false);

    var queue = std.ArrayList(usize).init(allocator);
    defer queue.deinit();

    for (roots.items) |root| {
        if (!visited[root]) {
            visited[root] = true;
            try queue.append(root);
        }
    }

    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const node = queue.items[cursor];
        for (adjacency.items[node].items) |neighbor| {
            if (visited[neighbor]) continue;
            visited[neighbor] = true;
            try queue.append(neighbor);
        }
    }

    for (visited) |is_reachable| {
        if (is_reachable) analysis.reachable_source_count += 1;
    }
    analysis.unreachable_source_count = source_count - analysis.reachable_source_count;

    for (visited, 0..) |is_reachable, idx| {
        if (!is_reachable) {
            try analysis.unreachable_indices.append(idx);
        }
    }
}

fn resolveEntryPathForReachability(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    entry: []const u8,
) ![]u8 {
    if (std.fs.path.isAbsolute(entry)) {
        return allocator.dupe(u8, entry);
    }
    if (compile_plan.config_dir) |config_dir| {
        return std.fs.path.join(allocator, &.{ config_dir, entry });
    }
    return allocator.dupe(u8, entry);
}

fn findEntryRootIndex(
    allocator: std.mem.Allocator,
    compile_plan: *const plan.CompilePlan,
    loaded: *const source.SourceLoadSummary,
    entry: []const u8,
) !?usize {
    if (try findSourceFileIndex(allocator, loaded, entry)) |index| {
        return index;
    }

    const resolved = try resolveEntryPathForReachability(allocator, compile_plan, entry);
    defer allocator.free(resolved);
    return findSourceFileIndex(allocator, loaded, resolved);
}

fn formatCyclePath(
    allocator: std.mem.Allocator,
    loaded: *const source.SourceLoadSummary,
    component: []const usize,
) ![]u8 {
    if (component.len == 0) return allocator.dupe(u8, "");

    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    var i = component.len;
    while (i > 0) {
        i -= 1;
        try buffer.writer().print("{s}", .{loaded.source_files.items[component[i]].path});
        if (i > 0) {
            try buffer.writer().writeAll(" -> ");
        }
    }
    try buffer.writer().print(" -> {s}", .{loaded.source_files.items[component[component.len - 1]].path});
    return buffer.toOwnedSlice();
}

fn hasSelfLoop(edges: []const usize, node: usize) bool {
    for (edges) |edge| {
        if (edge == node) return true;
    }
    return false;
}

fn appendUniqueIndex(
    list: *std.ArrayList(usize),
    value: usize,
) !void {
    for (list.items) |existing| {
        if (existing == value) return;
    }
    try list.append(value);
}

pub fn freeEdges(
    allocator: std.mem.Allocator,
    edges: *std.ArrayList(Edge),
) void {
    for (edges.items) |edge| {
        allocator.free(edge.from_path);
        if (edge.target_path) |path| allocator.free(path);
    }
    edges.deinit();
}
