const std = @import("std");
const cli_types = @import("../cli/types.zig");
const version_info = @import("../version.zig");
const compile_config = @import("./compile/config.zig");
const compile_plan = @import("./compile/plan.zig");
const compile_types = @import("./compile/types.zig");

const SnapshotState = struct {
    open_project: ?[]u8 = null,
    invalidate_all: bool = false,
    changed_count: usize = 0,
    created_count: usize = 0,
    deleted_count: usize = 0,

    fn deinit(self: *SnapshotState) void {
        if (self.open_project) |value| {
            std.heap.page_allocator.free(value);
            self.open_project = null;
        }
    }
};

pub fn run(parsed: *const cli_types.ParsedArgs, reader: anytype, writer: anytype) !u8 {
    if (hasGraphJson(parsed.passthrough.items)) {
        try writeGraphJson(writer, parsed.passthrough.items);
        return 0;
    }

    if (hasPipe(parsed.passthrough.items)) {
        try writer.writeAll("pipe transport is not implemented yet\n");
        return 1;
    }

    if (hasAsync(parsed.passthrough.items)) {
        return try runAsyncStdio(reader, writer);
    }

    return try runSyncStdio(reader, writer);
}

fn hasGraphJson(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--graphJson")) return true;
    }
    return false;
}

fn hasAsync(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--async")) return true;
    }
    return false;
}

fn hasPipe(argv: []const []const u8) bool {
    for (argv, 0..) |arg, index| {
        if (std.mem.eql(u8, arg, "--pipe")) return true;
        if (std.mem.startsWith(u8, arg, "--pipe=")) return true;
        if (std.mem.eql(u8, arg, "--socket")) return true;
        if (std.mem.startsWith(u8, arg, "--socket=")) return true;
        if (std.mem.eql(u8, arg, "--pipe") and index + 1 < argv.len) return true;
        if (std.mem.eql(u8, arg, "--socket") and index + 1 < argv.len) return true;
    }
    return false;
}

fn writeGraphJson(writer: anytype, argv: []const []const u8) !void {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    try writer.writeAll("{\"status\":\"ok\",\"schemaVersion\":1,\"cwd\":");
    try std.json.encodeJsonString(cwd, .{}, writer);
    try writer.writeAll(",\"exitCode\":0,\"stage\":\"api\",\"action\":\"api\",\"command\":\"api\",\"implemented\":true,\"transport\":{\"asyncStdio\":true,\"syncMessagePack\":false,\"pipe\":false,\"socket\":false},\"methods\":[\"initialize\",\"ping\",\"echo\",\"updateSnapshot\",\"release\",\"getDefaultProjectForFile\",\"parseConfigFile\",\"shutdown\",\"exit\"],\"limitations\":[\"sync MessagePack API is not implemented yet\",\"pipe and socket transports are not implemented yet\"],\"passthrough\":[");
    for (argv, 0..) |arg, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(arg, .{}, writer);
    }
    try writer.writeAll("],\"content\":\"zts: api async stdio entrypoint is implemented\"}\n");
}

fn runAsyncStdio(reader: anytype, writer: anytype) !u8 {
    var saw_shutdown = false;
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);
    var latest_snapshot: ?[]u8 = null;
    var snapshots = std.StringHashMap(SnapshotState).init(std.heap.page_allocator);
    defer {
        if (latest_snapshot) |value| {
            std.heap.page_allocator.free(value);
        }
        var iterator = snapshots.iterator();
        while (iterator.next()) |entry| {
            std.heap.page_allocator.free(entry.key_ptr.*);
            var state = entry.value_ptr.*;
            state.deinit();
        }
        snapshots.deinit();
    }
    var next_snapshot_id: u64 = 1;

    while (true) {
        const maybe_payload = try readFrame(std.heap.page_allocator, reader);
        const payload = maybe_payload orelse break;
        defer std.heap.page_allocator.free(payload);

        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, payload, .{}) catch {
            try writeJsonRpcErrorNull(writer, -32700, "Parse error");
            continue;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) {
            try writeJsonRpcErrorNull(writer, -32600, "Invalid Request");
            continue;
        }

        const method_value = root.object.get("method") orelse {
            if (root.object.get("id")) |id| {
                try writeJsonRpcError(writer, id, -32600, "Invalid Request");
            } else {
                try writeJsonRpcErrorNull(writer, -32600, "Invalid Request");
            }
            continue;
        };
        if (method_value != .string) {
            if (root.object.get("id")) |id| {
                try writeJsonRpcError(writer, id, -32600, "Invalid Request");
            } else {
                try writeJsonRpcErrorNull(writer, -32600, "Invalid Request");
            }
            continue;
        }
        const method = method_value.string;

        if (std.mem.eql(u8, method, "initialize")) {
            if (root.object.get("id")) |id| {
                var result = std.ArrayList(u8).init(std.heap.page_allocator);
                defer result.deinit();
                try result.writer().writeAll("{\"useCaseSensitiveFileNames\":true,\"currentDirectory\":");
                try std.json.encodeJsonString(cwd, .{}, result.writer());
                try result.writer().writeAll(",\"serverInfo\":{\"name\":\"zts-api\",\"version\":\"" ++ version_info.value ++ "\"},\"protocol\":\"json-rpc\",\"async\":true}");
                try result.writer().writeAll("}");
                try writeJsonRpcResult(writer, id, result.items);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "ping")) {
            if (root.object.get("id")) |id| {
                try writeJsonRpcResult(writer, id, "\"pong\"");
            }
            continue;
        }

        if (std.mem.eql(u8, method, "echo")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                try writeJsonRpcResultValue(writer, id, params);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "updateSnapshot")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                var state = try parseUpdateSnapshotParams(params);
                errdefer state.deinit();
                const snapshot = try makeSnapshotHandle(next_snapshot_id);
                defer std.heap.page_allocator.free(snapshot);
                next_snapshot_id += 1;
                const owned_snapshot = try std.heap.page_allocator.dupe(u8, snapshot);
                try snapshots.put(owned_snapshot, state);
                if (latest_snapshot) |value| {
                    std.heap.page_allocator.free(value);
                }
                latest_snapshot = try std.heap.page_allocator.dupe(u8, snapshot);

                var result = std.ArrayList(u8).init(std.heap.page_allocator);
                defer result.deinit();
                try result.writer().writeAll("{\"snapshot\":");
                try std.json.encodeJsonString(snapshot, .{}, result.writer());
                try result.writer().writeAll(",\"projects\":");
                try writeSnapshotProjectsJson(result.writer(), cwd, snapshot, snapshots.getPtr(owned_snapshot).?);
                if (latest_snapshot != null and next_snapshot_id > 2) {
                    try result.writer().writeAll(",\"changes\":");
                    try writeSnapshotChangesJson(result.writer(), snapshots.getPtr(owned_snapshot).?);
                }
                try result.writer().writeAll("}");
                try writeJsonRpcResult(writer, id, result.items);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "release")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const handle = extractReleaseHandle(params) catch {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: empty handle");
                    continue;
                };
                if (handle.len == 0) {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: empty handle");
                    continue;
                }
                if (handle[0] != 'n') {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: can only release snapshot handles");
                    continue;
                }
                if (latest_snapshot) |latest| {
                    if (std.mem.eql(u8, latest, handle)) {
                        std.heap.page_allocator.free(latest);
                        latest_snapshot = null;
                    }
                }
                if (snapshots.fetchRemove(handle)) |entry| {
                    std.heap.page_allocator.free(entry.key);
                    var state = entry.value;
                    state.deinit();
                    try writeJsonRpcResult(writer, id, "true");
                } else {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: snapshot not found");
                }
            }
            continue;
        }

        if (std.mem.eql(u8, method, "getDefaultProjectForFile")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractDefaultProjectRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: invalid getDefaultProjectForFile params");
                    continue;
                };
                defer request.deinit();

                const state = snapshots.getPtr(request.snapshot) orelse {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: snapshot not found");
                    continue;
                };
                if (state.open_project) |open_project| {
                    const project_id = try syntheticProjectId(request.snapshot, open_project);
                    defer std.heap.page_allocator.free(project_id);
                    var result = std.ArrayList(u8).init(std.heap.page_allocator);
                    defer result.deinit();
                    try result.writer().writeAll("{\"id\":");
                    try std.json.encodeJsonString(project_id, .{}, result.writer());
                    try writeProjectDescriptorJson(result.writer(), cwd, open_project);
                    try writeJsonRpcResult(writer, id, result.items);
                } else {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: no project found for file");
                }
            }
            continue;
        }

        if (std.mem.eql(u8, method, "parseConfigFile")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractParseConfigFileRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: invalid parseConfigFile params");
                    continue;
                };
                defer request.deinit();

                const config_path = try resolveDocumentPath(cwd, request.file);
                defer std.heap.page_allocator.free(config_path);

                const contents = compile_config.readConfig(std.heap.page_allocator, config_path) catch {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: could not read config file");
                    continue;
                };
                defer std.heap.page_allocator.free(contents);

                var parsed_config = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, contents, .{}) catch {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: invalid config file json");
                    continue;
                };
                defer parsed_config.deinit();

                var compile_request = compile_types.CompileRequest.init(std.heap.page_allocator, .normal);
                defer compile_request.deinit();
                var compile_result = compile_types.CompileResult{
                    .exit_code = 0,
                    .action = .compile,
                    .mode = .normal,
                    .config_resolution = .explicit_project,
                    .forwarded_arg_count = 0,
                    .entry_file_count = 0,
                    .project_path = config_path,
                    .resolved_config_path = config_path,
                    .diagnostic = null,
                };
                var native_plan = compile_plan.buildPlan(std.heap.page_allocator, &compile_request, &compile_result) catch {
                    try writeJsonRpcError(writer, id, -32001, "api: client error: could not build compile plan");
                    continue;
                };
                defer native_plan.deinit(std.heap.page_allocator);

                var result = std.ArrayList(u8).init(std.heap.page_allocator);
                defer result.deinit();
                try result.writer().writeAll("{\"fileNames\":");
                try writePlanFileNamesJson(result.writer(), &native_plan, parsed_config.value);
                try result.writer().writeAll(",\"options\":");
                try writeCompilerOptionsJson(result.writer(), parsed_config.value);
                try result.writer().writeAll(",\"plan\":");
                try writeCompilePlanJson(result.writer(), &native_plan);
                try result.writer().writeAll("}");
                try writeJsonRpcResult(writer, id, result.items);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "shutdown")) {
            saw_shutdown = true;
            if (root.object.get("id")) |id| {
                try writeJsonRpcResult(writer, id, "null");
            }
            continue;
        }

        if (std.mem.eql(u8, method, "exit")) {
            return if (saw_shutdown) 0 else 1;
        }

        if (root.object.get("id")) |id| {
            try writeJsonRpcMethodNotFound(writer, id, method);
        }
    }

    try writer.writeAll("zts: api stdio ended without exit notification\n");
    return if (saw_shutdown) 0 else 1;
}

fn runSyncStdio(reader: anytype, writer: anytype) !u8 {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    var input = std.ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();

    reader.readAllArrayList(&input, std.math.maxInt(usize)) catch |err| {
        if (err == error.EndOfStream) return 0;
        return err;
    };

    if (input.items.len == 0) return 0;

    const data = input.items;
    var offset: usize = 0;

    if (offset >= data.len or data[offset] != 0x93) return 1;
    offset += 1;

    if (offset >= data.len) return 1;
    const msg_type = data[offset];
    offset += 1;

    if (offset >= data.len) return 1;
    const method_len = try parseMsgpackStrLen(data, &offset);
    if (offset + method_len > data.len) return 1;
    const method = data[offset..offset + method_len];
    offset += method_len;

    if (offset >= data.len) return 1;
    var payload: []const u8 = &.{};
    if (offset < data.len) {
        payload = data[offset..];
        offset = data.len;
    }

    const result = if (std.mem.eql(u8, method, "ping"))
        try encodeMsgpackString("pong")
    else if (std.mem.eql(u8, method, "echo"))
        try encodeMsgpackBin(payload)
    else if (std.mem.eql(u8, method, "initialize"))
        try encodeSyncInitializeResult(cwd)
    else if (std.mem.eql(u8, method, "shutdown"))
        try encodeMsgpackNull()
    else
        try encodeMsgpackNull();

    var response = std.ArrayList(u8).init(std.heap.page_allocator);
    defer response.deinit();

    try response.append(0x93);
    try response.append(0);
    try response.appendSlice(result);

    const payload_placeholder = try encodeMsgpackStr("");
    try response.appendSlice(payload_placeholder);

    try writer.writeAll(response.items);
    _ = msg_type;
    return 0;
}

fn parseMsgpackStrLen(data: []const u8, offset: *usize) !usize {
    if (offset.* >= data.len) return error.TruncatedInput;
    const byte = data[offset.*];
    offset.* += 1;

    if (byte >= 0xa0 and byte <= 0xbf) {
        return @as(usize, byte & 0x1f);
    }

    switch (byte) {
        0xd9 => {
            if (offset.* >= data.len) return error.TruncatedInput;
            const len = data[offset.*];
            offset.* += 1;
            return len;
        },
        0xda => {
            if (offset.* + 2 > data.len) return error.TruncatedInput;
            const len = (@as(usize, data[offset.*]) << 8) | @as(usize, data[offset.* + 1]);
            offset.* += 2;
            return len;
        },
        0xdb => {
            if (offset.* + 4 > data.len) return error.TruncatedInput;
            const len = (@as(usize, data[offset.*]) << 24) | (@as(usize, data[offset.* + 1]) << 16) |
                (@as(usize, data[offset.* + 2]) << 8) | @as(usize, data[offset.* + 3]);
            offset.* += 4;
            return len;
        },
        else => return error.InvalidFormat,
    }
}

fn parseMsgpackBinLen(data: []const u8, offset: *usize) !usize {
    if (offset.* >= data.len) return error.TruncatedInput;
    const byte = data[offset.*];
    offset.* += 1;

    if (byte == 0xc4) {
        if (offset.* >= data.len) return error.TruncatedInput;
        const len = data[offset.*];
        offset.* += 1;
        return len;
    }
    if (byte == 0xc5) {
        if (offset.* + 2 > data.len) return error.TruncatedInput;
        const len = (@as(usize, data[offset.*]) << 8) | @as(usize, data[offset.* + 1]);
        offset.* += 2;
        return len;
    }
    if (byte == 0xc6) {
        if (offset.* + 4 > data.len) return error.TruncatedInput;
        const len = (@as(usize, data[offset.*]) << 24) | (@as(usize, data[offset.* + 1]) << 16) |
            (@as(usize, data[offset.* + 2]) << 8) | @as(usize, data[offset.* + 3]);
        offset.* += 4;
        return len;
    }

    return error.InvalidFormat;
}

fn encodeMsgpackString(s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer result.deinit();

    if (s.len < 32) {
        try result.append(@as(u8, 0xa0) + @as(u8, @truncate(s.len)));
    } else if (s.len < 256) {
        try result.append(0xd9);
        try result.append(@as(u8, @truncate(s.len)));
    } else if (s.len < 65536) {
        try result.append(0xda);
        try result.append(@as(u8, @truncate(s.len >> 8)));
        try result.append(@as(u8, @truncate(s.len & 0xff)));
    } else {
        try result.append(0xdb);
        try result.append(@as(u8, @truncate(s.len >> 24)));
        try result.append(@as(u8, @truncate((s.len >> 16) & 0xff)));
        try result.append(@as(u8, @truncate((s.len >> 8) & 0xff)));
        try result.append(@as(u8, @truncate(s.len & 0xff)));
    }
    try result.appendSlice(s);
    return result.toOwnedSlice();
}

fn encodeMsgpackStr(s: []const u8) ![]u8 {
    return encodeMsgpackString(s);
}

fn encodeMsgpackBin(data: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer result.deinit();

    if (data.len < 256) {
        try result.append(0xc4);
        try result.append(@as(u8, @truncate(data.len)));
    } else if (data.len < 65536) {
        try result.append(0xc5);
        try result.append(@as(u8, @truncate(data.len >> 8)));
        try result.append(@as(u8, @truncate(data.len & 0xff)));
    } else {
        try result.append(0xc6);
        try result.append(@as(u8, @truncate(data.len >> 24)));
        try result.append(@as(u8, @truncate((data.len >> 16) & 0xff)));
        try result.append(@as(u8, @truncate((data.len >> 8) & 0xff)));
        try result.append(@as(u8, @truncate(data.len & 0xff)));
    }
    try result.appendSlice(data);
    return result.toOwnedSlice();
}

fn encodeMsgpackNull() ![]u8 {
    return std.heap.page_allocator.dupe(u8, &.{0xc0});
}

fn encodeSyncInitializeResult(cwd: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer result.deinit();

    try result.append(0x93);
    try result.append(0xa0);
    try result.append(@as(u8, 0));

    try result.append(0xd9);
    try result.append(@as(u8, @truncate(cwd.len)));
    try result.appendSlice(cwd);

    const resp = try std.fmt.allocPrint(std.heap.page_allocator,
        \\{{"useCaseSensitiveFileNames":true,"currentDirectory":"{s}","serverInfo":{{"name":"zts-api","version":"{s}"}},"protocol":"json-rpc","async":false}}
    , .{ cwd, version_info.value });
    defer std.heap.page_allocator.free(resp);

    const resp_bin = try encodeMsgpackBin(resp);
    defer std.heap.page_allocator.free(resp_bin);
    try result.appendSlice(resp_bin);

    return result.toOwnedSlice();
}

fn makeSnapshotHandle(id: u64) ![]u8 {
    return try std.fmt.allocPrint(std.heap.page_allocator, "n{X:0>16}", .{id});
}

fn parseUpdateSnapshotParams(params: std.json.Value) !SnapshotState {
    if (params == .null) return .{};
    if (params != .object) return error.InvalidRequest;

    var state = SnapshotState{};

    if (params.object.get("openProject")) |open_project| {
        if (open_project != .string) return error.InvalidRequest;
        state.open_project = try std.heap.page_allocator.dupe(u8, open_project.string);
    }

    if (params.object.get("fileChanges")) |file_changes| {
        if (file_changes != .object) return error.InvalidRequest;
        if (file_changes.object.get("invalidateAll")) |invalidate_all| {
            if (invalidate_all != .bool) return error.InvalidRequest;
            state.invalidate_all = invalidate_all.bool;
        }
        state.changed_count = countJsonArray(file_changes.object.get("changed"));
        state.created_count = countJsonArray(file_changes.object.get("created"));
        state.deleted_count = countJsonArray(file_changes.object.get("deleted"));
    }

    return state;
}

fn countJsonArray(value: ?std.json.Value) usize {
    if (value) |resolved| {
        if (resolved == .array) return resolved.array.items.len;
    }
    return 0;
}

fn writeSnapshotProjectsJson(writer: anytype, cwd: []const u8, snapshot: []const u8, state: *const SnapshotState) !void {
    if (state.open_project) |open_project| {
        const project_id = try syntheticProjectId(snapshot, open_project);
        defer std.heap.page_allocator.free(project_id);
        try writer.writeAll("[{\"id\":");
        try std.json.encodeJsonString(project_id, .{}, writer);
        try writeProjectDescriptorJson(writer, cwd, open_project);
        try writer.writeAll("]");
        return;
    }
    try writer.writeAll("[]");
}

fn writeProjectDescriptorJson(writer: anytype, cwd: []const u8, open_project: []const u8) !void {
    try writer.writeAll(",\"configFileName\":");
    try std.json.encodeJsonString(open_project, .{}, writer);
    if (try writeResolvedProjectDetailsJson(writer, cwd, open_project)) {
        return;
    }
    try writer.writeAll(",\"rootFiles\":[],\"compilerOptions\":null}");
}

fn writeResolvedProjectDetailsJson(writer: anytype, cwd: []const u8, open_project: []const u8) !bool {
    const config_path = resolveDocumentPath(cwd, open_project) catch return false;
    defer std.heap.page_allocator.free(config_path);

    const contents = compile_config.readConfig(std.heap.page_allocator, config_path) catch return false;
    defer std.heap.page_allocator.free(contents);

    var parsed_config = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, contents, .{}) catch return false;
    defer parsed_config.deinit();

    var compile_request = compile_types.CompileRequest.init(std.heap.page_allocator, .normal);
    defer compile_request.deinit();
    const compile_result = compile_types.CompileResult{
        .exit_code = 0,
        .action = .compile,
        .mode = .normal,
        .config_resolution = .explicit_project,
        .forwarded_arg_count = 0,
        .entry_file_count = 0,
        .project_path = config_path,
        .resolved_config_path = config_path,
        .diagnostic = null,
    };
    var native_plan = compile_plan.buildPlan(std.heap.page_allocator, &compile_request, &compile_result) catch return false;
    defer native_plan.deinit(std.heap.page_allocator);

    try writer.writeAll(",\"rootFiles\":");
    try writePlanFileNamesJson(writer, &native_plan, parsed_config.value);
    try writer.writeAll(",\"compilerOptions\":");
    try writeCompilerOptionsJson(writer, parsed_config.value);
    try writer.writeAll("}");
    return true;
}

fn syntheticProjectId(snapshot: []const u8, open_project: []const u8) ![]u8 {
    _ = snapshot;
    return try std.fmt.allocPrint(std.heap.page_allocator, "p.{s}", .{open_project});
}

fn writeSnapshotChangesJson(writer: anytype, state: *const SnapshotState) !void {
    const has_changes = state.invalidate_all or state.changed_count > 0 or state.created_count > 0 or state.deleted_count > 0 or state.open_project != null;
    if (!has_changes) {
        try writer.writeAll("{\"changedProjects\":{},\"removedProjects\":[]}");
        return;
    }

    try writer.writeAll("{\"changedProjects\":{\"api.synthetic\":{");
    try writer.writeAll("\"changedFiles\":[");
    var emitted = false;
    if (state.invalidate_all) {
        try std.json.encodeJsonString("<invalidateAll>", .{}, writer);
        emitted = true;
    }
    var index: usize = 0;
    while (index < state.changed_count) : (index += 1) {
        if (emitted) try writer.writeAll(",");
        try writer.print("\"changed:{d}\"", .{index});
        emitted = true;
    }
    index = 0;
    while (index < state.created_count) : (index += 1) {
        if (emitted) try writer.writeAll(",");
        try writer.print("\"created:{d}\"", .{index});
        emitted = true;
    }
    if (state.open_project) |open_project| {
        if (emitted) try writer.writeAll(",");
        try std.json.encodeJsonString(open_project, .{}, writer);
    }
    try writer.writeAll("],\"deletedFiles\":[");
    index = 0;
    while (index < state.deleted_count) : (index += 1) {
        if (index > 0) try writer.writeAll(",");
        try writer.print("\"deleted:{d}\"", .{index});
    }
    try writer.writeAll("]}},\"removedProjects\":[]}");
}

fn extractReleaseHandle(params: std.json.Value) ![]const u8 {
    if (params != .object) return error.InvalidRequest;
    const handle_value = params.object.get("handle") orelse return error.InvalidRequest;
    if (handle_value != .string) return error.InvalidRequest;
    return handle_value.string;
}

const DefaultProjectRequest = struct {
    snapshot: []u8,
    file: []u8,

    fn deinit(self: *const DefaultProjectRequest) void {
        std.heap.page_allocator.free(self.snapshot);
        std.heap.page_allocator.free(self.file);
    }
};

const ParseConfigFileRequest = struct {
    file: []u8,

    fn deinit(self: *const ParseConfigFileRequest) void {
        std.heap.page_allocator.free(self.file);
    }
};

fn extractDefaultProjectRequest(params: std.json.Value) !DefaultProjectRequest {
    if (params != .object) return error.InvalidRequest;

    const snapshot_value = params.object.get("snapshot") orelse return error.InvalidRequest;
    if (snapshot_value != .string) return error.InvalidRequest;

    const file_value = params.object.get("file") orelse return error.InvalidRequest;
    const file = try extractDocumentIdentifier(file_value);

    return .{
        .snapshot = try std.heap.page_allocator.dupe(u8, snapshot_value.string),
        .file = file,
    };
}

fn extractParseConfigFileRequest(params: std.json.Value) !ParseConfigFileRequest {
    if (params != .object) return error.InvalidRequest;
    const file_value = params.object.get("file") orelse return error.InvalidRequest;
    return .{
        .file = try extractDocumentIdentifier(file_value),
    };
}

fn extractDocumentIdentifier(value: std.json.Value) ![]u8 {
    switch (value) {
        .string => |raw| return try std.heap.page_allocator.dupe(u8, raw),
        .object => |obj| {
            if (obj.get("fileName")) |file_name| {
                if (file_name != .string) return error.InvalidRequest;
                return try std.heap.page_allocator.dupe(u8, file_name.string);
            }
            if (obj.get("uri")) |uri| {
                if (uri != .string) return error.InvalidRequest;
                return try std.heap.page_allocator.dupe(u8, uri.string);
            }
            return error.InvalidRequest;
        },
        else => return error.InvalidRequest,
    }
}

fn resolveDocumentPath(cwd: []const u8, value: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, value, "file://")) {
        return std.heap.page_allocator.dupe(u8, value["file://".len..]);
    }
    if (std.fs.path.isAbsolute(value)) {
        return std.heap.page_allocator.dupe(u8, value);
    }
    return try std.fs.path.join(std.heap.page_allocator, &.{ cwd, value });
}

fn writePlanFileNamesJson(writer: anytype, plan: *const compile_plan.CompilePlan, root: std.json.Value) !void {
    if (plan.discovered_sources.items.len > 0) {
        try writer.writeAll("[");
        for (plan.discovered_sources.items, 0..) |source_path, index| {
            if (index > 0) try writer.writeAll(",");
            try std.json.encodeJsonString(source_path, .{}, writer);
        }
        try writer.writeAll("]");
        return;
    }

    if (root != .object) {
        try writer.writeAll("[]");
        return;
    }
    if (root.object.get("files")) |files_value| {
        if (files_value == .array) {
            try writer.writeAll("[");
            var wrote = false;
            for (files_value.array.items) |item| {
                if (item != .string) continue;
                if (wrote) try writer.writeAll(",");
                try std.json.encodeJsonString(item.string, .{}, writer);
                wrote = true;
            }
            try writer.writeAll("]");
            return;
        }
    }
    try writer.writeAll("[]");
}

fn writeCompilerOptionsJson(writer: anytype, root: std.json.Value) !void {
    if (root != .object) {
        try writer.writeAll("null");
        return;
    }
    if (root.object.get("compilerOptions")) |options_value| {
        try std.json.stringify(options_value, .{}, writer);
        return;
    }
    try writer.writeAll("null");
}

fn writeCompilePlanJson(writer: anytype, plan: *const compile_plan.CompilePlan) !void {
    try writer.writeAll("{\"configPath\":");
    if (plan.config_path) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"configDir\":");
    if (plan.config_dir) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"rootDir\":");
    if (plan.root_dir) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"outDir\":");
    if (plan.out_dir) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"module\":");
    if (plan.module_name) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"target\":");
    if (plan.target_name) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"baseUrl\":");
    if (plan.base_url) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"extends\":");
    if (plan.extends_path) |value| {
        try std.json.encodeJsonString(value, .{}, writer);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"includePatterns\":[");
    for (plan.include_patterns.items, 0..) |pattern, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(pattern, .{}, writer);
    }
    try writer.writeAll("],\"explicitFiles\":[");
    for (plan.explicit_files.items, 0..) |file, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(file, .{}, writer);
    }
    try writer.writeAll("],\"pathMappings\":[");
    for (plan.path_mappings.items, 0..) |mapping, mapping_index| {
        if (mapping_index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"pattern\":");
        try std.json.encodeJsonString(mapping.pattern, .{}, writer);
        try writer.writeAll(",\"targets\":[");
        for (mapping.targets.items, 0..) |target, target_index| {
            if (target_index > 0) try writer.writeAll(",");
            try std.json.encodeJsonString(target, .{}, writer);
        }
        try writer.writeAll("]}");
    }
    try writer.writeAll("],\"discoveredSources\":[");
    for (plan.discovered_sources.items, 0..) |source_path, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(source_path, .{}, writer);
    }
    try writer.writeAll("]}");
}

fn readFrame(allocator: std.mem.Allocator, reader: anytype) !?[]u8 {
    var content_length: ?usize = null;
    var line_buffer = std.ArrayList(u8).init(allocator);
    defer line_buffer.deinit();

    while (true) {
        line_buffer.clearRetainingCapacity();
        reader.streamUntilDelimiter(line_buffer.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => {
                if (content_length == null and line_buffer.items.len == 0) return null;
                return err;
            },
            else => return err,
        };

        const raw_line = std.mem.trimRight(u8, line_buffer.items, "\r\n");
        if (raw_line.len == 0) break;

        if (std.ascii.startsWithIgnoreCase(raw_line, "Content-Length:")) {
            const value = std.mem.trim(u8, raw_line["Content-Length:".len..], " \t");
            content_length = try std.fmt.parseUnsigned(usize, value, 10);
        }
    }

    const length = content_length orelse return null;
    const payload = try allocator.alloc(u8, length);
    errdefer allocator.free(payload);
    try reader.readNoEof(payload);
    return payload;
}

fn writeJsonRpcResult(writer: anytype, id: std.json.Value, result_json: []const u8) !void {
    var body = std.ArrayList(u8).init(std.heap.page_allocator);
    defer body.deinit();

    try body.writer().writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(body.writer(), id);
    try body.writer().writeAll(",\"result\":");
    try body.writer().writeAll(result_json);
    try body.writer().writeAll("}");
    try writeFrame(writer, body.items);
}

fn writeJsonRpcResultValue(writer: anytype, id: std.json.Value, result: std.json.Value) !void {
    var body = std.ArrayList(u8).init(std.heap.page_allocator);
    defer body.deinit();

    try body.writer().writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(body.writer(), id);
    try body.writer().writeAll(",\"result\":");
    try std.json.stringify(result, .{}, body.writer());
    try body.writer().writeAll("}");
    try writeFrame(writer, body.items);
}

fn writeJsonRpcMethodNotFound(writer: anytype, id: std.json.Value, method: []const u8) !void {
    var message = std.ArrayList(u8).init(std.heap.page_allocator);
    defer message.deinit();
    try message.writer().print("Method not found: {s}", .{method});
    try writeJsonRpcError(writer, id, -32601, message.items);
}

fn writeJsonRpcError(writer: anytype, id: std.json.Value, code: i32, message: []const u8) !void {
    var body = std.ArrayList(u8).init(std.heap.page_allocator);
    defer body.deinit();

    try body.writer().writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(body.writer(), id);
    try body.writer().print(",\"error\":{{\"code\":{d},\"message\":", .{code});
    try std.json.encodeJsonString(message, .{}, body.writer());
    try body.writer().writeAll("}}");
    try writeFrame(writer, body.items);
}

fn writeJsonRpcErrorNull(writer: anytype, code: i32, message: []const u8) !void {
    var body = std.ArrayList(u8).init(std.heap.page_allocator);
    defer body.deinit();

    try body.writer().writeAll("{\"jsonrpc\":\"2.0\",\"id\":null");
    try body.writer().print(",\"error\":{{\"code\":{d},\"message\":", .{code});
    try std.json.encodeJsonString(message, .{}, body.writer());
    try body.writer().writeAll("}}");
    try writeFrame(writer, body.items);
}

fn writeFrame(writer: anytype, body: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try writer.writeAll(body);
}

fn writeJsonValue(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |v| try writer.writeAll(if (v) "true" else "false"),
        .integer => |v| try writer.print("{d}", .{v}),
        .float => |v| try writer.print("{d}", .{v}),
        .number_string => |v| try writer.writeAll(v),
        .string => |v| try std.json.encodeJsonString(v, .{}, writer),
        else => try writer.writeAll("null"),
    }
}

test "api sync mode handles empty input" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;

    var input = std.io.fixedBufferStream("");
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expectEqualStrings("", output.items);
}

test "api rejects pipe transport for now" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");
    try parsed.passthrough.append("--pipe");
    try parsed.passthrough.append("demo.sock");

    var input = std.io.fixedBufferStream("");
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expectEqualStrings("pipe transport is not implemented yet\n", output.items);
}

test "api async stdio initialize shutdown exit lifecycle" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"serverInfo\":{\"name\":\"zts-api\",\"version\":\"0.0.0-dev\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"useCaseSensitiveFileNames\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"currentDirectory\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"protocol\":\"json-rpc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"async\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":2,\"result\":null") != null);
}

test "api async stdio supports ping and echo" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const ping = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}";
    const echo = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"echo\",\"params\":{\"value\":1,\"ok\":true}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ ping.len, ping });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ echo.len, echo });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":1,\"result\":\"pong\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":2,\"result\":{\"value\":1,\"ok\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":3,\"result\":null") != null);
}

test "api async stdio supports updateSnapshot and release" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const update = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"updateSnapshot\",\"params\":{}}";
    const release = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"release\",\"params\":{\"handle\":\"n0000000000000001\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ update.len, update });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ release.len, release });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":1,\"result\":{\"snapshot\":\"n0000000000000001\",\"projects\":[]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":2,\"result\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":3,\"result\":null") != null);
}

test "api async stdio updateSnapshot reflects openProject and fileChanges" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("demo/src");
    {
        var config_file = try temp.dir.createFile("demo/tsconfig.json", .{});
        defer config_file.close();
        try config_file.writeAll(
            \\{
            \\  "compilerOptions": {
            \\    "strict": true,
            \\    "rootDir": "src"
            \\  },
            \\  "include": ["src/**/*.ts"]
            \\}
        );
    }
    {
        var source_file = try temp.dir.createFile("demo/src/index.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export const value = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const first = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"updateSnapshot\",\"params\":{}}";
    const second = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"updateSnapshot\",\"params\":{\"openProject\":\"demo/tsconfig.json\",\"fileChanges\":{\"invalidateAll\":true,\"changed\":[\"a.ts\"],\"created\":[\"b.ts\"],\"deleted\":[\"c.ts\"]}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ first.len, first });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ second.len, second });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":2,\"result\":{\"snapshot\":\"n0000000000000002\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"configFileName\":\"demo/tsconfig.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"rootFiles\":[\"demo/src/index.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"compilerOptions\":{\"strict\":true,\"rootDir\":\"src\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"changedProjects\":{\"api.synthetic\":{\"changedFiles\":[\"<invalidateAll>\",\"changed:0\",\"created:0\",\"demo/tsconfig.json\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"deletedFiles\":[\"deleted:0\"]") != null);
}

test "api async stdio supports getDefaultProjectForFile" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("demo/src");
    {
        var config_file = try temp.dir.createFile("demo/tsconfig.json", .{});
        defer config_file.close();
        try config_file.writeAll(
            \\{
            \\  "compilerOptions": {
            \\    "strict": true,
            \\    "rootDir": "src"
            \\  },
            \\  "include": ["src/**/*.ts"]
            \\}
        );
    }
    {
        var source_file = try temp.dir.createFile("demo/src/index.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export const value = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const update = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"updateSnapshot\",\"params\":{\"openProject\":\"demo/tsconfig.json\"}}";
    const get_default = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"getDefaultProjectForFile\",\"params\":{\"snapshot\":\"n0000000000000001\",\"file\":\"demo/src/index.ts\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ update.len, update });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ get_default.len, get_default });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":2,\"result\":{\"id\":\"p.demo/tsconfig.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"configFileName\":\"demo/tsconfig.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"rootFiles\":[\"demo/src/index.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"compilerOptions\":{\"strict\":true,\"rootDir\":\"src\"}") != null);
}

test "api async stdio supports parseConfigFile" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var file = try temp.dir.createFile("tsconfig.json", .{});
        defer file.close();
        try file.writeAll(
            \\{
            \\  "compilerOptions": {
            \\    "strict": true,
            \\    "module": "nodenext",
            \\    "rootDir": "src",
            \\    "outDir": "dist",
            \\    "baseUrl": "."
            \\  },
            \\  "include": ["src/**/*.ts"],
            \\  "files": ["src/index.ts"]
            \\}
        );
    }
    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/index.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export const value = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"parseConfigFile\",\"params\":{\"file\":\"tsconfig.json\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ request.len, request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":1,\"result\":{\"fileNames\":[\"src/index.ts\"],\"options\":{\"strict\":true,\"module\":\"nodenext\",\"rootDir\":\"src\",\"outDir\":\"dist\",\"baseUrl\":\".\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"plan\":{\"configPath\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"rootDir\":\"src\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"outDir\":\"dist\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"baseUrl\":\".\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"includePatterns\":[\"src/**/*.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"explicitFiles\":[\"src/index.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"discoveredSources\":[\"src/index.ts\"]") != null);
}

test "api async stdio parseConfigFile fileNames follow discovered sources" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var config_file = try temp.dir.createFile("tsconfig.json", .{});
        defer config_file.close();
        try config_file.writeAll(
            \\{
            \\  "compilerOptions": {
            \\    "rootDir": "src"
            \\  },
            \\  "include": ["src/**/*.ts"]
            \\}
        );
    }
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export const value = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"parseConfigFile\",\"params\":{\"file\":\"tsconfig.json\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ request.len, request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"fileNames\":[\"src/main.ts\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"explicitFiles\":[]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"discoveredSources\":[\"src/main.ts\"]") != null);
}

test "api async stdio parseConfigFile errors for missing file" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"parseConfigFile\",\"params\":{\"file\":\"missing-tsconfig.json\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ request.len, request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":1,\"error\":{\"code\":-32001,\"message\":\"api: client error: could not read config file\"}") != null);
}

test "api async stdio getDefaultProjectForFile errors for missing snapshot" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getDefaultProjectForFile\",\"params\":{\"snapshot\":\"n0000000000000001\",\"file\":\"demo/src/index.ts\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ request.len, request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":1,\"error\":{\"code\":-32001,\"message\":\"api: client error: snapshot not found\"}") != null);
}

test "api async stdio returns client error for invalid release handle" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const release = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"release\",\"params\":{\"handle\":\"bad-handle\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ release.len, release });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":1,\"error\":{\"code\":-32001,\"message\":\"api: client error: can only release snapshot handles\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":2,\"result\":null") != null);
}

test "api async stdio returns parse error for invalid json frame" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .api;
    try parsed.passthrough.append("--async");

    const invalid = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ invalid.len, invalid });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();

    const exit_code = try run(&parsed, input.reader(), output.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"id\":2,\"result\":null") != null);
}
