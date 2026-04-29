const std = @import("std");
const cli_types = @import("../cli/types.zig");
const version_info = @import("../version.zig");
const parser = @import("./compile/parser.zig");

pub fn run(parsed: *const cli_types.ParsedArgs, reader: anytype, writer: anytype) !u8 {
    if (hasGraphJson(parsed.passthrough.items)) {
        try writeGraphJson(writer, parsed.passthrough.items);
        return 0;
    }

    if (!hasStdio(parsed.passthrough.items)) {
        try writer.writeAll("only stdio is supported\n");
        return 1;
    }

    return try runStdio(reader, writer);
}

fn hasStdio(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--stdio")) return true;
    }
    return false;
}

fn runStdio(reader: anytype, writer: anytype) !u8 {
    var saw_shutdown = false;
    var snapshots = DocumentSnapshotStore{};
    defer snapshots.deinit(std.heap.page_allocator);

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
                try writeJsonRpcResult(writer, id, "{\"capabilities\":{\"textDocumentSync\":1,\"hoverProvider\":true,\"definitionProvider\":true,\"declarationProvider\":true,\"typeDefinitionProvider\":true,\"implementationProvider\":true,\"foldingRangeProvider\":true,\"selectionRangeProvider\":true,\"linkedEditingRangeProvider\":true,\"inlayHintProvider\":true,\"colorProvider\":true,\"documentLinkProvider\":{\"resolveProvider\":false},\"codeLensProvider\":{\"resolveProvider\":false},\"documentFormattingProvider\":true,\"documentRangeFormattingProvider\":true,\"documentOnTypeFormattingProvider\":{\"firstTriggerCharacter\":\"\\n\",\"moreTriggerCharacter\":[]},\"documentSymbolProvider\":true,\"workspaceSymbolProvider\":true,\"completionProvider\":{\"resolveProvider\":true},\"referencesProvider\":true,\"renameProvider\":{\"prepareProvider\":true},\"codeActionProvider\":{\"codeActionKinds\":[\"source.organizeImports\"]},\"signatureHelpProvider\":{\"triggerCharacters\":[\"(\",\",\"]},\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":[\"class\",\"function\",\"interface\",\"type\",\"variable\"],\"tokenModifiers\":[]},\"full\":true}},\"serverInfo\":{\"name\":\"zts\",\"version\":\"" ++ version_info.value ++ "\"}}");
            }
            continue;
        }

        if (std.mem.eql(u8, method, "initialized")) {
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            const params = root.object.get("params") orelse continue;
            handleDidOpen(std.heap.page_allocator, &snapshots, params) catch {};
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const params = root.object.get("params") orelse continue;
            handleDidChange(std.heap.page_allocator, &snapshots, params) catch {};
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/didClose")) {
            const params = root.object.get("params") orelse continue;
            handleDidClose(std.heap.page_allocator, &snapshots, params) catch {};
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/hover")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildHoverResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/definition")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildDefinitionResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/declaration")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildDefinitionResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/typeDefinition")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildTypeDefinitionResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/implementation")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildImplementationResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/foldingRange")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildFoldingRangeResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/selectionRange")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractSelectionRangeRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit(std.heap.page_allocator);

                const result_json = try buildSelectionRangeResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/linkedEditingRange")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildLinkedEditingRangeResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/inlayHint")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractInlayHintRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildInlayHintResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/documentColor")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildDocumentColorResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/colorPresentation")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractColorPresentationRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildColorPresentationResultJson(std.heap.page_allocator, request);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/documentLink")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildDocumentLinkResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/codeLens")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildCodeLensResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildDocumentSymbolResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/references")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildReferencesResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/documentHighlight")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildDocumentHighlightResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/codeAction")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildCodeActionResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/formatting")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildFormattingResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/rangeFormatting")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractRangeFormattingRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildRangeFormattingResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/onTypeFormatting")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractOnTypeFormattingRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildOnTypeFormattingResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/rename")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractRenameRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildRenameResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/prepareRename")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildPrepareRenameResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "workspace/symbol")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const query = extractWorkspaceSymbolQuery(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(query);

                const result_json = try buildWorkspaceSymbolResultJson(std.heap.page_allocator, query);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/completion")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildCompletionResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "completionItem/resolve")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const result_json = buildCompletionResolveResultJson(std.heap.page_allocator, params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const document = extractTextDocumentRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer std.heap.page_allocator.free(document);

                const result_json = try buildSemanticTokensResultJson(std.heap.page_allocator, document, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
            }
            continue;
        }

        if (std.mem.eql(u8, method, "textDocument/signatureHelp")) {
            if (root.object.get("id")) |id| {
                const params = root.object.get("params") orelse std.json.Value{ .null = {} };
                const request = extractTextDocumentPositionRequest(params) catch {
                    try writeJsonRpcError(writer, id, -32600, "Invalid Request");
                    continue;
                };
                defer request.deinit();

                const result_json = try buildSignatureHelpResultJson(std.heap.page_allocator, request, &snapshots);
                defer std.heap.page_allocator.free(result_json);
                try writeJsonRpcResult(writer, id, result_json);
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

    try writer.print(
        "zts: lsp stdio ended without exit notification\n",
        .{},
    );
    return if (saw_shutdown) 0 else 1;
}

fn hasGraphJson(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--graphJson")) return true;
    }
    return false;
}

fn writeGraphJson(writer: anytype, argv: []const []const u8) !void {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);

    try writer.writeAll("{\"status\":\"ok\",\"schemaVersion\":1,\"cwd\":");
    try std.json.encodeJsonString(cwd, .{}, writer);
    try writer.writeAll(",\"exitCode\":0,\"stage\":\"lsp\",\"action\":\"lsp\",\"command\":\"lsp\",\"implemented\":true,\"transport\":{\"stdio\":true},\"lifecycleMethods\":[\"initialize\",\"initialized\",\"shutdown\",\"exit\"],\"requestMethods\":[\"textDocument/hover\",\"textDocument/definition\",\"textDocument/declaration\",\"textDocument/typeDefinition\",\"textDocument/implementation\",\"textDocument/foldingRange\",\"textDocument/selectionRange\",\"textDocument/linkedEditingRange\",\"textDocument/inlayHint\",\"textDocument/documentColor\",\"textDocument/colorPresentation\",\"textDocument/documentLink\",\"textDocument/codeLens\",\"textDocument/documentSymbol\",\"textDocument/references\",\"textDocument/documentHighlight\",\"textDocument/codeAction\",\"textDocument/formatting\",\"textDocument/rangeFormatting\",\"textDocument/onTypeFormatting\",\"textDocument/rename\",\"textDocument/prepareRename\",\"workspace/symbol\",\"textDocument/completion\",\"completionItem/resolve\",\"textDocument/semanticTokens/full\",\"textDocument/signatureHelp\"],\"notificationMethods\":[\"initialized\",\"textDocument/didOpen\",\"textDocument/didChange\",\"textDocument/didClose\",\"exit\"],\"limitations\":[\"language features remain same-file and lexical; there is no project-wide semantic index\",\"declaration currently aliases definition for same-file lexical declarations\",\"typeDefinition only resolves same-file top-level and member type names that can be found lexically\",\"implementation only resolves same-file top-level classes via lexical implements and extends matches\",\"foldingRange only returns top-level brace-delimited declaration blocks\",\"selectionRange only nests lexical identifier, containing line, member range when available, and top-level declaration block ranges\",\"linkedEditingRange, references, rename, documentHighlight, and member codeLens use same-container lexical matches without scope analysis\",\"inlayHint only labels arguments for same-file calls to top-level function declarations\",\"documentColor only recognizes lexical #RRGGBB and #RRGGBBAA literals\",\"colorPresentation only returns hexadecimal presentations for requested RGBA values\",\"documentLink only recognizes lexical http(s) URLs and relative top-level module specifiers\",\"codeAction only supports source.organizeImports for single-line top-level imports\",\"formatting, rangeFormatting, and onTypeFormatting only trim trailing whitespace, normalize line endings, and ensure a trailing newline when formatting reaches file end\",\"onTypeFormatting only reacts to newline triggers\",\"semantic tokens only classify top-level declaration names\",\"signature help only resolves same-file top-level function declarations\",\"workspace symbol scans the working directory without an index and resolves lexical matches with stable ordering, same-file deduplication, and ASCII case-insensitive fallback\",\"completion is lexical and suggests current-file top-level declarations plus same-container members with stable ordering, duplicate-label suppression, and ASCII case-insensitive prefix fallback\",\"textDocument/didChange expects full-document text in contentChanges\",\"stdio is the only supported transport\"],\"passthrough\":[");
    for (argv, 0..) |arg, index| {
        if (index > 0) try writer.writeAll(",");
        try std.json.encodeJsonString(arg, .{}, writer);
    }
    try writer.writeAll("],\"content\":\"zts: lsp stdio lifecycle, text sync, hover, definition, declaration, type definition, implementation, folding range, selection range, linked editing range, inlay hint, document color, color presentation, document link, code lens, documentSymbol, references, document highlight, code action, formatting, range formatting, on-type formatting, rename, prepareRename, workspace symbol, completion, completion resolve, semantic tokens, and signature help are implemented\"}\n");
}

const DocumentSnapshotStore = struct {
    map: std.StringHashMapUnmanaged([]u8) = .{},

    fn deinit(self: *DocumentSnapshotStore, allocator: std.mem.Allocator) void {
        var iterator = self.map.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.map.deinit(allocator);
    }

    fn upsert(self: *DocumentSnapshotStore, allocator: std.mem.Allocator, document: []const u8, text: []const u8) !void {
        const owned_document = try allocator.dupe(u8, document);
        errdefer allocator.free(owned_document);
        const owned_text = try allocator.dupe(u8, text);
        errdefer allocator.free(owned_text);

        const put_result = try self.map.getOrPut(allocator, owned_document);
        if (put_result.found_existing) {
            allocator.free(owned_document);
            allocator.free(put_result.value_ptr.*);
            put_result.value_ptr.* = owned_text;
        } else {
            put_result.value_ptr.* = owned_text;
        }
    }

    fn remove(self: *DocumentSnapshotStore, allocator: std.mem.Allocator, document: []const u8) void {
        const removed = self.map.fetchRemove(document) orelse return;
        allocator.free(removed.key);
        allocator.free(removed.value);
    }

    fn get(self: *const DocumentSnapshotStore, document: []const u8) ?[]const u8 {
        return self.map.get(document);
    }
};

const TextDocumentPositionRequest = struct {
    document: []u8,
    line: usize,
    character: usize,

    fn deinit(self: *const TextDocumentPositionRequest) void {
        std.heap.page_allocator.free(self.document);
    }
};

const RenameRequest = struct {
    document: []u8,
    line: usize,
    character: usize,
    new_name: []u8,

    fn deinit(self: *const RenameRequest) void {
        std.heap.page_allocator.free(self.document);
        std.heap.page_allocator.free(self.new_name);
    }
};

const RangeFormattingRequest = struct {
    document: []u8,
    start_line: usize,
    start_character: usize,
    end_line: usize,
    end_character: usize,

    fn deinit(self: *const RangeFormattingRequest) void {
        std.heap.page_allocator.free(self.document);
    }
};

const InlayHintRequest = struct {
    document: []u8,
    start_line: usize,
    start_character: usize,
    end_line: usize,
    end_character: usize,

    fn deinit(self: *const InlayHintRequest) void {
        std.heap.page_allocator.free(self.document);
    }
};

const ColorPresentationRequest = struct {
    document: []u8,
    range_start_line: usize,
    range_start_character: usize,
    range_end_line: usize,
    range_end_character: usize,
    color: RgbaColor,

    fn deinit(self: *const ColorPresentationRequest) void {
        std.heap.page_allocator.free(self.document);
    }
};

const OnTypeFormattingRequest = struct {
    document: []u8,
    line: usize,
    character: usize,
    trigger: []u8,

    fn deinit(self: *const OnTypeFormattingRequest) void {
        std.heap.page_allocator.free(self.document);
        std.heap.page_allocator.free(self.trigger);
    }
};

const SelectionRangePosition = struct {
    line: usize,
    character: usize,
};

const SelectionRangeRequest = struct {
    document: []u8,
    positions: []SelectionRangePosition,

    fn deinit(self: *const SelectionRangeRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.document);
        allocator.free(self.positions);
    }
};

fn handleDidOpen(allocator: std.mem.Allocator, snapshots: *DocumentSnapshotStore, params: std.json.Value) !void {
    if (params != .object) return error.InvalidRequest;
    const text_document = params.object.get("textDocument") orelse return error.InvalidRequest;
    if (text_document != .object) return error.InvalidRequest;
    const document_value = text_document.object.get("uri") orelse text_document.object.get("fileName") orelse return error.InvalidRequest;
    if (document_value != .string) return error.InvalidRequest;
    const text_value = text_document.object.get("text") orelse return error.InvalidRequest;
    if (text_value != .string) return error.InvalidRequest;

    const document = try resolveDocumentPath(document_value.string);
    defer allocator.free(document);
    try snapshots.upsert(allocator, document, text_value.string);
}

fn handleDidChange(allocator: std.mem.Allocator, snapshots: *DocumentSnapshotStore, params: std.json.Value) !void {
    if (params != .object) return error.InvalidRequest;
    const text_document = params.object.get("textDocument") orelse return error.InvalidRequest;
    if (text_document != .object) return error.InvalidRequest;
    const document_value = text_document.object.get("uri") orelse text_document.object.get("fileName") orelse return error.InvalidRequest;
    if (document_value != .string) return error.InvalidRequest;
    const content_changes_value = params.object.get("contentChanges") orelse return error.InvalidRequest;
    if (content_changes_value != .array or content_changes_value.array.items.len == 0) return error.InvalidRequest;

    const last_change = content_changes_value.array.items[content_changes_value.array.items.len - 1];
    if (last_change != .object) return error.InvalidRequest;
    const text_value = last_change.object.get("text") orelse return error.InvalidRequest;
    if (text_value != .string) return error.InvalidRequest;

    const document = try resolveDocumentPath(document_value.string);
    defer allocator.free(document);
    try snapshots.upsert(allocator, document, text_value.string);
}

fn handleDidClose(allocator: std.mem.Allocator, snapshots: *DocumentSnapshotStore, params: std.json.Value) !void {
    if (params != .object) return error.InvalidRequest;
    const text_document = params.object.get("textDocument") orelse return error.InvalidRequest;
    if (text_document != .object) return error.InvalidRequest;
    const document_value = text_document.object.get("uri") orelse text_document.object.get("fileName") orelse return error.InvalidRequest;
    if (document_value != .string) return error.InvalidRequest;

    const document = try resolveDocumentPath(document_value.string);
    defer allocator.free(document);
    snapshots.remove(allocator, document);
}

fn extractTextDocumentPositionRequest(params: std.json.Value) !TextDocumentPositionRequest {
    if (params != .object) return error.InvalidRequest;
    const text_document = params.object.get("textDocument") orelse return error.InvalidRequest;
    if (text_document != .object) return error.InvalidRequest;
    const document_value = text_document.object.get("uri") orelse text_document.object.get("fileName") orelse return error.InvalidRequest;
    if (document_value != .string) return error.InvalidRequest;

    const position = params.object.get("position") orelse return error.InvalidRequest;
    if (position != .object) return error.InvalidRequest;
    const line_value = position.object.get("line") orelse return error.InvalidRequest;
    const character_value = position.object.get("character") orelse return error.InvalidRequest;
    if (line_value != .integer or character_value != .integer) return error.InvalidRequest;
    if (line_value.integer < 0 or character_value.integer < 0) return error.InvalidRequest;

    return .{
        .document = try resolveDocumentPath(document_value.string),
        .line = @intCast(line_value.integer),
        .character = @intCast(character_value.integer),
    };
}

fn extractRenameRequest(params: std.json.Value) !RenameRequest {
    const request = try extractTextDocumentPositionRequest(params);
    errdefer request.deinit();
    if (params != .object) return error.InvalidRequest;
    const new_name_value = params.object.get("newName") orelse return error.InvalidRequest;
    if (new_name_value != .string) return error.InvalidRequest;

    return .{
        .document = request.document,
        .line = request.line,
        .character = request.character,
        .new_name = try std.heap.page_allocator.dupe(u8, new_name_value.string),
    };
}

fn extractRangeFormattingRequest(params: std.json.Value) !RangeFormattingRequest {
    if (params != .object) return error.InvalidRequest;
    const document = try extractTextDocumentRequest(params);
    errdefer std.heap.page_allocator.free(document);

    const range = params.object.get("range") orelse return error.InvalidRequest;
    if (range != .object) return error.InvalidRequest;
    const start_position = range.object.get("start") orelse return error.InvalidRequest;
    const end_position = range.object.get("end") orelse return error.InvalidRequest;
    if (start_position != .object or end_position != .object) return error.InvalidRequest;

    const start_line = start_position.object.get("line") orelse return error.InvalidRequest;
    const start_character = start_position.object.get("character") orelse return error.InvalidRequest;
    const end_line = end_position.object.get("line") orelse return error.InvalidRequest;
    const end_character = end_position.object.get("character") orelse return error.InvalidRequest;
    if (start_line != .integer or start_character != .integer or end_line != .integer or end_character != .integer) return error.InvalidRequest;
    if (start_line.integer < 0 or start_character.integer < 0 or end_line.integer < 0 or end_character.integer < 0) return error.InvalidRequest;

    return .{
        .document = document,
        .start_line = @intCast(start_line.integer),
        .start_character = @intCast(start_character.integer),
        .end_line = @intCast(end_line.integer),
        .end_character = @intCast(end_character.integer),
    };
}

fn extractOnTypeFormattingRequest(params: std.json.Value) !OnTypeFormattingRequest {
    const request = try extractTextDocumentPositionRequest(params);
    errdefer request.deinit();
    if (params != .object) return error.InvalidRequest;
    const ch_value = params.object.get("ch") orelse return error.InvalidRequest;
    if (ch_value != .string) return error.InvalidRequest;

    return .{
        .document = request.document,
        .line = request.line,
        .character = request.character,
        .trigger = try std.heap.page_allocator.dupe(u8, ch_value.string),
    };
}

fn extractInlayHintRequest(params: std.json.Value) !InlayHintRequest {
    if (params != .object) return error.InvalidRequest;
    const document = try extractTextDocumentRequest(params);
    errdefer std.heap.page_allocator.free(document);

    const range = params.object.get("range") orelse return error.InvalidRequest;
    if (range != .object) return error.InvalidRequest;
    const start_position = range.object.get("start") orelse return error.InvalidRequest;
    const end_position = range.object.get("end") orelse return error.InvalidRequest;
    if (start_position != .object or end_position != .object) return error.InvalidRequest;

    const start_line = start_position.object.get("line") orelse return error.InvalidRequest;
    const start_character = start_position.object.get("character") orelse return error.InvalidRequest;
    const end_line = end_position.object.get("line") orelse return error.InvalidRequest;
    const end_character = end_position.object.get("character") orelse return error.InvalidRequest;
    if (start_line != .integer or start_character != .integer or end_line != .integer or end_character != .integer) return error.InvalidRequest;
    if (start_line.integer < 0 or start_character.integer < 0 or end_line.integer < 0 or end_character.integer < 0) return error.InvalidRequest;

    return .{
        .document = document,
        .start_line = @intCast(start_line.integer),
        .start_character = @intCast(start_character.integer),
        .end_line = @intCast(end_line.integer),
        .end_character = @intCast(end_character.integer),
    };
}

fn extractColorPresentationRequest(params: std.json.Value) !ColorPresentationRequest {
    if (params != .object) return error.InvalidRequest;
    const document = try extractTextDocumentRequest(params);
    errdefer std.heap.page_allocator.free(document);

    const range = params.object.get("range") orelse return error.InvalidRequest;
    const color = params.object.get("color") orelse return error.InvalidRequest;
    if (range != .object or color != .object) return error.InvalidRequest;

    const start_position = range.object.get("start") orelse return error.InvalidRequest;
    const end_position = range.object.get("end") orelse return error.InvalidRequest;
    if (start_position != .object or end_position != .object) return error.InvalidRequest;

    const start_line = start_position.object.get("line") orelse return error.InvalidRequest;
    const start_character = start_position.object.get("character") orelse return error.InvalidRequest;
    const end_line = end_position.object.get("line") orelse return error.InvalidRequest;
    const end_character = end_position.object.get("character") orelse return error.InvalidRequest;
    if (start_line != .integer or start_character != .integer or end_line != .integer or end_character != .integer) return error.InvalidRequest;

    const red = color.object.get("red") orelse return error.InvalidRequest;
    const green = color.object.get("green") orelse return error.InvalidRequest;
    const blue = color.object.get("blue") orelse return error.InvalidRequest;
    const alpha = color.object.get("alpha") orelse return error.InvalidRequest;

    return .{
        .document = document,
        .range_start_line = @intCast(start_line.integer),
        .range_start_character = @intCast(start_character.integer),
        .range_end_line = @intCast(end_line.integer),
        .range_end_character = @intCast(end_character.integer),
        .color = .{
            .red = jsonNumberToF64(red) orelse return error.InvalidRequest,
            .green = jsonNumberToF64(green) orelse return error.InvalidRequest,
            .blue = jsonNumberToF64(blue) orelse return error.InvalidRequest,
            .alpha = jsonNumberToF64(alpha) orelse return error.InvalidRequest,
        },
    };
}

fn extractSelectionRangeRequest(params: std.json.Value) !SelectionRangeRequest {
    if (params != .object) return error.InvalidRequest;
    const document = try extractTextDocumentRequest(params);
    errdefer std.heap.page_allocator.free(document);

    const positions_value = params.object.get("positions") orelse return error.InvalidRequest;
    if (positions_value != .array) return error.InvalidRequest;

    var positions = try std.ArrayList(SelectionRangePosition).initCapacity(std.heap.page_allocator, positions_value.array.items.len);
    defer positions.deinit();

    for (positions_value.array.items) |position| {
        if (position != .object) return error.InvalidRequest;
        const line_value = position.object.get("line") orelse return error.InvalidRequest;
        const character_value = position.object.get("character") orelse return error.InvalidRequest;
        if (line_value != .integer or character_value != .integer) return error.InvalidRequest;
        if (line_value.integer < 0 or character_value.integer < 0) return error.InvalidRequest;

        positions.appendAssumeCapacity(.{
            .line = @intCast(line_value.integer),
            .character = @intCast(character_value.integer),
        });
    }

    return .{
        .document = document,
        .positions = try positions.toOwnedSlice(),
    };
}

fn resolveDocumentPath(value: []const u8) ![]u8 {
    if (std.mem.startsWith(u8, value, "file://")) {
        return std.heap.page_allocator.dupe(u8, value["file://".len..]);
    }
    if (std.fs.path.isAbsolute(value)) {
        return std.heap.page_allocator.dupe(u8, value);
    }

    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buffer);
    return std.fs.path.join(std.heap.page_allocator, &.{ cwd, value });
}

fn extractTextDocumentRequest(params: std.json.Value) ![]u8 {
    if (params != .object) return error.InvalidRequest;
    const text_document = params.object.get("textDocument") orelse return error.InvalidRequest;
    if (text_document != .object) return error.InvalidRequest;
    const document_value = text_document.object.get("uri") orelse text_document.object.get("fileName") orelse return error.InvalidRequest;
    if (document_value != .string) return error.InvalidRequest;
    return resolveDocumentPath(document_value.string);
}

fn extractWorkspaceSymbolQuery(params: std.json.Value) ![]u8 {
    if (params != .object) return error.InvalidRequest;
    const query_value = params.object.get("query") orelse return error.InvalidRequest;
    if (query_value != .string) return error.InvalidRequest;
    return std.heap.page_allocator.dupe(u8, query_value.string);
}

const DocumentContents = union(enum) {
    owned: []u8,
    borrowed: []const u8,

    fn slice(self: DocumentContents) []const u8 {
        return switch (self) {
            .owned => |contents| contents,
            .borrowed => |contents| contents,
        };
    }

    fn deinit(self: DocumentContents, allocator: std.mem.Allocator) void {
        switch (self) {
            .owned => |contents| allocator.free(contents),
            .borrowed => {},
        }
    }
};

fn loadDocumentContents(allocator: std.mem.Allocator, snapshots: *const DocumentSnapshotStore, document: []const u8) !?DocumentContents {
    if (snapshots.get(document)) |contents| {
        return DocumentContents{ .borrowed = contents };
    }

    const document_file = std.fs.cwd().openFile(document, .{}) catch return null;
    defer document_file.close();
    const contents = document_file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return null;
    return DocumentContents{ .owned = contents };
}

fn buildHoverResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "null");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "null");

    for (top_level.declarations.items) |decl| {
        const decl_end = declarationRangeEndOffset(contents, decl);
        if (offset < decl.start.offset or offset > decl_end) continue;

        var response_json = std.ArrayList(u8).init(allocator);
        defer response_json.deinit();

        hover_summary_source_contents = contents;
        defer hover_summary_source_contents = null;
        try response_json.writer().writeAll("{\"contents\":{\"kind\":\"markdown\",\"value\":");
        if (!try writeMemberHoverLabelJson(response_json.writer(), contents, decl, offset)) {
            try writeHoverLabelJson(response_json.writer(), decl);
        }
        try response_json.writer().writeAll("}}");
        return response_json.toOwnedSlice();
    }

    return allocator.dupe(u8, "null");
}

fn writeMemberHoverLabelJson(writer: anytype, contents: []const u8, decl: parser.Declaration, offset: usize) !bool {
    const range = declarationMemberScanRange(contents, decl) orelse return false;
    return writeMemberHoverLabelJsonInRange(writer, contents, range.start_index, range.close_index, range.mode, offset);
}

fn writeMemberHoverLabelJsonInRange(
    writer: anytype,
    contents: []const u8,
    start_index: usize,
    close_index: usize,
    mode: MemberScanMode,
    offset: usize,
) !bool {
    var scan_index = start_index;
    var scan_depth: usize = 0;

    while (scan_index < close_index) {
        const member_name_start = nextMemberNameStart(contents, scan_index, close_index, mode, &scan_depth) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);

        if (try writeMemberHoverSnippetJson(writer, contents, member_name_start, member_entry.range_end, offset)) return true;

        scan_index = member_entry.range_end;
    }

    return false;
}

fn writeMemberHoverSnippetJson(
    writer: anytype,
    contents: []const u8,
    name_start: usize,
    range_end: usize,
    offset: usize,
) !bool {
    if (offset < name_start or offset > range_end) return false;
    try writeHoverRawSnippetJson(writer, contents[name_start..range_end]);
    return true;
}

fn buildDefinitionResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "null");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "null");

    if (resolveMemberSymbolAtOffset(contents, top_level.declarations.items, offset)) |member| {
        return buildLocationResultJson(allocator, request.document, contents, member.declaration_start, member.declaration_end);
    }

    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "null");
    if (topLevelDeclarationByName(top_level.declarations.items, symbol)) |decl| {
        const declaration_name = decl.name orelse unreachable;
        return buildDeclarationLocationResultJson(allocator, request.document, contents, decl, declaration_name);
    }

    return allocator.dupe(u8, "null");
}

fn buildLocationResultJson(
    allocator: std.mem.Allocator,
    document: []const u8,
    contents: []const u8,
    start_offset: usize,
    end_offset: usize,
) ![]u8 {
    const start_position = offsetToLineCharacter(contents, start_offset);
    const end_position = offsetToLineCharacter(contents, end_offset);

    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try writeLocationJson(response_json.writer(), document, start_position, end_position);
    return response_json.toOwnedSlice();
}

fn buildDeclarationLocationResultJson(
    allocator: std.mem.Allocator,
    document: []const u8,
    contents: []const u8,
    decl: parser.Declaration,
    name: []const u8,
) ![]u8 {
    const declaration_start = declarationNameStartOffset(decl, name);
    const declaration_end = decl.end_offset;
    return buildLocationResultJson(allocator, document, contents, declaration_start, declaration_end);
}

fn writeDeclarationLocationJson(
    writer: anytype,
    document: []const u8,
    contents: []const u8,
    decl: parser.Declaration,
    name: []const u8,
) !void {
    const declaration_start = offsetToLineCharacter(contents, declarationNameStartOffset(decl, name));
    const declaration_end = offsetToLineCharacter(contents, decl.end_offset);
    try writeLocationJson(writer, document, declaration_start, declaration_end);
}

fn declarationNameStartOffset(decl: parser.Declaration, name: []const u8) usize {
    return decl.end_offset - name.len;
}

fn declarationNameOffsetRange(decl: parser.Declaration, name: []const u8) OffsetRange {
    return .{ .start = declarationNameStartOffset(decl, name), .end = decl.end_offset };
}

fn declarationNameLineRange(contents: []const u8, decl: parser.Declaration, name: []const u8) struct { start: LineCharacter, end: LineCharacter } {
    const declaration_start = declarationNameStartOffset(decl, name);
    const declaration_end = decl.end_offset;
    return .{
        .start = offsetToLineCharacter(contents, declaration_start),
        .end = offsetToLineCharacter(contents, declaration_end),
    };
}

fn lineStartOffset(contents: []const u8, offset: usize) usize {
    var line_start = offset;
    while (line_start > 0 and contents[line_start - 1] != '\n') : (line_start -= 1) {}
    return line_start;
}

const MemberSymbolMatch = struct {
    name: []const u8,
    declaration_start: usize,
    declaration_end: usize,
    range_end: usize,
    container_start: usize,
    container_end: usize,
};

fn resolveMemberSymbolAtOffset(
    contents: []const u8,
    declarations: []const parser.Declaration,
    offset: usize,
) ?MemberSymbolMatch {
    for (declarations) |decl| {
        if (resolveMemberSymbolInDeclarationAtOffset(contents, decl, offset)) |member| return member;
    }
    return null;
}

fn resolveMemberSymbolInDeclarationAtOffset(
    contents: []const u8,
    decl: parser.Declaration,
    offset: usize,
) ?MemberSymbolMatch {
    const range = declarationMemberScanRange(contents, decl) orelse return null;
    return resolveMemberSymbolAtOffsetInRange(contents, range.start_index, range.close_index, range.mode, offset);
}

fn resolveMemberSymbolAtOffsetInRange(
    contents: []const u8,
    start_index: usize,
    close_index: usize,
    mode: MemberScanMode,
    offset: usize,
) ?MemberSymbolMatch {
    if (!offsetWithinMemberScanRange(offset, start_index, close_index)) return null;
    const active_symbol = identifierAtOffset(contents, offset) orelse return null;

    var scan_index = start_index;
    var scan_depth: usize = 0;
    while (scan_index < close_index) {
        const member_name_start = nextMemberNameStart(contents, scan_index, close_index, mode, &scan_depth) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);

        if (std.mem.eql(u8, member_entry.name(contents), active_symbol) and offset >= member_name_start and offset <= close_index + 1) {
            return .{
                .name = member_entry.name(contents),
                .declaration_start = member_name_start,
                .declaration_end = member_entry.name_end,
                .range_end = member_entry.range_end,
                .container_start = start_index,
                .container_end = close_index,
            };
        }

        scan_index = member_entry.range_end;
    }

    return null;
}

fn resolveMemberTypeSymbolAtOffset(
    contents: []const u8,
    declarations: []const parser.Declaration,
    offset: usize,
) ?[]const u8 {
    for (declarations) |decl| {
        if (resolveMemberTypeSymbolInDeclarationAtOffset(contents, decl, declarations, offset)) |symbol| return symbol;
    }
    return null;
}

fn resolveMemberTypeSymbolInDeclarationAtOffset(
    contents: []const u8,
    decl: parser.Declaration,
    declarations: []const parser.Declaration,
    offset: usize,
) ?[]const u8 {
    const range = declarationMemberScanRange(contents, decl) orelse return null;
    return resolveMemberTypeSymbolAtOffsetInRange(contents, range.start_index, range.close_index, range.mode, declarations, offset);
}

fn resolveMemberTypeSymbolAtOffsetInRange(
    contents: []const u8,
    start_index: usize,
    close_index: usize,
    mode: MemberScanMode,
    declarations: []const parser.Declaration,
    offset: usize,
) ?[]const u8 {
    if (!offsetWithinMemberScanRange(offset, start_index, close_index)) return null;

    var scan_index = start_index;
    var scan_depth: usize = 0;

    while (scan_index < close_index) {
        const member_name_start = nextMemberNameStart(contents, scan_index, close_index, mode, &scan_depth) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);

        if (offset >= member_name_start and offset <= member_entry.range_end) {
            return extractTypeSymbolFromMemberSnippet(contents[member_name_start..member_entry.range_end], offset - member_name_start, declarations);
        }

        scan_index = member_entry.range_end;
    }

    return null;
}

fn extractTypeSymbolFromMemberSnippet(
    snippet: []const u8,
    relative_offset: usize,
    declarations: []const parser.Declaration,
) ?[]const u8 {
    var scan_index: usize = 0;
    while (scan_index < snippet.len) {
        if (!isIdentifierByte(snippet[scan_index])) {
            scan_index += 1;
            continue;
        }
        const ident_start = scan_index;
        while (scan_index < snippet.len and isIdentifierByte(snippet[scan_index])) : (scan_index += 1) {}
        const ident_end = scan_index;
        if (relative_offset < ident_start or relative_offset > ident_end) continue;

        var type_cursor = ident_end;
        while (type_cursor < snippet.len and std.ascii.isWhitespace(snippet[type_cursor])) : (type_cursor += 1) {}
        if (type_cursor < snippet.len and snippet[type_cursor] == ':') {
            type_cursor += 1;
            const type_start = skipTypeExpressionPrefix(snippet, type_cursor);
            if (type_start >= snippet.len) return null;
            const type_end = typeExpressionEndOffsetWithin(snippet, type_start, snippet.len);
            return findResolvableTypeSymbolInExpression(snippet[type_start..type_end], declarations);
        }

        const open_paren = std.mem.indexOfScalar(u8, snippet[ident_end..], '(') orelse return null;
        if (ident_end + open_paren != ident_end) continue;
        const paren_open = ident_end + open_paren;
        const paren_close = findMatchingDelimiter(snippet, paren_open, '(', ')') orelse return null;

        if (relative_offset >= paren_open and relative_offset <= paren_close) {
            var param_index = paren_open + 1;
            while (param_index < paren_close) {
                while (param_index < paren_close and !isIdentifierByte(snippet[param_index])) : (param_index += 1) {}
                if (param_index >= paren_close) break;
                const param_start = param_index;
                while (param_index < paren_close and isIdentifierByte(snippet[param_index])) : (param_index += 1) {}
                const param_end = param_index;
                while (param_index < paren_close and std.ascii.isWhitespace(snippet[param_index])) : (param_index += 1) {}
                if (param_index < paren_close and snippet[param_index] == ':') {
                    if (relative_offset >= param_start and relative_offset <= param_end) {
                        param_index += 1;
                        const type_start = skipTypeExpressionPrefix(snippet, param_index);
                        if (type_start >= paren_close) return null;
                        const type_end = typeExpressionEndOffsetWithin(snippet, type_start, paren_close);
                        return findResolvableTypeSymbolInExpression(snippet[type_start..type_end], declarations);
                    }
                }
                while (param_index < paren_close and snippet[param_index] != ',') : (param_index += 1) {}
                if (param_index < paren_close and snippet[param_index] == ',') param_index += 1;
            }
        }

        var return_cursor = paren_close + 1;
        while (return_cursor < snippet.len and std.ascii.isWhitespace(snippet[return_cursor])) : (return_cursor += 1) {}
        if (return_cursor < snippet.len and snippet[return_cursor] == ':') {
            if (relative_offset >= ident_start and relative_offset <= ident_end) {
                return_cursor += 1;
                const type_start = skipTypeExpressionPrefix(snippet, return_cursor);
                if (type_start >= snippet.len) return null;
                const type_end = typeExpressionEndOffsetWithin(snippet, type_start, snippet.len);
                return findResolvableTypeSymbolInExpression(snippet[type_start..type_end], declarations);
            }
        }

        return null;
    }

    return null;
}

fn skipTypeExpressionPrefix(snippet: []const u8, start: usize) usize {
    var scan_index = start;
    while (scan_index < snippet.len) : (scan_index += 1) {
        const ch = snippet[scan_index];
        if (std.ascii.isWhitespace(ch) or ch == '?' or ch == ':' or ch == '=') continue;
        break;
    }
    return scan_index;
}

fn typeExpressionEndOffsetWithin(snippet: []const u8, start: usize, limit: usize) usize {
    var scan_index = start;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var angle_depth: usize = 0;
    var in_single = false;
    var in_double = false;
    var in_template = false;
    var escaped = false;

    while (scan_index < limit) : (scan_index += 1) {
        const ch = snippet[scan_index];

        if (in_single or in_double or in_template) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if ((in_single and ch == '\'') or (in_double and ch == '"') or (in_template and ch == '`')) {
                in_single = false;
                in_double = false;
                in_template = false;
            }
            continue;
        }

        switch (ch) {
            '\'' => in_single = true,
            '"' => in_double = true,
            '`' => in_template = true,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth == 0) return scan_index;
                paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth == 0 and bracket_depth == 0 and angle_depth == 0 and paren_depth == 0) return scan_index;
                if (brace_depth > 0) brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            '<' => angle_depth += 1,
            '>' => {
                if (angle_depth > 0) angle_depth -= 1;
            },
            ',' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0 and angle_depth == 0) return scan_index;
            },
            ';' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0 and angle_depth == 0) return scan_index;
            },
            '=' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0 and angle_depth == 0) return scan_index;
            },
            '\n', '\r' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0 and angle_depth == 0) return scan_index;
            },
            else => {},
        }
    }

    return limit;
}

fn findResolvableTypeSymbolInExpression(expression: []const u8, declarations: []const parser.Declaration) ?[]const u8 {
    var scan_index: usize = 0;
    while (scan_index < expression.len) {
        if (!isIdentifierByte(expression[scan_index])) {
            scan_index += 1;
            continue;
        }

        const ident_start = scan_index;
        while (scan_index < expression.len and isIdentifierByte(expression[scan_index])) : (scan_index += 1) {}
        const ident = expression[ident_start..scan_index];
        if (isIgnoredTypeIdentifier(ident)) continue;
        if (!declarationsContainTypeSymbol(declarations, ident)) continue;
        return ident;
    }

    return null;
}

fn declarationsContainTypeSymbol(declarations: []const parser.Declaration, symbol: []const u8) bool {
    const type_declaration = topLevelDeclarationByName(declarations, symbol) orelse return false;
    return switch (type_declaration.kind) {
        .class_decl, .interface_decl, .type_decl => true,
        else => false,
    };
}

fn isIgnoredTypeIdentifier(ident: []const u8) bool {
    return std.mem.eql(u8, ident, "string") or
        std.mem.eql(u8, ident, "number") or
        std.mem.eql(u8, ident, "boolean") or
        std.mem.eql(u8, ident, "bigint") or
        std.mem.eql(u8, ident, "symbol") or
        std.mem.eql(u8, ident, "object") or
        std.mem.eql(u8, ident, "any") or
        std.mem.eql(u8, ident, "unknown") or
        std.mem.eql(u8, ident, "never") or
        std.mem.eql(u8, ident, "void") or
        std.mem.eql(u8, ident, "undefined") or
        std.mem.eql(u8, ident, "null") or
        std.mem.eql(u8, ident, "true") or
        std.mem.eql(u8, ident, "false") or
        std.mem.eql(u8, ident, "readonly") or
        std.mem.eql(u8, ident, "keyof") or
        std.mem.eql(u8, ident, "typeof") or
        std.mem.eql(u8, ident, "infer") or
        std.mem.eql(u8, ident, "asserts") or
        std.mem.eql(u8, ident, "is");
}

fn buildTypeDefinitionResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "null");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "null");
    if (resolveMemberTypeSymbolAtOffset(contents, top_level.declarations.items, offset)) |member_type_symbol| {
        if (try buildNamedTypeDefinitionResultJson(allocator, request.document, contents, top_level.declarations.items, member_type_symbol)) |type_definition_result| {
            return type_definition_result;
        }
    }
    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "null");

    if (try buildNamedTypeDefinitionResultJson(allocator, request.document, contents, top_level.declarations.items, symbol)) |type_definition_result| {
        return type_definition_result;
    }

    return allocator.dupe(u8, "null");
}

fn buildNamedTypeDefinitionResultJson(
    allocator: std.mem.Allocator,
    document: []const u8,
    contents: []const u8,
    declarations: []const parser.Declaration,
    symbol: []const u8,
) !?[]u8 {
    const type_declaration = topLevelDeclarationByName(declarations, symbol) orelse return null;
    return switch (type_declaration.kind) {
        .class_decl, .interface_decl, .type_decl => try buildDeclarationLocationResultJson(allocator, document, contents, type_declaration, symbol),
        else => null,
    };
}

fn buildImplementationResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "[]");
    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "[]");

    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try response_json.writer().writeAll("[");

    var wrote = false;
    for (top_level.declarations.items) |decl| {
        if (decl.kind != .class_decl) continue;
        const class_name = decl.name orelse continue;
        const line_start = lineStartOffset(contents, decl.start.offset);
        const line_end = lineEndOffset(contents, decl.start.offset);
        const declaration_line = contents[line_start..line_end];
        var matches_target = false;
        if (std.mem.indexOf(u8, declaration_line, "implements")) |index| {
            const implements_clause = declaration_line[index + "implements".len ..];
            matches_target = std.mem.indexOf(u8, implements_clause, symbol) != null;
        }
        if (!matches_target) {
            if (std.mem.indexOf(u8, declaration_line, "extends")) |index| {
                const extends_clause = declaration_line[index + "extends".len ..];
                matches_target = std.mem.indexOf(u8, extends_clause, symbol) != null;
            }
        }
        if (!matches_target) continue;

        if (wrote) try response_json.writer().writeAll(",");
        try writeDeclarationLocationJson(response_json.writer(), request.document, contents, decl, class_name);
        wrote = true;
    }

    try response_json.writer().writeAll("]");
    return response_json.toOwnedSlice();
}

fn buildDocumentSymbolResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var candidates = std.ArrayList(DocumentSymbolCandidate).init(allocator);
    defer candidates.deinit();
    for (top_level.declarations.items, 0..) |decl, index| {
        const declaration_name = decl.name orelse continue;
        try appendOrReplaceDocumentSymbolCandidate(&candidates, .{
            .decl_index = index,
            .name = declaration_name,
            .preference_rank = declarationPreferenceRank(decl.kind),
            .start_offset = decl.start.offset,
        });
    }

    std.mem.sort(DocumentSymbolCandidate, candidates.items, {}, lessThanDocumentSymbolCandidate);

    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try response_json.writer().writeAll("[");

    var wrote = false;
    for (candidates.items) |candidate| {
        const declaration = top_level.declarations.items[candidate.decl_index];
        const declaration_name = declaration.name orelse continue;
        const kind = declarationSymbolKind(declaration.kind);
        const range_end_offset = declarationRangeEndOffset(contents, declaration);
        const selection_start = offsetToLineCharacter(contents, declarationNameStartOffset(declaration, declaration_name));
        const selection_end = offsetToLineCharacter(contents, declaration.end_offset);
        const range_start = offsetToLineCharacter(contents, declaration.start.offset);
        const range_end = offsetToLineCharacter(contents, range_end_offset);

        if (wrote) try response_json.writer().writeAll(",");
        try response_json.writer().writeAll("{\"name\":");
        try std.json.encodeJsonString(declaration_name, .{}, response_json.writer());
        try response_json.writer().print(",\"kind\":{d},\"range\":{{\"start\":{{", .{kind});
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ range_start.line, range_start.character });
        try response_json.writer().writeAll("},\"end\":{");
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ range_end.line, range_end.character });
        try response_json.writer().writeAll("}},\"selectionRange\":{\"start\":{");
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ selection_start.line, selection_start.character });
        try response_json.writer().writeAll("},\"end\":{");
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ selection_end.line, selection_end.character });
        try response_json.writer().writeAll("}},\"children\":");
        try writeDocumentSymbolChildrenJson(allocator, response_json.writer(), contents, declaration);
        try response_json.writer().writeAll("}");
        wrote = true;
    }

    try response_json.writer().writeAll("]");
    return response_json.toOwnedSlice();
}

const DocumentSymbolCandidate = struct {
    decl_index: usize,
    name: []const u8,
    preference_rank: u8,
    start_offset: usize,
};

fn lessThanDocumentSymbolCandidate(_: void, a: DocumentSymbolCandidate, b: DocumentSymbolCandidate) bool {
    if (a.start_offset != b.start_offset) return a.start_offset < b.start_offset;
    return a.decl_index < b.decl_index;
}

fn appendOrReplaceDocumentSymbolCandidate(
    candidates: *std.ArrayList(DocumentSymbolCandidate),
    next: DocumentSymbolCandidate,
) !void {
    for (candidates.items, 0..) |candidate, index| {
        if (!std.mem.eql(u8, candidate.name, next.name)) continue;
        if (next.preference_rank < candidate.preference_rank or
            (next.preference_rank == candidate.preference_rank and next.start_offset < candidate.start_offset))
        {
            candidates.items[index] = next;
        }
        return;
    }
    try candidates.append(next);
}

fn writeDocumentSymbolChildrenJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    contents: []const u8,
    decl: parser.Declaration,
) !void {
    switch (decl.kind) {
        .function_decl => try writeFunctionDocumentSymbolChildrenJson(allocator, writer, contents, decl),
        .class_decl => try writeClassDocumentSymbolChildrenJson(writer, contents, decl),
        .interface_decl, .type_decl => {
            const open_index = memberContainerOpenIndex(contents, decl) orelse {
                try writer.writeAll("[]");
                return;
            };
            try writeObjectTypeMembersJson(writer, contents, open_index);
        },
        else => try writer.writeAll("[]"),
    }
}

fn writeFunctionDocumentSymbolChildrenJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    contents: []const u8,
    decl: parser.Declaration,
) !void {
    var function_params = try extractFunctionParameters(allocator, contents, decl);
    defer {
        for (function_params.items) |param| allocator.free(param);
        function_params.deinit();
    }

    if (function_params.items.len == 0) {
        try writer.writeAll("[]");
        return;
    }

    var search_start = decl.end_offset;
    while (search_start < contents.len and std.ascii.isWhitespace(contents[search_start])) : (search_start += 1) {}
    if (search_start >= contents.len or contents[search_start] != '(') {
        try writer.writeAll("[]");
        return;
    }

    const open_index = search_start;
    const close_index = findMatchingDelimiter(contents, open_index, '(', ')') orelse {
        try writer.writeAll("[]");
        return;
    };

    try writer.writeAll("[");
    var wrote = false;
    var param_search_start = open_index + 1;

    for (function_params.items) |param| {
        const param_name = parameterLabelName(param);
        if (param_name.len == 0) continue;

        const param_index = std.mem.indexOfPos(u8, contents, param_search_start, param_name) orelse continue;
        if (param_index >= close_index) continue;
        param_search_start = param_index + param_name.len;

        const parameter_start = offsetToLineCharacter(contents, param_index);
        const parameter_end = offsetToLineCharacter(contents, param_index + param_name.len);

        try writeParameterDocumentSymbolJson(writer, param_name, parameter_start, parameter_end, &wrote);
    }

    try writer.writeAll("]");
}

fn writeClassDocumentSymbolChildrenJson(writer: anytype, contents: []const u8, decl: parser.Declaration) !void {
    const bounds = memberContainerBounds(contents, decl) orelse {
        try writer.writeAll("[]");
        return;
    };
    const open_index = bounds.open;
    const close_index = bounds.close;

    try writer.writeAll("[");
    var wrote = false;
    var scan_index = open_index + 1;

    while (scan_index < close_index) {
        const member_name_start = nextClassMemberNameStart(contents, scan_index, close_index) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);
        scan_index = member_entry.name_end;
        const member_name = member_entry.name(contents);
        if (memberNameAlreadySeen(contents, open_index + 1, member_name_start, member_name)) {
            while (scan_index < close_index and contents[scan_index] != '\n') : (scan_index += 1) {}
            continue;
        }

        try writeScannedMemberDocumentSymbolJson(writer, contents, member_name, member_name_start, member_entry, close_index, lineEndOffset(contents, member_name_start), &wrote);

        while (scan_index < close_index and contents[scan_index] != '\n') : (scan_index += 1) {}
    }

    try writer.writeAll("]");
}

fn writeClassMethodParameterChildrenJson(
    writer: anytype,
    contents: []const u8,
    open_index: usize,
    class_close_index: usize,
) !void {
    if (open_index >= class_close_index or contents[open_index] != '(') {
        try writer.writeAll("[]");
        return;
    }

    const close_index = findMatchingDelimiter(contents, open_index, '(', ')') orelse {
        try writer.writeAll("[]");
        return;
    };
    if (close_index > class_close_index) {
        try writer.writeAll("[]");
        return;
    }

    try writer.writeAll("[");
    var wrote = false;
    var scan_index = open_index + 1;

    while (scan_index < close_index) {
        while (scan_index < close_index and !isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        if (scan_index >= close_index) break;

        const parameter_name_start = scan_index;
        while (scan_index < close_index and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const parameter_name_end = scan_index;

        var type_separator_index = scan_index;
        while (type_separator_index < close_index and std.ascii.isWhitespace(contents[type_separator_index])) : (type_separator_index += 1) {}
        if (type_separator_index >= close_index or (contents[type_separator_index] != ':' and contents[type_separator_index] != ',' and contents[type_separator_index] != ')')) {
            continue;
        }

        const parameter_start = offsetToLineCharacter(contents, parameter_name_start);
        const parameter_end = offsetToLineCharacter(contents, parameter_name_end);

        try writeParameterDocumentSymbolJson(writer, contents[parameter_name_start..parameter_name_end], parameter_start, parameter_end, &wrote);
    }

    try writer.writeAll("]");
}

fn writeParameterDocumentSymbolJson(
    writer: anytype,
    name: []const u8,
    start: LineCharacter,
    end: LineCharacter,
    wrote: *bool,
) !void {
    if (wrote.*) try writer.writeAll(",");
    try writer.writeAll("{\"name\":");
    try std.json.encodeJsonString(name, .{}, writer);
    try writer.writeAll(",\"kind\":13,\"range\":{\"start\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ start.line, start.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ end.line, end.character });
    try writer.writeAll("}},\"selectionRange\":{\"start\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ start.line, start.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ end.line, end.character });
    try writer.writeAll("}},\"children\":[]}");
    wrote.* = true;
}

fn writeObjectTypeMembersJson(writer: anytype, contents: []const u8, open_index: usize) !void {
    const close_index = memberContainerCloseIndex(contents, open_index) orelse {
        try writer.writeAll("[]");
        return;
    };

    try writer.writeAll("[");
    var wrote = false;
    var scan_index = open_index + 1;
    var scan_depth: usize = 0;

    while (scan_index < close_index) {
        const member_name_start = nextObjectTypeMemberNameStart(contents, scan_index, close_index, &scan_depth) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);
        scan_index = member_entry.name_end;
        const member_name = member_entry.name(contents);
        if (memberNameAlreadySeen(contents, open_index + 1, member_name_start, member_name)) {
            scan_index = objectMemberRangeEndOffset(contents, scan_index, close_index);
            continue;
        }

        try writeScannedMemberDocumentSymbolJson(writer, contents, member_name, member_name_start, member_entry, close_index, member_entry.range_end, &wrote);

        scan_index = member_entry.range_end;
    }

    try writer.writeAll("]");
}

fn writeScannedMemberDocumentSymbolJson(
    writer: anytype,
    contents: []const u8,
    name: []const u8,
    name_start: usize,
    entry: MemberScanEntry,
    close_index: usize,
    range_end_offset: usize,
    wrote: *bool,
) !void {
    try writeMemberDocumentSymbolJson(
        writer,
        contents,
        name,
        memberSymbolKind(memberCategory(contents, entry.after_name, close_index)),
        name_start,
        entry.name_end,
        range_end_offset,
        entry.after_name,
        close_index,
        wrote,
    );
}

fn writeMemberDocumentSymbolJson(
    writer: anytype,
    contents: []const u8,
    name: []const u8,
    kind: usize,
    name_start: usize,
    name_end: usize,
    range_end_offset: usize,
    after_name: usize,
    close_index: usize,
    wrote: *bool,
) !void {
    const name_start_position = offsetToLineCharacter(contents, name_start);
    const name_end_position = offsetToLineCharacter(contents, name_end);
    const range_end = offsetToLineCharacter(contents, range_end_offset);

    if (wrote.*) try writer.writeAll(",");
    try writer.writeAll("{\"name\":");
    try std.json.encodeJsonString(name, .{}, writer);
    try writer.print(",\"kind\":{d},\"range\":{{\"start\":{{", .{kind});
    try writer.print("\"line\":{d},\"character\":{d}", .{ name_start_position.line, name_start_position.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ range_end.line, range_end.character });
    try writer.writeAll("}},\"selectionRange\":{\"start\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ name_start_position.line, name_start_position.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ name_end_position.line, name_end_position.character });
    try writer.writeAll("}},\"children\":");
    if (kind == memberSymbolKind(.method)) {
        try writeClassMethodParameterChildrenJson(writer, contents, after_name, close_index);
    } else {
        try writer.writeAll("[]");
    }
    try writer.writeAll("}");
    wrote.* = true;
}

fn memberContainerOpenIndex(contents: []const u8, decl: parser.Declaration) ?usize {
    return switch (decl.kind) {
        .class_decl, .interface_decl => std.mem.indexOfPos(u8, contents, decl.start.offset, "{"),
        .type_decl => blk: {
            var search_start = decl.end_offset;
            while (search_start < contents.len and contents[search_start] != '=') : (search_start += 1) {}
            if (search_start >= contents.len) break :blk null;
            while (search_start < contents.len and contents[search_start] != '{' and contents[search_start] != ';' and contents[search_start] != '\n') : (search_start += 1) {}
            if (search_start >= contents.len or contents[search_start] != '{') break :blk null;
            break :blk search_start;
        },
        else => null,
    };
}

fn memberContainerBounds(contents: []const u8, decl: parser.Declaration) ?struct { open: usize, close: usize } {
    const open_index = memberContainerOpenIndex(contents, decl) orelse return null;
    const close_index = memberContainerCloseIndex(contents, open_index) orelse return null;
    return .{ .open = open_index, .close = close_index };
}

fn memberContainerCloseIndex(contents: []const u8, open_index: usize) ?usize {
    return findMatchingDelimiter(contents, open_index, '{', '}');
}

const DeclarationMemberScanRange = struct {
    start_index: usize,
    close_index: usize,
    mode: MemberScanMode,
};

fn declarationMemberScanRange(contents: []const u8, decl: parser.Declaration) ?DeclarationMemberScanRange {
    return switch (decl.kind) {
        .class_decl => blk: {
            const bounds = memberContainerBounds(contents, decl) orelse break :blk null;
            break :blk .{
                .start_index = bounds.open + 1,
                .close_index = bounds.close,
                .mode = .class_members,
            };
        },
        .interface_decl, .type_decl => blk: {
            const open_index = memberContainerOpenIndex(contents, decl) orelse break :blk null;
            const close_index = memberContainerCloseIndex(contents, open_index) orelse break :blk null;
            break :blk .{
                .start_index = open_index + 1,
                .close_index = close_index,
                .mode = .object_type_members,
            };
        },
        else => null,
    };
}

const MemberCategory = enum {
    method,
    property,
};

const MemberScanMode = enum {
    class_members,
    object_type_members,
};

const MemberScanEntry = struct {
    name_start: usize,
    name_end: usize,
    after_name: usize,
    range_end: usize,

    fn name(self: MemberScanEntry, contents: []const u8) []const u8 {
        return contents[self.name_start..self.name_end];
    }
};

fn memberCategory(contents: []const u8, after_name: usize, close_index: usize) MemberCategory {
    return if (after_name < close_index and contents[after_name] == '(') .method else .property;
}

fn scanMemberEntry(contents: []const u8, name_start: usize, close_index: usize) MemberScanEntry {
    var name_end_offset = name_start;
    while (name_end_offset < close_index and isIdentifierByte(contents[name_end_offset])) : (name_end_offset += 1) {}
    const after_name = skipInlineWhitespace(contents, name_end_offset, close_index);
    return .{
        .name_start = name_start,
        .name_end = name_end_offset,
        .after_name = after_name,
        .range_end = objectMemberRangeEndOffset(contents, after_name, close_index),
    };
}

fn nextMemberNameStart(
    contents: []const u8,
    from: usize,
    close_index: usize,
    mode: MemberScanMode,
    depth: *usize,
) ?usize {
    return switch (mode) {
        .class_members => nextClassMemberNameStart(contents, from, close_index),
        .object_type_members => nextObjectTypeMemberNameStart(contents, from, close_index, depth),
    };
}

fn nextClassMemberNameStart(contents: []const u8, from: usize, close_index: usize) ?usize {
    var scan_index = from;
    while (scan_index < close_index) {
        while (scan_index < close_index and (contents[scan_index] == '\n' or contents[scan_index] == '\r')) : (scan_index += 1) {}
        while (scan_index < close_index and std.ascii.isWhitespace(contents[scan_index]) and contents[scan_index] != '\n' and contents[scan_index] != '\r') : (scan_index += 1) {}
        if (scan_index >= close_index) return null;
        if (isIdentifierByte(contents[scan_index])) return scan_index;
        while (scan_index < close_index and contents[scan_index] != '\n') : (scan_index += 1) {}
    }
    return null;
}

fn nextObjectTypeMemberNameStart(contents: []const u8, from: usize, close_index: usize, depth: *usize) ?usize {
    var scan_index = from;
    while (scan_index < close_index) {
        const ch = contents[scan_index];
        if (ch == '{') {
            depth.* += 1;
            scan_index += 1;
            continue;
        }
        if (ch == '}') {
            if (depth.* > 0) depth.* -= 1;
            scan_index += 1;
            continue;
        }
        if (depth.* > 0 or ch == '\n' or ch == '\r' or std.ascii.isWhitespace(ch)) {
            scan_index += 1;
            continue;
        }
        if (isIdentifierByte(ch)) return scan_index;
        while (scan_index < close_index and contents[scan_index] != '\n' and contents[scan_index] != ';') : (scan_index += 1) {}
    }
    return null;
}

fn skipInlineWhitespace(contents: []const u8, from: usize, end_index: usize) usize {
    var scan_index = from;
    while (scan_index < end_index and std.ascii.isWhitespace(contents[scan_index]) and contents[scan_index] != '\n' and contents[scan_index] != '\r') : (scan_index += 1) {}
    return scan_index;
}

fn objectMemberRangeEndOffset(contents: []const u8, from: usize, close_index: usize) usize {
    var scan_index = from;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;

    while (scan_index < close_index) : (scan_index += 1) {
        const ch = contents[scan_index];
        switch (ch) {
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth == 0) return scan_index;
                brace_depth -= 1;
            },
            ';' => {
                if (paren_depth == 0 and brace_depth == 0) return scan_index + 1;
            },
            '\n' => {
                if (paren_depth == 0 and brace_depth == 0) return scan_index;
            },
            else => {},
        }
    }

    return close_index;
}

fn declarationRangeEndOffset(contents: []const u8, decl: parser.Declaration) usize {
    const line_end = lineEndOffset(contents, decl.start.offset);
    const open_brace = std.mem.indexOfPos(u8, contents, decl.start.offset, "{") orelse return line_end;
    const close_brace = memberContainerCloseIndex(contents, open_brace) orelse return line_end;
    return close_brace + 1;
}

fn buildReferencesResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "[]");
    if (resolveMemberSymbolAtOffset(contents, top_level.declarations.items, offset)) |member| {
        return buildMemberReferencesResultJson(allocator, request.document, contents, member);
    }
    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "[]");

    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try response_json.writer().writeAll("[");

    var wrote = false;
    var scan_index: usize = 0;
    while (scan_index < contents.len) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }

        const start_index = scan_index;
        while (scan_index < contents.len and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, symbol)) continue;

        const match_start = offsetToLineCharacter(contents, start_index);
        const match_end = offsetToLineCharacter(contents, scan_index);
        if (wrote) try response_json.writer().writeAll(",");
        try writeLocationJson(response_json.writer(), request.document, match_start, match_end);
        wrote = true;
    }

    try response_json.writer().writeAll("]");
    return response_json.toOwnedSlice();
}

fn buildMemberReferencesResultJson(
    allocator: std.mem.Allocator,
    document: []const u8,
    contents: []const u8,
    member: MemberSymbolMatch,
) ![]u8 {
    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try response_json.writer().writeAll("[");

    var wrote = false;
    var scan_index = member.container_start;
    while (scan_index < member.container_end) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }
        const start_index = scan_index;
        while (scan_index < member.container_end and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, member.name)) continue;

        const match_start = offsetToLineCharacter(contents, start_index);
        const match_end = offsetToLineCharacter(contents, scan_index);
        if (wrote) try response_json.writer().writeAll(",");
        try writeLocationJson(response_json.writer(), document, match_start, match_end);
        wrote = true;
    }

    try response_json.writer().writeAll("]");
    return response_json.toOwnedSlice();
}

fn buildDocumentHighlightResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "[]");
    if (resolveMemberSymbolAtOffset(contents, top_level.declarations.items, offset)) |member| {
        return buildMemberDocumentHighlightResultJson(allocator, contents, member);
    }
    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "[]");

    const declaration_start_index = if (topLevelDeclarationByName(top_level.declarations.items, symbol)) |decl|
        declarationNameStartOffset(decl, symbol)
    else
        null;

    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try response_json.writer().writeAll("[");

    var wrote = false;
    var scan_index: usize = 0;
    while (scan_index < contents.len) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }

        const start_index = scan_index;
        while (scan_index < contents.len and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, symbol)) continue;

        const match_start = offsetToLineCharacter(contents, start_index);
        const match_end = offsetToLineCharacter(contents, scan_index);
        const kind: usize = if (declaration_start_index != null and start_index == declaration_start_index.?) 1 else 2;

        if (wrote) try response_json.writer().writeAll(",");
        try response_json.writer().writeAll("{\"range\":{\"start\":{");
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ match_start.line, match_start.character });
        try response_json.writer().writeAll("},\"end\":{");
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ match_end.line, match_end.character });
        try response_json.writer().writeAll("}},\"kind\":");
        try response_json.writer().print("{d}", .{kind});
        try response_json.writer().writeAll("}");
        wrote = true;
    }

    try response_json.writer().writeAll("]");
    return response_json.toOwnedSlice();
}

fn buildMemberDocumentHighlightResultJson(
    allocator: std.mem.Allocator,
    contents: []const u8,
    member: MemberSymbolMatch,
) ![]u8 {
    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try response_json.writer().writeAll("[");

    var wrote = false;
    var scan_index = member.container_start;
    while (scan_index < member.container_end) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }

        const start_index = scan_index;
        while (scan_index < member.container_end and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, member.name)) continue;

        const match_start = offsetToLineCharacter(contents, start_index);
        const match_end = offsetToLineCharacter(contents, scan_index);
        const kind: usize = if (start_index == member.declaration_start) 1 else 2;

        if (wrote) try response_json.writer().writeAll(",");
        try response_json.writer().writeAll("{\"range\":{\"start\":{");
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ match_start.line, match_start.character });
        try response_json.writer().writeAll("},\"end\":{");
        try response_json.writer().print("\"line\":{d},\"character\":{d}", .{ match_end.line, match_end.character });
        try response_json.writer().writeAll("}},\"kind\":");
        try response_json.writer().print("{d}", .{kind});
        try response_json.writer().writeAll("}");
        wrote = true;
    }

    try response_json.writer().writeAll("]");
    return response_json.toOwnedSlice();
}

fn buildCodeActionResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var import_entries = std.ArrayList(ImportEntry).init(allocator);
    defer {
        for (import_entries.items) |entry| allocator.free(entry.text);
        import_entries.deinit();
    }

    var import_block_end: usize = 0;
    for (top_level.declarations.items) |decl| {
        if (decl.kind != .import_stmt) continue;
        const line_start = lineStartOffset(contents, decl.start.offset);
        const line_end = lineEndOffset(contents, decl.start.offset);
        const import_line = contents[line_start..line_end];
        const trimmed = std.mem.trim(u8, import_line, " \t\r\n");
        if (trimmed.len == 0) continue;

        try import_entries.append(.{
            .module_specifier = decl.module_specifier orelse "",
            .text = try allocator.dupe(u8, trimmed),
        });

        if (line_end > import_block_end) import_block_end = line_end;
    }

    if (import_entries.items.len == 0) return allocator.dupe(u8, "[]");

    std.mem.sort(ImportEntry, import_entries.items, {}, lessThanImportEntry);

    var new_text_builder = std.ArrayList(u8).init(allocator);
    defer new_text_builder.deinit();
    for (import_entries.items, 0..) |entry, index| {
        if (index > 0) try new_text_builder.writer().writeByte('\n');
        try new_text_builder.writer().writeAll(entry.text);
    }
    try new_text_builder.writer().writeByte('\n');

    const import_block_end_position = offsetToLineCharacter(contents, import_block_end);

    var code_action_json = std.ArrayList(u8).init(allocator);
    defer code_action_json.deinit();
    try code_action_json.writer().writeAll("[{\"title\":\"Organize Imports\",\"kind\":\"source.organizeImports\",\"edit\":{\"changes\":{");
    try std.json.encodeJsonString(document, .{}, code_action_json.writer());
    try code_action_json.writer().writeAll(":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{");
    try code_action_json.writer().print("\"line\":{d},\"character\":{d}", .{ import_block_end_position.line, import_block_end_position.character });
    try code_action_json.writer().writeAll("}},\"newText\":");
    try std.json.encodeJsonString(new_text_builder.items, .{}, code_action_json.writer());
    try code_action_json.writer().writeAll("}]}}}]");
    return code_action_json.toOwnedSlice();
}

fn buildFoldingRangeResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var response_json = std.ArrayList(u8).init(allocator);
    defer response_json.deinit();
    try response_json.writer().writeAll("[");

    var wrote = false;
    for (top_level.declarations.items) |decl| {
        const open_brace = std.mem.indexOfPos(u8, contents, decl.start.offset, "{") orelse continue;
        const close_brace = memberContainerCloseIndex(contents, open_brace) orelse continue;
        const start_position = offsetToLineCharacter(contents, open_brace);
        const end_position = offsetToLineCharacter(contents, close_brace);
        if (end_position.line <= start_position.line) continue;

        if (wrote) try response_json.writer().writeAll(",");
        try response_json.writer().writeAll("{\"startLine\":");
        try response_json.writer().print("{d}", .{start_position.line});
        try response_json.writer().writeAll(",\"endLine\":");
        try response_json.writer().print("{d}", .{end_position.line});
        try response_json.writer().writeAll(",\"kind\":\"region\"}");
        wrote = true;
    }

    try response_json.writer().writeAll("]");
    return response_json.toOwnedSlice();
}

fn buildSelectionRangeResultJson(allocator: std.mem.Allocator, request: SelectionRangeRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var selection_ranges_json = std.ArrayList(u8).init(allocator);
    defer selection_ranges_json.deinit();
    try selection_ranges_json.writer().writeAll("[");

    for (request.positions, 0..) |position, index| {
        if (index > 0) try selection_ranges_json.writer().writeAll(",");
        try writeSelectionRangeForPositionJson(selection_ranges_json.writer(), contents, top_level.declarations.items, position);
    }

    try selection_ranges_json.writer().writeAll("]");
    return selection_ranges_json.toOwnedSlice();
}

fn buildLinkedEditingRangeResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "null");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "null");
    if (resolveMemberSymbolAtOffset(contents, top_level.declarations.items, offset)) |member| {
        return buildMemberLinkedEditingRangeResultJson(allocator, contents, member);
    }
    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "null");

    if (topLevelDeclarationByName(top_level.declarations.items, symbol) == null) return allocator.dupe(u8, "null");

    var linked_ranges_json = std.ArrayList(u8).init(allocator);
    defer linked_ranges_json.deinit();
    try linked_ranges_json.writer().writeAll("{\"ranges\":[");

    var wrote = false;
    var scan_index: usize = 0;
    while (scan_index < contents.len) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }

        const start_index = scan_index;
        while (scan_index < contents.len and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, symbol)) continue;

        if (wrote) try linked_ranges_json.writer().writeAll(",");
        try writeRangeFromOffsetsJson(linked_ranges_json.writer(), contents, start_index, scan_index);
        wrote = true;
    }

    try linked_ranges_json.writer().writeAll("],\"wordPattern\":\"[A-Za-z0-9_$]+\"}");
    return linked_ranges_json.toOwnedSlice();
}

fn buildMemberLinkedEditingRangeResultJson(allocator: std.mem.Allocator, contents: []const u8, member: MemberSymbolMatch) ![]u8 {
    var member_ranges_json = std.ArrayList(u8).init(allocator);
    defer member_ranges_json.deinit();
    try member_ranges_json.writer().writeAll("{\"ranges\":[");

    var wrote = false;
    var scan_index = member.container_start;
    while (scan_index < member.container_end) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }

        const start_index = scan_index;
        while (scan_index < member.container_end and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, member.name)) continue;

        if (wrote) try member_ranges_json.writer().writeAll(",");
        try writeRangeFromOffsetsJson(member_ranges_json.writer(), contents, start_index, scan_index);
        wrote = true;
    }

    try member_ranges_json.writer().writeAll("],\"wordPattern\":\"[A-Za-z0-9_$]+\"}");
    return member_ranges_json.toOwnedSlice();
}

fn buildInlayHintResultJson(allocator: std.mem.Allocator, request: InlayHintRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    const start_offset = positionToOffset(contents, request.start_line, request.start_character) orelse return allocator.dupe(u8, "[]");
    const end_offset = positionToOffset(contents, request.end_line, request.end_character) orelse return allocator.dupe(u8, "[]");
    if (end_offset < start_offset) return allocator.dupe(u8, "[]");

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var inlay_hints_json = std.ArrayList(u8).init(allocator);
    defer inlay_hints_json.deinit();
    try inlay_hints_json.writer().writeAll("[");

    var wrote = false;
    for (top_level.declarations.items) |decl| {
        if (decl.kind != .function_decl) continue;
        const function_name = decl.name orelse continue;
        const declaration_name_start = declarationNameStartOffset(decl, function_name);

        var function_params = try extractFunctionParameters(allocator, contents, decl);
        defer {
            for (function_params.items) |param| allocator.free(param);
            function_params.deinit();
        }
        if (function_params.items.len == 0) continue;

        var search_start: usize = 0;
        while (search_start < contents.len) {
            const call_start = std.mem.indexOfPos(u8, contents, search_start, function_name) orelse break;
            search_start = call_start + function_name.len;

            if (call_start > 0 and isIdentifierByte(contents[call_start - 1])) continue;
            if (search_start < contents.len and isIdentifierByte(contents[search_start])) continue;
            if (call_start == declaration_name_start) continue;

            var open_paren = search_start;
            while (open_paren < contents.len and std.ascii.isWhitespace(contents[open_paren])) : (open_paren += 1) {}
            if (open_paren >= contents.len or contents[open_paren] != '(') continue;

            const close_paren = findMatchingDelimiter(contents, open_paren, '(', ')') orelse continue;
            if (close_paren < start_offset or open_paren > end_offset) continue;

            var call_arguments = try extractCallArguments(allocator, contents[open_paren + 1 .. close_paren]);
            defer {
                for (call_arguments.items) |arg| allocator.free(arg);
                call_arguments.deinit();
            }

            for (call_arguments.items, 0..) |arg, index| {
                if (index >= function_params.items.len) break;
                const arg_index = std.mem.indexOfPos(u8, contents, open_paren + 1, arg) orelse continue;
                if (arg_index < start_offset or arg_index > end_offset) continue;

                if (wrote) try inlay_hints_json.writer().writeAll(",");
                try inlay_hints_json.writer().writeAll("{\"position\":{");
                const position = offsetToLineCharacter(contents, arg_index);
                try inlay_hints_json.writer().print("\"line\":{d},\"character\":{d}", .{ position.line, position.character });
                try inlay_hints_json.writer().writeAll("},\"label\":");

                const parameter_label = parameterLabelName(function_params.items[index]);
                var label_text = std.ArrayList(u8).init(allocator);
                defer label_text.deinit();
                try label_text.writer().print("{s}:", .{parameter_label});
                try std.json.encodeJsonString(label_text.items, .{}, inlay_hints_json.writer());
                try inlay_hints_json.writer().writeAll(",\"kind\":2,\"paddingRight\":true}");
                wrote = true;
            }
        }
    }

    try inlay_hints_json.writer().writeAll("]");
    return inlay_hints_json.toOwnedSlice();
}

fn buildDocumentColorResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var document_colors_json = std.ArrayList(u8).init(allocator);
    defer document_colors_json.deinit();
    try document_colors_json.writer().writeAll("[");

    var wrote = false;
    var scan_index: usize = 0;
    while (scan_index < contents.len) : (scan_index += 1) {
        if (contents[scan_index] != '#') continue;

        const hex_len = colorLiteralLength(contents, scan_index) orelse continue;
        const literal = contents[scan_index + 1 .. scan_index + 1 + hex_len];
        const rgba = parseHexColorLiteral(literal) orelse continue;

        if (wrote) try document_colors_json.writer().writeAll(",");
        try document_colors_json.writer().writeAll("{\"range\":");
        try writeRangeFromOffsetsJson(document_colors_json.writer(), contents, scan_index, scan_index + 1 + hex_len);
        try document_colors_json.writer().writeAll(",\"color\":{");
        try document_colors_json.writer().print("\"red\":{d},\"green\":{d},\"blue\":{d},\"alpha\":{d}", .{
            rgba.red,
            rgba.green,
            rgba.blue,
            rgba.alpha,
        });
        try document_colors_json.writer().writeAll("}}");
        wrote = true;
    }

    try document_colors_json.writer().writeAll("]");
    return document_colors_json.toOwnedSlice();
}

fn buildDocumentLinkResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var document_links_json = std.ArrayList(u8).init(allocator);
    defer document_links_json.deinit();
    try document_links_json.writer().writeAll("[");

    var wrote = false;
    var search_index: usize = 0;
    while (search_index < contents.len) {
        const http_index = findNextUrlStart(contents, search_index) orelse break;
        const end_index = findUrlEnd(contents, http_index);
        if (wrote) try document_links_json.writer().writeAll(",");
        try writeDocumentLinkJson(document_links_json.writer(), contents, http_index, end_index, contents[http_index..end_index]);
        wrote = true;
        search_index = end_index;
    }

    for (top_level.declarations.items) |decl| {
        const specifier = decl.module_specifier orelse continue;
        if (!std.mem.startsWith(u8, specifier, "./") and !std.mem.startsWith(u8, specifier, "../")) continue;

        const quoted = try std.fmt.allocPrint(allocator, "\"{s}\"", .{specifier});
        defer allocator.free(quoted);
        const quote_index = std.mem.indexOfPos(u8, contents, decl.start.offset, quoted) orelse continue;
        const start_index = quote_index + 1;
        const end_index = start_index + specifier.len;
        const link_target = try resolveRelativeLinkTarget(allocator, document, specifier);
        defer allocator.free(link_target);

        if (wrote) try document_links_json.writer().writeAll(",");
        try writeDocumentLinkJson(document_links_json.writer(), contents, start_index, end_index, link_target);
        wrote = true;
    }

    try document_links_json.writer().writeAll("]");
    return document_links_json.toOwnedSlice();
}

fn buildCodeLensResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var code_lenses_json = std.ArrayList(u8).init(allocator);
    defer code_lenses_json.deinit();
    try code_lenses_json.writer().writeAll("[");

    var wrote = false;
    for (top_level.declarations.items) |decl| {
        const declaration_name = decl.name orelse continue;
        const declaration_start = declarationNameStartOffset(decl, declaration_name);
        const declaration_end = decl.end_offset;
        const refs = countIdentifierOccurrencesInRange(contents, 0, contents.len, declaration_name);
        const reference_count = if (refs > 0) refs - 1 else 0;
        try appendCodeLensJson(allocator, &code_lenses_json, contents, declaration_start, declaration_end, reference_count, &wrote);
    }

    for (top_level.declarations.items) |decl| {
        wrote = try appendDeclarationMemberCodeLensJson(allocator, &code_lenses_json, contents, decl, wrote);
    }

    try code_lenses_json.writer().writeAll("]");
    return code_lenses_json.toOwnedSlice();
}

fn appendCodeLensJson(
    allocator: std.mem.Allocator,
    body: *std.ArrayList(u8),
    contents: []const u8,
    start_offset: usize,
    end_offset: usize,
    reference_count: usize,
    wrote: *bool,
) !void {
    const start_position = offsetToLineCharacter(contents, start_offset);
    const end_position = offsetToLineCharacter(contents, end_offset);

    if (wrote.*) try body.writer().writeAll(",");
    try body.writer().writeAll("{\"range\":{\"start\":{");
    try body.writer().print("\"line\":{d},\"character\":{d}", .{ start_position.line, start_position.character });
    try body.writer().writeAll("},\"end\":{");
    try body.writer().print("\"line\":{d},\"character\":{d}", .{ end_position.line, end_position.character });
    try body.writer().writeAll("}},\"command\":{\"title\":");

    var title_text = std.ArrayList(u8).init(allocator);
    defer title_text.deinit();
    try title_text.writer().print("{d} references", .{reference_count});
    try std.json.encodeJsonString(title_text.items, .{}, body.writer());
    try body.writer().writeAll(",\"command\":\"zts.showReferences\"}}");
    wrote.* = true;
}

fn appendMemberCodeLensJsonInRange(
    allocator: std.mem.Allocator,
    body: *std.ArrayList(u8),
    contents: []const u8,
    start_index: usize,
    close_index: usize,
    mode: MemberScanMode,
    wrote: bool,
) !bool {
    var did_write = wrote;
    var scan_index = start_index;
    var scan_depth: usize = 0;

    while (scan_index < close_index) {
        const member_name_start = nextMemberNameStart(contents, scan_index, close_index, mode, &scan_depth) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);
        try appendMemberCodeLensJson(
            allocator,
            body,
            contents,
            member_name_start,
            member_entry.name_end,
            close_index,
            &did_write,
        );
        scan_index = member_entry.range_end;
    }

    return did_write;
}

fn appendMemberCodeLensJson(
    allocator: std.mem.Allocator,
    body: *std.ArrayList(u8),
    contents: []const u8,
    name_start: usize,
    name_end: usize,
    close_index: usize,
    wrote: *bool,
) !void {
    const member_name = contents[name_start..name_end];
    const refs = countIdentifierOccurrencesInRange(contents, name_start, close_index, member_name);
    const reference_count = if (refs > 0) refs - 1 else 0;
    try appendCodeLensJson(allocator, body, contents, name_start, name_end, reference_count, wrote);
}

fn countIdentifierOccurrencesInRange(contents: []const u8, start_index: usize, end_index: usize, symbol: []const u8) usize {
    var count: usize = 0;
    var scan_index = start_index;
    while (scan_index < end_index) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }

        const ident_start = scan_index;
        while (scan_index < end_index and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        if (std.mem.eql(u8, contents[ident_start..scan_index], symbol)) count += 1;
    }
    return count;
}

fn appendDeclarationMemberCodeLensJson(
    allocator: std.mem.Allocator,
    body: *std.ArrayList(u8),
    contents: []const u8,
    decl: parser.Declaration,
    wrote: bool,
) !bool {
    const range = declarationMemberScanRange(contents, decl) orelse return wrote;
    return appendMemberCodeLensJsonInRange(allocator, body, contents, range.start_index, range.close_index, range.mode, wrote);
}

fn buildColorPresentationResultJson(allocator: std.mem.Allocator, request: ColorPresentationRequest) ![]u8 {
    const presentation = try colorToHexPresentation(allocator, request.color);
    defer allocator.free(presentation);

    var color_presentations_json = std.ArrayList(u8).init(allocator);
    defer color_presentations_json.deinit();
    try color_presentations_json.writer().writeAll("[{\"label\":");
    try std.json.encodeJsonString(presentation, .{}, color_presentations_json.writer());
    try color_presentations_json.writer().writeAll(",\"textEdit\":{\"range\":{\"start\":{");
    try color_presentations_json.writer().print("\"line\":{d},\"character\":{d}", .{ request.range_start_line, request.range_start_character });
    try color_presentations_json.writer().writeAll("},\"end\":{");
    try color_presentations_json.writer().print("\"line\":{d},\"character\":{d}", .{ request.range_end_line, request.range_end_character });
    try color_presentations_json.writer().writeAll("}},\"newText\":");
    try std.json.encodeJsonString(presentation, .{}, color_presentations_json.writer());
    try color_presentations_json.writer().writeAll("}}]");
    return color_presentations_json.toOwnedSlice();
}

fn buildFormattingResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    const formatted = try formatDocumentText(allocator, contents);
    defer allocator.free(formatted);

    var formatting_edits_json = std.ArrayList(u8).init(allocator);
    defer formatting_edits_json.deinit();
    try formatting_edits_json.writer().writeAll("[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{");
    const document_end = offsetToLineCharacter(contents, contents.len);
    try formatting_edits_json.writer().print("\"line\":{d},\"character\":{d}", .{ document_end.line, document_end.character });
    try formatting_edits_json.writer().writeAll("}},\"newText\":");
    try std.json.encodeJsonString(formatted, .{}, formatting_edits_json.writer());
    try formatting_edits_json.writer().writeAll("}]");
    return formatting_edits_json.toOwnedSlice();
}

fn buildRangeFormattingResultJson(allocator: std.mem.Allocator, request: RangeFormattingRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    const start_offset = positionToOffset(contents, request.start_line, request.start_character) orelse return allocator.dupe(u8, "[]");
    const end_offset = positionToOffset(contents, request.end_line, request.end_character) orelse return allocator.dupe(u8, "[]");
    if (end_offset < start_offset) return allocator.dupe(u8, "[]");

    const formatted = try formatRangeText(allocator, contents, start_offset, end_offset);
    defer allocator.free(formatted);

    var range_formatting_edits_json = std.ArrayList(u8).init(allocator);
    defer range_formatting_edits_json.deinit();
    try range_formatting_edits_json.writer().writeAll("[{\"range\":{\"start\":{");
    try range_formatting_edits_json.writer().print("\"line\":{d},\"character\":{d}", .{ request.start_line, request.start_character });
    try range_formatting_edits_json.writer().writeAll("},\"end\":{");
    try range_formatting_edits_json.writer().print("\"line\":{d},\"character\":{d}", .{ request.end_line, request.end_character });
    try range_formatting_edits_json.writer().writeAll("}},\"newText\":");
    try std.json.encodeJsonString(formatted, .{}, range_formatting_edits_json.writer());
    try range_formatting_edits_json.writer().writeAll("}]");
    return range_formatting_edits_json.toOwnedSlice();
}

fn buildOnTypeFormattingResultJson(allocator: std.mem.Allocator, request: OnTypeFormattingRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    if (!std.mem.eql(u8, request.trigger, "\n")) return allocator.dupe(u8, "[]");

    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    if (request.line == 0) return allocator.dupe(u8, "[]");
    const target_line = request.line - 1;
    const start_offset = positionToOffset(contents, target_line, 0) orelse return allocator.dupe(u8, "[]");
    const end_offset = positionToOffset(contents, request.line, 0) orelse return allocator.dupe(u8, "[]");

    const formatted = try formatRangeText(allocator, contents, start_offset, end_offset);
    defer allocator.free(formatted);

    var on_type_formatting_edits_json = std.ArrayList(u8).init(allocator);
    defer on_type_formatting_edits_json.deinit();
    try on_type_formatting_edits_json.writer().writeAll("[{\"range\":{\"start\":{");
    try on_type_formatting_edits_json.writer().print("\"line\":{d},\"character\":0", .{target_line});
    try on_type_formatting_edits_json.writer().writeAll("},\"end\":{");
    try on_type_formatting_edits_json.writer().print("\"line\":{d},\"character\":0", .{request.line});
    try on_type_formatting_edits_json.writer().writeAll("}},\"newText\":");
    try std.json.encodeJsonString(formatted, .{}, on_type_formatting_edits_json.writer());
    try on_type_formatting_edits_json.writer().writeAll("}]");
    return on_type_formatting_edits_json.toOwnedSlice();
}

fn formatDocumentText(allocator: std.mem.Allocator, contents: []const u8) ![]u8 {
    var formatted_text = std.ArrayList(u8).init(allocator);
    defer formatted_text.deinit();

    var line_start: usize = 0;
    var line_index: usize = 0;
    while (line_index < contents.len) : (line_index += 1) {
        if (contents[line_index] != '\n') continue;
        var line_text = contents[line_start..line_index];
        if (line_text.len > 0 and line_text[line_text.len - 1] == '\r') {
            line_text = line_text[0 .. line_text.len - 1];
        }
        const trimmed = std.mem.trimRight(u8, line_text, " \t");
        try formatted_text.writer().writeAll(trimmed);
        try formatted_text.writer().writeByte('\n');
        line_start = line_index + 1;
    }

    if (line_start < contents.len) {
        const trailing_text = std.mem.trimRight(u8, contents[line_start..], " \t\r\n");
        try formatted_text.writer().writeAll(trailing_text);
        try formatted_text.writer().writeByte('\n');
    } else if (formatted_text.items.len == 0 or formatted_text.items[formatted_text.items.len - 1] != '\n') {
        try formatted_text.writer().writeByte('\n');
    }

    return formatted_text.toOwnedSlice();
}

fn formatRangeText(allocator: std.mem.Allocator, contents: []const u8, start_offset: usize, end_offset: usize) ![]u8 {
    var formatted_text = std.ArrayList(u8).init(allocator);
    defer formatted_text.deinit();

    var range_text = contents[start_offset..end_offset];
    var line_start: usize = 0;
    var line_index: usize = 0;
    while (line_index < range_text.len) : (line_index += 1) {
        if (range_text[line_index] != '\n') continue;
        var line_text = range_text[line_start..line_index];
        if (line_text.len > 0 and line_text[line_text.len - 1] == '\r') {
            line_text = line_text[0 .. line_text.len - 1];
        }
        const trimmed = std.mem.trimRight(u8, line_text, " \t");
        try formatted_text.writer().writeAll(trimmed);
        try formatted_text.writer().writeByte('\n');
        line_start = line_index + 1;
    }

    if (line_start < range_text.len) {
        var trailing_slice = range_text[line_start..];
        if (trailing_slice.len > 0 and trailing_slice[trailing_slice.len - 1] == '\r') {
            trailing_slice = trailing_slice[0 .. trailing_slice.len - 1];
        }
        try formatted_text.writer().writeAll(std.mem.trimRight(u8, trailing_slice, " \t"));
        if (end_offset == contents.len and (formatted_text.items.len == 0 or formatted_text.items[formatted_text.items.len - 1] != '\n')) {
            try formatted_text.writer().writeByte('\n');
        }
    }

    return formatted_text.toOwnedSlice();
}

const ImportEntry = struct {
    module_specifier: []const u8,
    text: []u8,
};

fn lessThanImportEntry(_: void, a: ImportEntry, b: ImportEntry) bool {
    const by_specifier = std.mem.order(u8, a.module_specifier, b.module_specifier);
    if (by_specifier != .eq) return by_specifier == .lt;
    return std.mem.lessThan(u8, a.text, b.text);
}

fn lineEndOffset(contents: []const u8, offset: usize) usize {
    var line_end = @min(offset, contents.len);
    while (line_end < contents.len and contents[line_end] != '\n') : (line_end += 1) {}
    return line_end;
}

const OffsetRange = struct {
    start: usize,
    end: usize,
};

fn writeSelectionRangeForPositionJson(
    writer: anytype,
    contents: []const u8,
    declarations: []const parser.Declaration,
    position: SelectionRangePosition,
) !void {
    const offset = positionToOffset(contents, position.line, position.character) orelse {
        try writer.writeAll("null");
        return;
    };

    var spans: [4]OffsetRange = undefined;
    var span_count: usize = 0;

    if (identifierBoundsAtOffset(contents, offset)) |identifier| {
        spans[span_count] = identifier;
        span_count += 1;
    }

    const line_start = positionToOffset(contents, position.line, 0) orelse offset;
    const line_end = lineEndOffset(contents, line_start);
    const line_range = OffsetRange{ .start = line_start, .end = line_end };
    if (!containsEqualRange(spans[0..span_count], line_range)) {
        spans[span_count] = line_range;
        span_count += 1;
    }

    if (resolveMemberSymbolAtOffset(contents, declarations, offset)) |member| {
        const member_range = OffsetRange{ .start = member.declaration_start, .end = member.range_end };
        if (!containsEqualRange(spans[0..span_count], member_range)) {
            spans[span_count] = member_range;
            span_count += 1;
        }
    }

    if (findTopLevelSelectionContainer(contents, declarations, offset)) |container| {
        if (!containsEqualRange(spans[0..span_count], container)) {
            spans[span_count] = container;
            span_count += 1;
        }
    }

    if (span_count == 0) {
        try writer.writeAll("null");
        return;
    }

    for (spans[0..span_count], 0..) |range, index| {
        const span_start = range.start;
        const span_end = range.end;
        try writer.writeAll("{\"range\":");
        try writeRangeFromOffsetsJson(writer, contents, span_start, span_end);
        if (index + 1 < span_count) {
            try writer.writeAll(",\"parent\":");
        }
    }

    var close_count: usize = 0;
    while (close_count < span_count) : (close_count += 1) {
        try writer.writeAll("}");
    }
}

fn identifierBoundsAtOffset(contents: []const u8, offset: usize) ?OffsetRange {
    const ident = identifierAtOffset(contents, offset) orelse return null;
    var identifier_start = if (offset < contents.len) offset else contents.len - 1;
    if (!isIdentifierByte(contents[identifier_start]) and identifier_start > 0 and isIdentifierByte(contents[identifier_start - 1])) {
        identifier_start -= 1;
    }
    while (identifier_start > 0 and isIdentifierByte(contents[identifier_start - 1])) : (identifier_start -= 1) {}
    return .{ .start = identifier_start, .end = identifier_start + ident.len };
}

fn findTopLevelSelectionContainer(contents: []const u8, declarations: []const parser.Declaration, offset: usize) ?OffsetRange {
    for (declarations) |decl| {
        const declaration_start = decl.start.offset;
        if (offset < declaration_start) continue;

        const line_end = lineEndOffset(contents, declaration_start);
        const line_range = OffsetRange{
            .start = declaration_start,
            .end = line_end,
        };
        if (offset >= declaration_start and offset <= line_end) return line_range;

        const open_brace = std.mem.indexOfPos(u8, contents, declaration_start, "{") orelse continue;
        const close_brace = memberContainerCloseIndex(contents, open_brace) orelse continue;
        if (offset >= declaration_start and offset <= close_brace + 1) {
            return .{ .start = declaration_start, .end = close_brace + 1 };
        }
    }
    return null;
}

fn containsEqualRange(ranges: []const OffsetRange, candidate: OffsetRange) bool {
    const candidate_start = candidate.start;
    const candidate_end = candidate.end;
    for (ranges) |range| {
        const existing_start = range.start;
        const existing_end = range.end;
        if (existing_start == candidate_start and existing_end == candidate_end) return true;
    }
    return false;
}

fn writeRangeFromOffsetsJson(writer: anytype, contents: []const u8, start_offset: usize, end_offset: usize) !void {
    const start_position = offsetToLineCharacter(contents, start_offset);
    const end_position = offsetToLineCharacter(contents, end_offset);
    try writer.writeAll("{\"start\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ start_position.line, start_position.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ end_position.line, end_position.character });
    try writer.writeAll("}}");
}

fn buildRenameResultJson(allocator: std.mem.Allocator, request: RenameRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "{\"changes\":{}}");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "{\"changes\":{}}");
    if (resolveMemberSymbolAtOffset(contents, top_level.declarations.items, offset)) |member| {
        return buildMemberRenameResultJson(allocator, request.document, contents, member, request.new_name);
    }
    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "{\"changes\":{}}");

    var rename_edits_json = std.ArrayList(u8).init(allocator);
    defer rename_edits_json.deinit();
    try rename_edits_json.writer().writeAll("{\"changes\":{");
    try std.json.encodeJsonString(request.document, .{}, rename_edits_json.writer());
    try rename_edits_json.writer().writeAll(":[");

    var wrote = false;
    var scan_index: usize = 0;
    while (scan_index < contents.len) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }

        const start_index = scan_index;
        while (scan_index < contents.len and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, symbol)) continue;

        const match_start = offsetToLineCharacter(contents, start_index);
        const match_end = offsetToLineCharacter(contents, scan_index);
        if (wrote) try rename_edits_json.writer().writeAll(",");
        try writeTextEditJson(rename_edits_json.writer(), match_start, match_end, request.new_name);
        wrote = true;
    }

    try rename_edits_json.writer().writeAll("]}}");
    return rename_edits_json.toOwnedSlice();
}

fn buildMemberRenameResultJson(
    allocator: std.mem.Allocator,
    document: []const u8,
    contents: []const u8,
    member: MemberSymbolMatch,
    new_name: []const u8,
) ![]u8 {
    var rename_edits_json = std.ArrayList(u8).init(allocator);
    defer rename_edits_json.deinit();
    try rename_edits_json.writer().writeAll("{\"changes\":{");
    try std.json.encodeJsonString(document, .{}, rename_edits_json.writer());
    try rename_edits_json.writer().writeAll(":[");

    var wrote = false;
    var scan_index = member.container_start;
    while (scan_index < member.container_end) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }
        const start_index = scan_index;
        while (scan_index < member.container_end and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        const ident = contents[start_index..scan_index];
        if (!std.mem.eql(u8, ident, member.name)) continue;

        const match_start = offsetToLineCharacter(contents, start_index);
        const match_end = offsetToLineCharacter(contents, scan_index);
        if (wrote) try rename_edits_json.writer().writeAll(",");
        try writeTextEditJson(rename_edits_json.writer(), match_start, match_end, new_name);
        wrote = true;
    }

    try rename_edits_json.writer().writeAll("]}}");
    return rename_edits_json.toOwnedSlice();
}

fn buildPrepareRenameResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "null");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "null");
    if (resolveMemberSymbolAtOffset(contents, top_level.declarations.items, offset)) |member| {
        const name_start_position = offsetToLineCharacter(contents, member.declaration_start);
        const name_end_position = offsetToLineCharacter(contents, member.declaration_end);
        return buildPrepareRenameResultJsonFromRange(allocator, name_start_position, name_end_position, member.name);
    }
    const symbol = identifierAtOffset(contents, offset) orelse return allocator.dupe(u8, "null");

    var start_index = if (offset < contents.len) offset else contents.len - 1;
    if (!isIdentifierByte(contents[start_index]) and start_index > 0 and isIdentifierByte(contents[start_index - 1])) {
        start_index -= 1;
    }
    if (!isIdentifierByte(contents[start_index])) return allocator.dupe(u8, "null");
    while (start_index > 0 and isIdentifierByte(contents[start_index - 1])) : (start_index -= 1) {}
    const end_index = start_index + symbol.len;

    const name_start_position = offsetToLineCharacter(contents, start_index);
    const name_end_position = offsetToLineCharacter(contents, end_index);
    return buildPrepareRenameResultJsonFromRange(allocator, name_start_position, name_end_position, symbol);
}

fn buildPrepareRenameResultJsonFromRange(
    allocator: std.mem.Allocator,
    start: LineCharacter,
    end: LineCharacter,
    placeholder: []const u8,
) ![]u8 {
    var prepare_rename_json = std.ArrayList(u8).init(allocator);
    defer prepare_rename_json.deinit();
    try writePrepareRenameJson(prepare_rename_json.writer(), start, end, placeholder);
    return prepare_rename_json.toOwnedSlice();
}

fn buildWorkspaceSymbolResultJson(allocator: std.mem.Allocator, query: []const u8) ![]u8 {
    var cwd = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer cwd.close();

    var walker = try cwd.walk(allocator);
    defer walker.deinit();

    var source_paths = std.ArrayList([]u8).init(allocator);
    defer {
        for (source_paths.items) |path| allocator.free(path);
        source_paths.deinit();
    }

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!isSupportedSourceFile(entry.basename)) continue;
        try source_paths.append(try allocator.dupe(u8, entry.path));
    }

    std.mem.sort([]u8, source_paths.items, {}, lessThanOwnedPath);

    var candidates = std.ArrayList(WorkspaceSymbolCandidate).init(allocator);
    defer {
        for (candidates.items) |candidate| {
            allocator.free(candidate.name);
            if (candidate.container_name) |container_name| allocator.free(container_name);
        }
        candidates.deinit();
    }

    for (source_paths.items) |path| {
        const source_file = cwd.openFile(path, .{}) catch continue;
        defer source_file.close();

        const contents = source_file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch continue;
        defer allocator.free(contents);

        var parsed = parser.parseTopLevel(allocator, contents) catch continue;
        defer parsed.deinit(allocator);

        for (parsed.declarations.items) |decl| {
            const declaration_name = decl.name orelse continue;
            if (workspaceSymbolMatchesQuery(declaration_name, query)) {
                const declaration_start = offsetToLineCharacter(contents, declarationNameStartOffset(decl, declaration_name));
                const declaration_end = offsetToLineCharacter(contents, decl.end_offset);
                try appendOrReplaceWorkspaceSymbolCandidate(allocator, &candidates, .{
                    .path = path,
                    .name = try allocator.dupe(u8, declaration_name),
                    .container_name = null,
                    .kind = declarationSymbolKind(decl.kind),
                    .match_rank = workspaceSymbolMatchRank(declaration_name, query),
                    .preference_rank = declarationPreferenceRank(decl.kind),
                    .start = declaration_start,
                    .end = declaration_end,
                });
            }

            try appendDeclarationMemberWorkspaceSymbolCandidates(allocator, &candidates, path, contents, decl, query);
        }
    }

    std.mem.sort(WorkspaceSymbolCandidate, candidates.items, {}, lessThanWorkspaceSymbolCandidate);

    var workspace_symbols_json = std.ArrayList(u8).init(allocator);
    defer workspace_symbols_json.deinit();
    try workspace_symbols_json.writer().writeAll("[");

    var wrote = false;
    for (candidates.items) |candidate| {
        try appendWorkspaceSymbolJsonWithContainer(
            allocator,
            &workspace_symbols_json,
            candidate.path,
            candidate.name,
            candidate.kind,
            candidate.start,
            candidate.end,
            candidate.container_name,
            &wrote,
        );
    }

    try workspace_symbols_json.writer().writeAll("]");
    return workspace_symbols_json.toOwnedSlice();
}

fn lessThanOwnedPath(_: void, a: []u8, b: []u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const WorkspaceSymbolCandidate = struct {
    path: []const u8,
    name: []const u8,
    container_name: ?[]const u8,
    kind: usize,
    match_rank: u8,
    preference_rank: u8,
    start: LineCharacter,
    end: LineCharacter,
};

fn lessThanWorkspaceSymbolCandidate(_: void, a: WorkspaceSymbolCandidate, b: WorkspaceSymbolCandidate) bool {
    if (a.match_rank != b.match_rank) return a.match_rank < b.match_rank;
    if (a.preference_rank != b.preference_rank) return a.preference_rank < b.preference_rank;

    const by_path = std.mem.order(u8, a.path, b.path);
    if (by_path != .eq) return by_path == .lt;

    const by_name = std.mem.order(u8, a.name, b.name);
    if (by_name != .eq) return by_name == .lt;

    if (a.kind != b.kind) return a.kind < b.kind;

    const a_container = a.container_name orelse "";
    const b_container = b.container_name orelse "";
    const by_container = std.mem.order(u8, a_container, b_container);
    if (by_container != .eq) return by_container == .lt;

    if (a.start.line != b.start.line) return a.start.line < b.start.line;
    if (a.start.character != b.start.character) return a.start.character < b.start.character;
    if (a.end.line != b.end.line) return a.end.line < b.end.line;
    return a.end.character < b.end.character;
}

fn appendWorkspaceSymbolJson(
    allocator: std.mem.Allocator,
    body: *std.ArrayList(u8),
    path: []const u8,
    name: []const u8,
    kind: usize,
    start: LineCharacter,
    end: LineCharacter,
    wrote: *bool,
) !void {
    try appendWorkspaceSymbolJsonWithContainer(allocator, body, path, name, kind, start, end, null, wrote);
}

fn appendWorkspaceSymbolJsonWithContainer(
    allocator: std.mem.Allocator,
    body: *std.ArrayList(u8),
    path: []const u8,
    name: []const u8,
    kind: usize,
    start: LineCharacter,
    end: LineCharacter,
    container_name: ?[]const u8,
    wrote: *bool,
) !void {
    _ = allocator;
    if (wrote.*) try body.writer().writeAll(",");
    try body.writer().writeAll("{\"name\":");
    try std.json.encodeJsonString(name, .{}, body.writer());
    if (container_name) |container| {
        try body.writer().writeAll(",\"containerName\":");
        try std.json.encodeJsonString(container, .{}, body.writer());
    }
    try body.writer().print(",\"kind\":{d},\"location\":{{\"uri\":", .{kind});
    try std.json.encodeJsonString(path, .{}, body.writer());
    try body.writer().writeAll(",\"range\":{\"start\":{");
    try body.writer().print("\"line\":{d},\"character\":{d}", .{ start.line, start.character });
    try body.writer().writeAll("},\"end\":{");
    try body.writer().print("\"line\":{d},\"character\":{d}", .{ end.line, end.character });
    try body.writer().writeAll("}}}}");
    wrote.* = true;
}

fn declarationPreferenceRank(kind: parser.DeclarationKind) u8 {
    return switch (kind) {
        .function_decl => 1,
        .class_decl => 2,
        .interface_decl => 3,
        .variable_stmt => 5,
        .type_decl => 6,
        .import_stmt => 7,
        .export_stmt => 8,
    };
}

fn declarationSymbolKind(kind: parser.DeclarationKind) usize {
    return switch (kind) {
        .import_stmt => 2,
        .variable_stmt => 13,
        .function_decl => 12,
        .class_decl => 5,
        .interface_decl => 11,
        .type_decl => 13,
        .export_stmt => 2,
    };
}

fn declarationCompletionKind(kind: parser.DeclarationKind) usize {
    return switch (kind) {
        .import_stmt => 9,
        .variable_stmt => 6,
        .function_decl => 3,
        .class_decl => 7,
        .interface_decl => 8,
        .type_decl => 6,
        .export_stmt => 9,
    };
}

fn declarationCompletionDetail(kind: parser.DeclarationKind) []const u8 {
    return switch (kind) {
        .import_stmt => "import",
        .variable_stmt => "variable",
        .function_decl => "function",
        .class_decl => "class",
        .interface_decl => "interface",
        .type_decl => "type",
        .export_stmt => "export",
    };
}

fn appendMemberWorkspaceSymbolCandidatesInRange(
    allocator: std.mem.Allocator,
    candidates: *std.ArrayList(WorkspaceSymbolCandidate),
    path: []const u8,
    container_name: []const u8,
    contents: []const u8,
    start_index: usize,
    close_index: usize,
    mode: MemberScanMode,
    query: []const u8,
) !void {
    var scan_index = start_index;
    var scan_depth: usize = 0;

    while (scan_index < close_index) {
        const member_name_start = nextMemberNameStart(contents, scan_index, close_index, mode, &scan_depth) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);
        const member_name = member_entry.name(contents);

        if (workspaceSymbolMatchesQuery(member_name, query)) {
            try appendMemberWorkspaceSymbolCandidate(
                allocator,
                candidates,
                path,
                container_name,
                contents,
                member_name,
                member_name_start,
                member_entry.name_end,
                member_entry.after_name,
                close_index,
                query,
            );
        }

        scan_index = member_entry.range_end;
    }
}

fn appendMemberWorkspaceSymbolCandidate(
    allocator: std.mem.Allocator,
    candidates: *std.ArrayList(WorkspaceSymbolCandidate),
    path: []const u8,
    container_name: []const u8,
    contents: []const u8,
    name: []const u8,
    name_start: usize,
    name_end: usize,
    after_name: usize,
    close_index: usize,
    query: []const u8,
) !void {
    const category = memberCategory(contents, after_name, close_index);
    try appendOrReplaceWorkspaceSymbolCandidate(allocator, candidates, .{
        .path = path,
        .name = try allocator.dupe(u8, name),
        .container_name = try allocator.dupe(u8, container_name),
        .kind = memberSymbolKind(category),
        .match_rank = workspaceSymbolMatchRank(name, query),
        .preference_rank = memberWorkspaceSymbolPreferenceRank(category),
        .start = offsetToLineCharacter(contents, name_start),
        .end = offsetToLineCharacter(contents, name_end),
    });
}

fn workspaceSymbolMatchesQuery(name: []const u8, query: []const u8) bool {
    return query.len == 0 or std.mem.indexOf(u8, name, query) != null or asciiCaseInsensitiveContains(name, query);
}

fn workspaceSymbolMatchRank(name: []const u8, query: []const u8) u8 {
    return if (query.len == 0 or std.mem.indexOf(u8, name, query) != null) 0 else 1;
}

fn appendDeclarationMemberWorkspaceSymbolCandidates(
    allocator: std.mem.Allocator,
    candidates: *std.ArrayList(WorkspaceSymbolCandidate),
    path: []const u8,
    contents: []const u8,
    decl: parser.Declaration,
    query: []const u8,
) !void {
    const range = declarationMemberScanRange(contents, decl) orelse return;
    const container_name = decl.name orelse return;
    try appendMemberWorkspaceSymbolCandidatesInRange(
        allocator,
        candidates,
        path,
        container_name,
        contents,
        range.start_index,
        range.close_index,
        range.mode,
        query,
    );
}

fn appendOrReplaceWorkspaceSymbolCandidate(
    allocator: std.mem.Allocator,
    candidates: *std.ArrayList(WorkspaceSymbolCandidate),
    next: WorkspaceSymbolCandidate,
) !void {
    for (candidates.items, 0..) |candidate, index| {
        if (!std.mem.eql(u8, candidate.path, next.path)) continue;
        if (!std.mem.eql(u8, candidate.name, next.name)) continue;
        const candidate_container_name = candidate.container_name orelse "";
        const next_container_name = next.container_name orelse "";
        if (!std.mem.eql(u8, candidate_container_name, next_container_name)) continue;
        const prefers_next =
            next.match_rank < candidate.match_rank or
            (next.match_rank == candidate.match_rank and
                (next.preference_rank < candidate.preference_rank or
                    (next.preference_rank == candidate.preference_rank and
                        (next.kind < candidate.kind or
                            (next.kind == candidate.kind and
                                (next.start.line < candidate.start.line or
                                    (next.start.line == candidate.start.line and next.start.character < candidate.start.character)))))));
        if (prefers_next) {
            allocator.free(candidate.name);
            if (candidate.container_name) |container_name| allocator.free(container_name);
            candidates.items[index] = next;
        } else {
            allocator.free(next.name);
            if (next.container_name) |container_name| allocator.free(container_name);
        }
        return;
    }
    try candidates.append(next);
}

fn asciiCaseInsensitiveContains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var haystack_index: usize = 0;
    while (haystack_index + needle.len <= haystack.len) : (haystack_index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[haystack_index .. haystack_index + needle.len], needle)) return true;
    }
    return false;
}

fn buildCompletionResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "[]");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "[]");
    const prefix_end = if (offset <= contents.len) offset else contents.len;
    var prefix_start = prefix_end;
    while (prefix_start > 0 and isIdentifierByte(contents[prefix_start - 1])) : (prefix_start -= 1) {}
    const prefix = contents[prefix_start..prefix_end];
    const active_container_name = currentCompletionContainerName(contents, top_level.declarations.items, offset);

    var candidates = std.ArrayList(CompletionCandidate).init(allocator);
    defer candidates.deinit();
    for (top_level.declarations.items) |decl| {
        try appendDeclarationMemberCompletionItems(&candidates, contents, decl, offset, prefix);
    }
    for (top_level.declarations.items) |decl| {
        const declaration_name = decl.name orelse continue;
        if (active_container_name) |container_name| {
            if (std.mem.eql(u8, declaration_name, container_name)) continue;
        }
        if (!matchesCompletionPrefix(declaration_name, prefix)) continue;
        try appendOrReplaceCompletionCandidate(&candidates, .{
            .label = declaration_name,
            .kind = declarationCompletionKind(decl.kind),
            .detail = declarationCompletionDetail(decl.kind),
            .match_rank = completionMatchRank(declaration_name, prefix),
        });
    }

    std.mem.sort(CompletionCandidate, candidates.items, {}, lessThanCompletionCandidate);

    var completion_items_json = std.ArrayList(u8).init(allocator);
    defer completion_items_json.deinit();
    try completion_items_json.writer().writeAll("[");

    var wrote = false;
    for (candidates.items) |candidate| {
        try appendCompletionItemJson(allocator, &completion_items_json, candidate.label, candidate.kind, candidate.detail, &wrote);
    }

    try completion_items_json.writer().writeAll("]");
    return completion_items_json.toOwnedSlice();
}

const CompletionCandidate = struct {
    label: []const u8,
    kind: usize,
    detail: []const u8,
    match_rank: u8,
};

fn lessThanCompletionCandidate(_: void, a: CompletionCandidate, b: CompletionCandidate) bool {
    if (a.match_rank != b.match_rank) return a.match_rank < b.match_rank;

    const by_label = std.mem.order(u8, a.label, b.label);
    if (by_label != .eq) return by_label == .lt;
    return a.kind < b.kind;
}

fn appendMemberCompletionItemsInRange(
    candidates: *std.ArrayList(CompletionCandidate),
    contents: []const u8,
    start_index: usize,
    close_index: usize,
    mode: MemberScanMode,
    offset: usize,
    prefix: []const u8,
) !void {
    if (!offsetWithinMemberScanRange(offset, start_index, close_index)) return;

    const active_prefix_range = activeIdentifierRangeAtOffset(contents, offset);
    var scan_index = start_index;
    var scan_depth: usize = 0;

    while (scan_index < close_index) {
        const member_name_start = nextMemberNameStart(contents, scan_index, close_index, mode, &scan_depth) orelse break;
        const member_entry = scanMemberEntry(contents, member_name_start, close_index);

        try appendFilteredMemberCompletionCandidate(
            candidates,
            contents,
            start_index,
            active_prefix_range,
            member_name_start,
            member_entry.name_end,
            member_entry.name(contents),
            member_entry.after_name,
            close_index,
            prefix,
        );

        scan_index = member_entry.range_end;
    }
}

fn appendFilteredMemberCompletionCandidate(
    candidates: *std.ArrayList(CompletionCandidate),
    contents: []const u8,
    scan_start: usize,
    active_prefix_range: ?OffsetRange,
    name_start: usize,
    name_end: usize,
    name: []const u8,
    after_name: usize,
    close_index: usize,
    prefix: []const u8,
) !void {
    if (!matchesCompletionPrefix(name, prefix)) return;
    if (active_prefix_range != null and name_start == active_prefix_range.?.start and name_end == active_prefix_range.?.end) return;
    if (memberNameAlreadySeen(contents, scan_start, name_start, name)) return;
    try appendMemberCompletionCandidate(candidates, contents, name, after_name, close_index, prefix);
}

fn appendMemberCompletionCandidate(
    candidates: *std.ArrayList(CompletionCandidate),
    contents: []const u8,
    name: []const u8,
    after_name: usize,
    close_index: usize,
    prefix: []const u8,
) !void {
    const category = memberCategory(contents, after_name, close_index);
    try appendOrReplaceCompletionCandidate(candidates, .{
        .label = name,
        .kind = memberCompletionKind(category),
        .detail = memberCompletionDetail(category),
        .match_rank = completionMatchRank(name, prefix),
    });
}

fn activeIdentifierRangeAtOffset(contents: []const u8, offset: usize) ?OffsetRange {
    const range_end = if (offset <= contents.len) offset else contents.len;
    if (range_end == 0) return null;

    var range_start = range_end;
    while (range_start > 0 and isIdentifierByte(contents[range_start - 1])) : (range_start -= 1) {}
    if (range_start == range_end) return null;
    return .{ .start = range_start, .end = range_end };
}

fn offsetWithinMemberScanRange(offset: usize, start_index: usize, close_index: usize) bool {
    return offset + 1 >= start_index and offset <= close_index + 1;
}

fn memberSymbolKind(category: MemberCategory) usize {
    return switch (category) {
        .method => 6,
        .property => 7,
    };
}

fn memberWorkspaceSymbolPreferenceRank(category: MemberCategory) u8 {
    return switch (category) {
        .method => 0,
        .property => 4,
    };
}

fn memberCompletionKind(category: MemberCategory) usize {
    return switch (category) {
        .method => 2,
        .property => 10,
    };
}

fn memberCompletionDetail(category: MemberCategory) []const u8 {
    return switch (category) {
        .method => "method",
        .property => "property",
    };
}

fn completionMatchRank(name: []const u8, prefix: []const u8) u8 {
    return if (prefix.len == 0 or std.mem.startsWith(u8, name, prefix)) 0 else 1;
}

fn appendDeclarationMemberCompletionItems(
    candidates: *std.ArrayList(CompletionCandidate),
    contents: []const u8,
    decl: parser.Declaration,
    offset: usize,
    prefix: []const u8,
) !void {
    const range = declarationMemberScanRange(contents, decl) orelse return;
    try appendMemberCompletionItemsInRange(candidates, contents, range.start_index, range.close_index, range.mode, offset, prefix);
}

fn appendCompletionItemJson(
    allocator: std.mem.Allocator,
    body: *std.ArrayList(u8),
    label: []const u8,
    kind: usize,
    detail: []const u8,
    wrote: *bool,
) !void {
    _ = allocator;
    if (wrote.*) try body.writer().writeAll(",");
    try body.writer().writeAll("{\"label\":");
    try std.json.encodeJsonString(label, .{}, body.writer());
    try body.writer().print(",\"kind\":{d}", .{kind});
    try body.writer().writeAll(",\"data\":{\"label\":");
    try std.json.encodeJsonString(label, .{}, body.writer());
    try body.writer().print(",\"kind\":{d}", .{kind});
    try body.writer().writeAll(",\"detail\":");
    try std.json.encodeJsonString(detail, .{}, body.writer());
    try body.writer().writeAll("}}");
    wrote.* = true;
}

fn matchesCompletionPrefix(label: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0) return true;
    if (std.mem.startsWith(u8, label, prefix)) return true;
    if (prefix.len > label.len) return false;
    return std.ascii.eqlIgnoreCase(label[0..prefix.len], prefix);
}

fn appendOrReplaceCompletionCandidate(candidates: *std.ArrayList(CompletionCandidate), next: CompletionCandidate) !void {
    for (candidates.items, 0..) |candidate, index| {
        if (!std.mem.eql(u8, candidate.label, next.label)) continue;
        const next_priority = completionDetailPriority(next.detail);
        const current_priority = completionDetailPriority(candidate.detail);
        if (next.match_rank < candidate.match_rank or
            (next.match_rank == candidate.match_rank and
                (next_priority < current_priority or
                    (next_priority == current_priority and next.kind < candidate.kind))))
        {
            candidates.items[index] = next;
        }
        return;
    }
    try candidates.append(next);
}

fn completionDetailPriority(detail: []const u8) u8 {
    return if (std.mem.eql(u8, detail, "method"))
        0
    else if (std.mem.eql(u8, detail, "function"))
        1
    else if (std.mem.eql(u8, detail, "class"))
        2
    else if (std.mem.eql(u8, detail, "interface"))
        3
    else if (std.mem.eql(u8, detail, "property"))
        4
    else if (std.mem.eql(u8, detail, "variable"))
        5
    else if (std.mem.eql(u8, detail, "type"))
        6
    else if (std.mem.eql(u8, detail, "import"))
        7
    else if (std.mem.eql(u8, detail, "export"))
        8
    else
        9;
}

fn memberNameAlreadySeen(contents: []const u8, scan_start: usize, name_start: usize, name: []const u8) bool {
    var scan_index = scan_start;
    while (scan_index < name_start) {
        if (!isIdentifierByte(contents[scan_index])) {
            scan_index += 1;
            continue;
        }
        const start_index = scan_index;
        while (scan_index < name_start and isIdentifierByte(contents[scan_index])) : (scan_index += 1) {}
        if (std.mem.eql(u8, contents[start_index..scan_index], name)) return true;
    }
    return false;
}

fn currentCompletionContainerName(contents: []const u8, declarations: []const parser.Declaration, offset: usize) ?[]const u8 {
    for (declarations) |decl| {
        const container_name = decl.name orelse continue;
        switch (decl.kind) {
            .class_decl, .interface_decl, .type_decl => {},
            else => continue,
        }

        const range_end = declarationRangeEndOffset(contents, decl);
        if (offset >= decl.start.offset and offset <= range_end) return container_name;
    }
    return null;
}

fn topLevelDeclarationByName(declarations: []const parser.Declaration, symbol: []const u8) ?parser.Declaration {
    for (declarations) |decl| {
        const declaration_name = decl.name orelse continue;
        if (std.mem.eql(u8, declaration_name, symbol)) return decl;
    }
    return null;
}

fn buildCompletionResolveResultJson(allocator: std.mem.Allocator, params: std.json.Value) ![]u8 {
    if (params != .object) return error.InvalidRequest;

    const label_value = params.object.get("label") orelse return error.InvalidRequest;
    if (label_value != .string) return error.InvalidRequest;

    var completion_detail: []const u8 = "symbol";
    if (params.object.get("data")) |data_value| {
        if (data_value != .object) return error.InvalidRequest;
        if (data_value.object.get("detail")) |detail_value| {
            if (detail_value != .string) return error.InvalidRequest;
            completion_detail = detail_value.string;
        }
    }

    var resolved_completion_json = std.ArrayList(u8).init(allocator);
    defer resolved_completion_json.deinit();
    try resolved_completion_json.writer().writeAll("{\"label\":");
    try std.json.encodeJsonString(label_value.string, .{}, resolved_completion_json.writer());
    if (params.object.get("kind")) |kind_value| {
        if (kind_value == .integer) {
            try resolved_completion_json.writer().print(",\"kind\":{d}", .{kind_value.integer});
        }
    }
    try resolved_completion_json.writer().writeAll(",\"detail\":");
    try std.json.encodeJsonString(completion_detail, .{}, resolved_completion_json.writer());
    try resolved_completion_json.writer().writeAll(",\"documentation\":{\"kind\":\"markdown\",\"value\":");
    const documentation = try std.fmt.allocPrint(allocator, "{s} `{s}`", .{ completion_detail, label_value.string });
    defer allocator.free(documentation);
    try std.json.encodeJsonString(documentation, .{}, resolved_completion_json.writer());
    try resolved_completion_json.writer().writeAll("}}");
    return resolved_completion_json.toOwnedSlice();
}

fn buildSemanticTokensResultJson(allocator: std.mem.Allocator, document: []const u8, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "{\"data\":[]}");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    var semantic_tokens_json = std.ArrayList(u8).init(allocator);
    defer semantic_tokens_json.deinit();
    try semantic_tokens_json.writer().writeAll("{\"data\":[");

    var previous_line: usize = 0;
    var previous_start: usize = 0;
    var wrote = false;

    for (top_level.declarations.items) |decl| {
        const declaration_name = decl.name orelse continue;
        const token_type: usize = switch (decl.kind) {
            .class_decl => 0,
            .function_decl => 1,
            .interface_decl => 2,
            .type_decl => 3,
            .variable_stmt => 4,
            else => continue,
        };
        const name_start_position = offsetToLineCharacter(contents, declarationNameStartOffset(decl, declaration_name));
        const delta_line = if (!wrote) name_start_position.line else name_start_position.line - previous_line;
        const delta_start = if (!wrote or delta_line > 0) name_start_position.character else name_start_position.character - previous_start;

        if (wrote) try semantic_tokens_json.writer().writeAll(",");
        try semantic_tokens_json.writer().print("{d},{d},{d},{d},0", .{ delta_line, delta_start, declaration_name.len, token_type });
        wrote = true;
        previous_line = name_start_position.line;
        previous_start = name_start_position.character;
    }

    try semantic_tokens_json.writer().writeAll("]}");
    return semantic_tokens_json.toOwnedSlice();
}

fn buildSignatureHelpResultJson(allocator: std.mem.Allocator, request: TextDocumentPositionRequest, snapshots: *const DocumentSnapshotStore) ![]u8 {
    const maybe_contents = try loadDocumentContents(allocator, snapshots, request.document);
    const document_contents = maybe_contents orelse return allocator.dupe(u8, "null");
    defer document_contents.deinit(allocator);
    const contents = document_contents.slice();

    const offset = positionToOffset(contents, request.line, request.character) orelse return allocator.dupe(u8, "null");
    const call = findCallAtOffset(contents, offset) orelse return allocator.dupe(u8, "null");

    var top_level = try parser.parseTopLevel(allocator, contents);
    defer top_level.deinit(allocator);

    for (top_level.declarations.items) |decl| {
        if (decl.kind != .function_decl) continue;
        const function_name = decl.name orelse continue;
        if (!std.mem.eql(u8, function_name, call.function_name)) continue;

        var function_params = try extractFunctionParameters(allocator, contents, decl);
        defer {
            for (function_params.items) |param| allocator.free(param);
            function_params.deinit();
        }

        var signature_help_json = std.ArrayList(u8).init(allocator);
        defer signature_help_json.deinit();
        try signature_help_json.writer().writeAll("{\"signatures\":[{\"label\":");

        const signature_label = try buildFunctionSignatureLabel(allocator, function_name, function_params.items);
        defer allocator.free(signature_label);
        try std.json.encodeJsonString(signature_label, .{}, signature_help_json.writer());
        try signature_help_json.writer().writeAll(",\"parameters\":[");
        for (function_params.items, 0..) |param, index| {
            if (index > 0) try signature_help_json.writer().writeAll(",");
            try signature_help_json.writer().writeAll("{\"label\":");
            try std.json.encodeJsonString(param, .{}, signature_help_json.writer());
            try signature_help_json.writer().writeAll("}");
        }
        try signature_help_json.writer().writeAll("]}],\"activeSignature\":0,\"activeParameter\":");

        const active_parameter = if (function_params.items.len == 0) @as(usize, 0) else @min(call.active_parameter, function_params.items.len - 1);
        try signature_help_json.writer().print("{d}", .{active_parameter});
        try signature_help_json.writer().writeAll("}");
        return signature_help_json.toOwnedSlice();
    }

    return allocator.dupe(u8, "null");
}

const CallSite = struct {
    function_name: []const u8,
    active_parameter: usize,
};

fn findCallAtOffset(contents: []const u8, offset: usize) ?CallSite {
    if (contents.len == 0) return null;
    const search_end = @min(offset, contents.len);
    var paren_depth: usize = 0;
    var active_parameter_index: usize = 0;
    var scan_index: usize = search_end;

    while (scan_index > 0) {
        scan_index -= 1;
        const ch = contents[scan_index];

        if (ch == ')') {
            paren_depth += 1;
            continue;
        }
        if (ch == '(') {
            if (paren_depth == 0) {
                var function_name_end = scan_index;
                while (function_name_end > 0 and std.ascii.isWhitespace(contents[function_name_end - 1])) : (function_name_end -= 1) {}
                var function_name_start = function_name_end;
                while (function_name_start > 0 and isIdentifierByte(contents[function_name_start - 1])) : (function_name_start -= 1) {}
                if (function_name_start == function_name_end) return null;
                return .{
                    .function_name = contents[function_name_start..function_name_end],
                    .active_parameter = active_parameter_index,
                };
            }
            paren_depth -= 1;
            continue;
        }
        if (ch == ',' and paren_depth == 0) {
            active_parameter_index += 1;
        }
    }

    return null;
}

fn extractFunctionParameters(allocator: std.mem.Allocator, contents: []const u8, decl: parser.Declaration) !std.ArrayList([]u8) {
    var parameter_names = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (parameter_names.items) |param| allocator.free(param);
        parameter_names.deinit();
    }

    var scan_index = decl.end_offset;
    while (scan_index < contents.len and std.ascii.isWhitespace(contents[scan_index])) : (scan_index += 1) {}
    if (scan_index >= contents.len or contents[scan_index] != '(') return parameter_names;

    const open_index = scan_index;
    const close_index = findMatchingDelimiter(contents, open_index, '(', ')') orelse return parameter_names;
    const param_source = contents[open_index + 1 .. close_index];

    var segment_start: usize = 0;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var angle_depth: usize = 0;
    var in_single = false;
    var in_double = false;
    var in_template = false;
    var escaped = false;
    var source_index: usize = 0;

    while (source_index < param_source.len) : (source_index += 1) {
        const ch = param_source[source_index];

        if (in_single or in_double or in_template) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if ((in_single and ch == '\'') or (in_double and ch == '"') or (in_template and ch == '`')) {
                in_single = false;
                in_double = false;
                in_template = false;
            }
            continue;
        }

        switch (ch) {
            '\'' => in_single = true,
            '"' => in_double = true,
            '`' => in_template = true,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth > 0) brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            '<' => angle_depth += 1,
            '>' => {
                if (angle_depth > 0) angle_depth -= 1;
            },
            ',' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
                    try appendTrimmedParameter(allocator, &parameter_names, param_source[segment_start..source_index]);
                    segment_start = source_index + 1;
                }
            },
            else => {},
        }
    }

    try appendTrimmedParameter(allocator, &parameter_names, param_source[segment_start..]);
    return parameter_names;
}

fn appendTrimmedParameter(allocator: std.mem.Allocator, params: *std.ArrayList([]u8), raw: []const u8) !void {
    const trimmed = std.mem.trim(u8, raw, " \t\r\n");
    if (trimmed.len == 0) return;
    try params.append(try allocator.dupe(u8, trimmed));
}

fn findMatchingDelimiter(contents: []const u8, open_index: usize, open_ch: u8, close_ch: u8) ?usize {
    var delimiter_depth: usize = 0;
    var scan_index = open_index;
    var in_single = false;
    var in_double = false;
    var in_template = false;
    var escaped = false;

    while (scan_index < contents.len) : (scan_index += 1) {
        const ch = contents[scan_index];

        if (in_single or in_double or in_template) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if ((in_single and ch == '\'') or (in_double and ch == '"') or (in_template and ch == '`')) {
                in_single = false;
                in_double = false;
                in_template = false;
            }
            continue;
        }

        switch (ch) {
            '\'' => in_single = true,
            '"' => in_double = true,
            '`' => in_template = true,
            else => {},
        }

        if (ch == open_ch) {
            delimiter_depth += 1;
        } else if (ch == close_ch) {
            delimiter_depth -= 1;
            if (delimiter_depth == 0) return scan_index;
        }
    }

    return null;
}

fn buildFunctionSignatureLabel(allocator: std.mem.Allocator, name: []const u8, params: []const []const u8) ![]u8 {
    var signature_label_text = std.ArrayList(u8).init(allocator);
    defer signature_label_text.deinit();
    try signature_label_text.writer().print("{s}(", .{name});
    for (params, 0..) |param, index| {
        if (index > 0) try signature_label_text.writer().writeAll(", ");
        try signature_label_text.writer().writeAll(param);
    }
    try signature_label_text.writer().writeAll(")");
    return signature_label_text.toOwnedSlice();
}

fn extractCallArguments(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList([]u8) {
    var argument_texts = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (argument_texts.items) |arg| allocator.free(arg);
        argument_texts.deinit();
    }

    var segment_start: usize = 0;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var angle_depth: usize = 0;
    var in_single = false;
    var in_double = false;
    var in_template = false;
    var escaped = false;
    var source_index: usize = 0;

    while (source_index < source.len) : (source_index += 1) {
        const ch = source[source_index];

        if (in_single or in_double or in_template) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if ((in_single and ch == '\'') or (in_double and ch == '"') or (in_template and ch == '`')) {
                in_single = false;
                in_double = false;
                in_template = false;
            }
            continue;
        }

        switch (ch) {
            '\'' => in_single = true,
            '"' => in_double = true,
            '`' => in_template = true,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth > 0) brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            '<' => angle_depth += 1,
            '>' => {
                if (angle_depth > 0) angle_depth -= 1;
            },
            ',' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
                    try appendTrimmedParameter(allocator, &argument_texts, source[segment_start..source_index]);
                    segment_start = source_index + 1;
                }
            },
            else => {},
        }
    }

    try appendTrimmedParameter(allocator, &argument_texts, source[segment_start..]);
    return argument_texts;
}

fn parameterLabelName(param: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, param, " \t\r\n");
    const colon_index = std.mem.indexOfScalar(u8, trimmed, ':') orelse trimmed.len;
    const equals_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse trimmed.len;
    const stop = @min(colon_index, equals_index);
    return std.mem.trim(u8, trimmed[0..stop], " \t\r\n?");
}

const RgbaColor = struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

fn colorLiteralLength(contents: []const u8, hash_index: usize) ?usize {
    var length: usize = 0;
    var scan_index = hash_index + 1;
    while (scan_index < contents.len and length < 8 and isHexByte(contents[scan_index])) : (scan_index += 1) {
        length += 1;
    }
    if (length != 6 and length != 8) return null;
    if (scan_index < contents.len and isHexByte(contents[scan_index])) return null;
    return length;
}

fn isHexByte(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or
        (ch >= 'a' and ch <= 'f') or
        (ch >= 'A' and ch <= 'F');
}

fn parseHexColorLiteral(literal: []const u8) ?RgbaColor {
    if (literal.len != 6 and literal.len != 8) return null;

    const red = parseHexPair(literal[0..2]) orelse return null;
    const green = parseHexPair(literal[2..4]) orelse return null;
    const blue = parseHexPair(literal[4..6]) orelse return null;
    const alpha_byte: u8 = if (literal.len == 8) parseHexPair(literal[6..8]) orelse return null else 255;

    return .{
        .red = @as(f64, @floatFromInt(red)) / 255.0,
        .green = @as(f64, @floatFromInt(green)) / 255.0,
        .blue = @as(f64, @floatFromInt(blue)) / 255.0,
        .alpha = @as(f64, @floatFromInt(alpha_byte)) / 255.0,
    };
}

fn parseHexPair(pair: []const u8) ?u8 {
    if (pair.len != 2) return null;
    return std.fmt.parseUnsigned(u8, pair, 16) catch null;
}

fn colorToHexPresentation(allocator: std.mem.Allocator, color: RgbaColor) ![]u8 {
    const red = floatChannelToByte(color.red);
    const green = floatChannelToByte(color.green);
    const blue = floatChannelToByte(color.blue);
    const alpha = floatChannelToByte(color.alpha);

    if (alpha == 255) {
        return std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}", .{ red, green, blue });
    }
    return std.fmt.allocPrint(allocator, "#{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ red, green, blue, alpha });
}

fn floatChannelToByte(value: f64) u8 {
    const clamped = @max(@as(f64, 0), @min(@as(f64, 1), value));
    const rounded = @as(u16, @intFromFloat((clamped * 255.0) + 0.5));
    return @intCast(@min(rounded, 255));
}

fn jsonNumberToF64(value: std.json.Value) ?f64 {
    return switch (value) {
        .float => |float_value| float_value,
        .integer => |integer_value| @as(f64, @floatFromInt(integer_value)),
        .number_string => |number_text| std.fmt.parseFloat(f64, number_text) catch null,
        else => null,
    };
}

fn findNextUrlStart(contents: []const u8, start_index: usize) ?usize {
    const http_index = std.mem.indexOfPos(u8, contents, start_index, "http://");
    const https_index = std.mem.indexOfPos(u8, contents, start_index, "https://");
    return switch (http_index != null and https_index != null) {
        true => @min(http_index.?, https_index.?),
        false => http_index orelse https_index,
    };
}

fn findUrlEnd(contents: []const u8, start_index: usize) usize {
    var scan_index = start_index;
    while (scan_index < contents.len) : (scan_index += 1) {
        const ch = contents[scan_index];
        if (std.ascii.isWhitespace(ch) or ch == '"' or ch == '\'' or ch == '`' or ch == ')' or ch == ']' or ch == '}') break;
    }
    return scan_index;
}

fn resolveRelativeLinkTarget(allocator: std.mem.Allocator, document: []const u8, specifier: []const u8) ![]u8 {
    const base_dir = std.fs.path.dirname(document) orelse ".";
    if (std.mem.eql(u8, base_dir, ".")) {
        return try std.fmt.allocPrint(allocator, "file://{s}", .{specifier});
    }
    const path = try std.fs.path.join(allocator, &.{ base_dir, specifier });
    errdefer allocator.free(path);
    return try std.fmt.allocPrint(allocator, "file://{s}", .{path});
}

fn writeDocumentLinkJson(writer: anytype, contents: []const u8, start_offset: usize, end_offset: usize, target: []const u8) !void {
    try writer.writeAll("{\"range\":");
    try writeRangeFromOffsetsJson(writer, contents, start_offset, end_offset);
    try writer.writeAll(",\"target\":");
    try std.json.encodeJsonString(target, .{}, writer);
    try writer.writeAll("}");
}

fn positionToOffset(contents: []const u8, line_zero_based: usize, character_zero_based: usize) ?usize {
    const target_line = line_zero_based + 1;
    const target_column = character_zero_based + 1;

    var current_line: usize = 1;
    var current_column: usize = 1;
    var scan_index: usize = 0;
    while (scan_index < contents.len) : (scan_index += 1) {
        if (current_line == target_line and current_column == target_column) return scan_index;

        if (contents[scan_index] == '\n') {
            current_line += 1;
            current_column = 1;
        } else {
            current_column += 1;
        }
    }

    if (current_line == target_line and current_column == target_column) return contents.len;
    return null;
}

fn writeHoverLabelJson(writer: anytype, decl: parser.Declaration) !void {
    var hover_text = std.ArrayList(u8).init(std.heap.page_allocator);
    defer hover_text.deinit();

    try hover_text.writer().writeAll("```typescript\n");
    try writeHoverDeclarationSummaryJsonSource(hover_text.writer(), decl);
    try hover_text.writer().writeAll("\n```");
    try std.json.encodeJsonString(hover_text.items, .{}, writer);
}

fn writeHoverDeclarationSummaryJsonSource(writer: anytype, decl: parser.Declaration) !void {
    const contents = hover_summary_source_contents orelse return writer.writeAll("declaration");
    const summary_start = switch (decl.kind) {
        .class_decl => std.mem.indexOfPos(u8, contents, decl.start.offset, "class") orelse decl.start.offset,
        .interface_decl => std.mem.indexOfPos(u8, contents, decl.start.offset, "interface") orelse decl.start.offset,
        .type_decl => std.mem.indexOfPos(u8, contents, decl.start.offset, "type") orelse decl.start.offset,
        .function_decl => std.mem.indexOfPos(u8, contents, decl.start.offset, "function") orelse decl.start.offset,
        .variable_stmt => decl.start.offset,
        .import_stmt => decl.start.offset,
        .export_stmt => decl.start.offset,
    };
    if (summary_start >= contents.len) return writer.writeAll("declaration");

    const end_info = hoverSummaryEndOffset(contents, summary_start, decl.kind);
    const trimmed_summary = std.mem.trim(u8, contents[summary_start..end_info.end], " \t\r\n");
    if (trimmed_summary.len == 0) return writer.writeAll("declaration");

    var compact_summary = std.ArrayList(u8).init(std.heap.page_allocator);
    defer compact_summary.deinit();
    try writeCollapsedWhitespace(compact_summary.writer(), trimmed_summary);
    try compact_summary.writer().writeAll(end_info.suffix);
    try writer.writeAll(compact_summary.items);
}

fn writeHoverRawSnippetJson(writer: anytype, snippet: []const u8) !void {
    var hover_text = std.ArrayList(u8).init(std.heap.page_allocator);
    defer hover_text.deinit();
    try hover_text.writer().writeAll("```typescript\n");

    const trimmed = std.mem.trim(u8, snippet, " \t\r\n");
    var compact_snippet = std.ArrayList(u8).init(std.heap.page_allocator);
    defer compact_snippet.deinit();
    try writeCollapsedWhitespace(compact_snippet.writer(), trimmed);
    try hover_text.writer().writeAll(compact_snippet.items);

    try hover_text.writer().writeAll("\n```");
    try std.json.encodeJsonString(hover_text.items, .{}, writer);
}

var hover_summary_source_contents: ?[]const u8 = null;

const HoverSummaryEnd = struct {
    end: usize,
    suffix: []const u8 = "",
};

fn hoverSummaryEndOffset(contents: []const u8, start: usize, kind: parser.DeclarationKind) HoverSummaryEnd {
    var scan_index = start;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var angle_depth: usize = 0;
    var in_single = false;
    var in_double = false;
    var in_template = false;
    var escaped = false;

    while (scan_index < contents.len) : (scan_index += 1) {
        const ch = contents[scan_index];
        if (in_single or in_double or in_template) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (ch == '\\') {
                escaped = true;
                continue;
            }
            if ((in_single and ch == '\'') or (in_double and ch == '"') or (in_template and ch == '`')) {
                in_single = false;
                in_double = false;
                in_template = false;
            }
            continue;
        }

        switch (ch) {
            '\'' => in_single = true,
            '"' => in_double = true,
            '`' => in_template = true,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            '<' => {
                if (kind == .function_decl or kind == .class_decl or kind == .interface_decl) angle_depth += 1;
            },
            '>' => {
                if (angle_depth > 0) angle_depth -= 1;
            },
            ';' => {
                if (paren_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
                    return .{ .end = scan_index + 1 };
                }
            },
            '{' => {
                if (paren_depth == 0 and bracket_depth == 0 and angle_depth == 0) {
                    return .{
                        .end = scan_index,
                        .suffix = switch (kind) {
                            .function_decl => " {}",
                            .class_decl, .interface_decl => " { ... }",
                            .type_decl => " { ... }",
                            else => "",
                        },
                    };
                }
            },
            '\n' => {
                if (kind == .variable_stmt or kind == .import_stmt or kind == .export_stmt) {
                    return .{ .end = scan_index };
                }
            },
            else => {},
        }
    }

    return .{ .end = contents.len };
}

fn writeCollapsedWhitespace(writer: anytype, text: []const u8) !void {
    var pending_space = false;
    var wrote = false;
    for (text) |ch| {
        if (std.ascii.isWhitespace(ch)) {
            pending_space = wrote;
            continue;
        }
        if (pending_space) try writer.writeByte(' ');
        try writer.writeByte(ch);
        pending_space = false;
        wrote = true;
    }
}

fn identifierAtOffset(contents: []const u8, offset: usize) ?[]const u8 {
    if (contents.len == 0) return null;

    var identifier_start = if (offset < contents.len) offset else contents.len - 1;
    if (!isIdentifierByte(contents[identifier_start]) and identifier_start > 0 and isIdentifierByte(contents[identifier_start - 1])) {
        identifier_start -= 1;
    }
    if (!isIdentifierByte(contents[identifier_start])) return null;

    var identifier_left = identifier_start;
    while (identifier_left > 0 and isIdentifierByte(contents[identifier_left - 1])) : (identifier_left -= 1) {}

    var identifier_right = identifier_start + 1;
    while (identifier_right < contents.len and isIdentifierByte(contents[identifier_right])) : (identifier_right += 1) {}

    return contents[identifier_left..identifier_right];
}

fn isIdentifierByte(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch) or ch == '_' or ch == '$';
}

fn isSupportedSourceFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".ts") or
        std.mem.endsWith(u8, path, ".tsx") or
        std.mem.endsWith(u8, path, ".mts") or
        std.mem.endsWith(u8, path, ".cts");
}

const LineCharacter = struct {
    line: usize,
    character: usize,
};

fn offsetToLineCharacter(contents: []const u8, offset: usize) LineCharacter {
    var current_line: usize = 0;
    var current_character: usize = 0;
    var scan_index: usize = 0;
    while (scan_index < offset and scan_index < contents.len) : (scan_index += 1) {
        if (contents[scan_index] == '\n') {
            current_line += 1;
            current_character = 0;
        } else {
            current_character += 1;
        }
    }
    return .{ .line = current_line, .character = current_character };
}

fn writeLocationJson(writer: anytype, document: []const u8, start: LineCharacter, end: LineCharacter) !void {
    try writer.writeAll("{\"uri\":");
    try std.json.encodeJsonString(document, .{}, writer);
    try writer.writeAll(",\"range\":{\"start\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ start.line, start.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ end.line, end.character });
    try writer.writeAll("}}}");
}

fn writeTextEditJson(writer: anytype, start: LineCharacter, end: LineCharacter, new_text: []const u8) !void {
    try writer.writeAll("{\"range\":{\"start\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ start.line, start.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ end.line, end.character });
    try writer.writeAll("}},\"newText\":");
    try std.json.encodeJsonString(new_text, .{}, writer);
    try writer.writeAll("}");
}

fn writePrepareRenameJson(writer: anytype, start: LineCharacter, end: LineCharacter, placeholder: []const u8) !void {
    try writer.writeAll("{\"range\":{\"start\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ start.line, start.character });
    try writer.writeAll("},\"end\":{");
    try writer.print("\"line\":{d},\"character\":{d}", .{ end.line, end.character });
    try writer.writeAll("}},\"placeholder\":");
    try std.json.encodeJsonString(placeholder, .{}, writer);
    try writer.writeAll("}");
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

        const header_line = std.mem.trimRight(u8, line_buffer.items, "\r\n");
        if (header_line.len == 0) break;

        if (std.ascii.startsWithIgnoreCase(header_line, "Content-Length:")) {
            const content_length_text = std.mem.trim(u8, header_line["Content-Length:".len..], " \t");
            content_length = try std.fmt.parseUnsigned(usize, content_length_text, 10);
        }
    }

    const length = content_length orelse return null;
    const payload = try allocator.alloc(u8, length);
    errdefer allocator.free(payload);
    try reader.readNoEof(payload);
    return payload;
}

fn writeJsonRpcResult(writer: anytype, id: std.json.Value, result_json: []const u8) !void {
    var response_frame = std.ArrayList(u8).init(std.heap.page_allocator);
    defer response_frame.deinit();

    try response_frame.writer().writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(response_frame.writer(), id);
    try response_frame.writer().writeAll(",\"result\":");
    try response_frame.writer().writeAll(result_json);
    try response_frame.writer().writeAll("}");
    try writeFrame(writer, response_frame.items);
}

fn writeJsonRpcMethodNotFound(writer: anytype, id: std.json.Value, method: []const u8) !void {
    var error_message = std.ArrayList(u8).init(std.heap.page_allocator);
    defer error_message.deinit();
    try error_message.writer().print("Method not found: {s}", .{method});
    try writeJsonRpcError(writer, id, -32601, error_message.items);
}

fn writeJsonRpcError(writer: anytype, id: std.json.Value, code: i32, message: []const u8) !void {
    var error_frame = std.ArrayList(u8).init(std.heap.page_allocator);
    defer error_frame.deinit();

    try error_frame.writer().writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeJsonValue(error_frame.writer(), id);
    try error_frame.writer().print(",\"error\":{{\"code\":{d},\"message\":", .{code});
    try std.json.encodeJsonString(message, .{}, error_frame.writer());
    try error_frame.writer().writeAll("}}");
    try writeFrame(writer, error_frame.items);
}

fn writeJsonRpcErrorNull(writer: anytype, code: i32, message: []const u8) !void {
    var error_frame = std.ArrayList(u8).init(std.heap.page_allocator);
    defer error_frame.deinit();

    try error_frame.writer().writeAll("{\"jsonrpc\":\"2.0\",\"id\":null");
    try error_frame.writer().print(",\"error\":{{\"code\":{d},\"message\":", .{code});
    try std.json.encodeJsonString(message, .{}, error_frame.writer());
    try error_frame.writer().writeAll("}}");
    try writeFrame(writer, error_frame.items);
}

fn writeFrame(writer: anytype, body: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try writer.writeAll(body);
}

fn writeJsonValue(writer: anytype, value: std.json.Value) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |bool_value| try writer.writeAll(if (bool_value) "true" else "false"),
        .integer => |integer_value| try writer.print("{d}", .{integer_value}),
        .float => |float_value| try writer.print("{d}", .{float_value}),
        .number_string => |number_text| try writer.writeAll(number_text),
        .string => |string_value| try std.json.encodeJsonString(string_value, .{}, writer),
        else => try writer.writeAll("null"),
    }
}

test "lsp rejects non-stdio mode" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;

    var input = std.io.fixedBufferStream("");
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 1), exit_code);
    try std.testing.expectEqualStrings("only stdio is supported\n", response_bytes.items);
}

test "lsp stdio initialize shutdown exit lifecycle" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit_notification.len, exit_notification });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"result\":{\"capabilities\":{\"textDocumentSync\":1,\"hoverProvider\":true,\"definitionProvider\":true,\"declarationProvider\":true,\"typeDefinitionProvider\":true,\"implementationProvider\":true,\"foldingRangeProvider\":true,\"selectionRangeProvider\":true,\"linkedEditingRangeProvider\":true,\"inlayHintProvider\":true,\"colorProvider\":true,\"documentLinkProvider\":{\"resolveProvider\":false},\"codeLensProvider\":{\"resolveProvider\":false},\"documentFormattingProvider\":true,\"documentRangeFormattingProvider\":true,\"documentOnTypeFormattingProvider\":{\"firstTriggerCharacter\":\"\\n\",\"moreTriggerCharacter\":[]},\"documentSymbolProvider\":true,\"workspaceSymbolProvider\":true,\"completionProvider\":{\"resolveProvider\":true},\"referencesProvider\":true,\"renameProvider\":{\"prepareProvider\":true},\"codeActionProvider\":{\"codeActionKinds\":[\"source.organizeImports\"]},\"signatureHelpProvider\":{\"triggerCharacters\":[\"(\",\",\"]},\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":[\"class\",\"function\",\"interface\",\"type\",\"variable\"],\"tokenModifiers\":[]},\"full\":true}},\"serverInfo\":{\"name\":\"zts\",\"version\":\"0.0.0-dev\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":null") != null);
}

test "lsp stdio hover returns top-level declaration" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function greet() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const hover_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":17}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_request.len, hover_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit_notification.len, exit_notification });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```typescript\\nfunction greet() {}\\n```\"}}") != null);
}

test "lsp stdio hover returns null when nothing matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function greet() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const hover_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":0}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_request.len, hover_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit_notification.len, exit_notification });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":null") != null);
}

test "lsp stdio hover returns interface summary" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("interface Shape { area(): number; }\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const hover_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":11}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_request.len, hover_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit_notification.len, exit_notification });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```typescript\\ninterface Shape { ... }\\n```\"}}") != null);
}

test "lsp stdio hover returns class member summary" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {}
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const hover_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_request.len, hover_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit_notification.len, exit_notification });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```typescript\\ngreet(name: string): void {}\\n```\"}}") != null);
}

test "lsp stdio hover returns object type member summary" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const hover_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_request.len, hover_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```typescript\\nwidth: number;\\n```\"}}") != null);
}

test "lsp stdio definition returns top-level declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\greet();
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ definition_request.len, definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":21}}}") != null);
}

test "lsp stdio definition returns null when symbol is missing" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\run();
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":1}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ definition_request.len, definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":null") != null);
}

test "lsp stdio definition returns class member location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {}
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ definition_request.len, definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}}}") != null);
}

test "lsp stdio definition returns object type member location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ definition_request.len, definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}}}") != null);
}

test "lsp stdio definition returns class member declaration from usage" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {
            \\    this.greet(name);
            \\  }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":11}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ definition_request.len, definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}}}") != null);
}

test "lsp stdio definition returns object type member declaration from usage" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Shape {
            \\  area(): number;
            \\  area(value: number): number;
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ definition_request.len, definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":6}}}") != null);
}

test "lsp stdio declaration returns top-level declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\greet();
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const declaration_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/declaration\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ declaration_request.len, declaration_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":21}}}") != null);
}

test "lsp stdio declaration returns null when symbol is missing" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\run();
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const declaration_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/declaration\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":1}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ declaration_request.len, declaration_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":null") != null);
}

test "lsp stdio typeDefinition returns top-level type declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person { name: string }
            \\const user: Person = { name: "Ada" };
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":12}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":16}}}") != null);
}

test "lsp stdio typeDefinition returns null when no top-level type exists" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function greet() {}
            \\greet();
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":null") != null);
}

test "lsp stdio typeDefinition uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("interface DiskVersion {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"interface Person { name: string }\\nconst user: Person = { name: \\\"Ada\\\" };\\n\"}}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":12}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":16}}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "DiskVersion") == null);
}

test "lsp stdio typeDefinition returns member field type declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person {}
            \\type Shape = {
            \\  owner: Person;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":16}}}") != null);
}

test "lsp stdio typeDefinition returns method return type declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Shape {}
            \\class Greeter {
            \\  build(): Shape { return {} as Shape; }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":15}}}") != null);
}

test "lsp stdio typeDefinition returns parameter type declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person {}
            \\class Greeter {
            \\  greet(user: Person): void {}
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":9}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":16}}}") != null);
}

test "lsp stdio typeDefinition returns generic member type declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person {}
            \\interface Box<T> {}
            \\type Shape = {
            \\  owner: Box<Person>;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":1,\"character\":10},\"end\":{\"line\":1,\"character\":13}}}") != null);
}

test "lsp stdio typeDefinition returns nested generic return type declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface ApiResponse {}
            \\class Greeter {
            \\  build(): Promise<ApiResponse> { throw new Error("nope"); }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":21}}}") != null);
}

test "lsp stdio typeDefinition returns qualified member type declaration location" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person {}
            \\type Shape = {
            \\  owner: models.Person;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const type_definition_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/typeDefinition\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ type_definition_request.len, type_definition_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"uri\":\"main.ts\",\"range\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":16}}}") != null);
}

test "lsp stdio implementation returns matching classes" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person { name: string }
            \\class User implements Person {}
            \\class Admin extends Person {}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const implementation_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/implementation\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":12}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ implementation_request.len, implementation_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":6},\"end\":{\"line\":1,\"character\":10}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":6},\"end\":{\"line\":2,\"character\":11}") != null);
}

test "lsp stdio implementation returns empty when nothing matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person { name: string }
            \\class User {}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const implementation_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/implementation\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":12}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ implementation_request.len, implementation_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[]") != null);
}

test "lsp stdio implementation uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("interface DiskVersion {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"interface Person { name: string }\\nclass User implements Person {}\\n\"}}}";
    const implementation_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/implementation\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":12}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ implementation_request.len, implementation_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":6},\"end\":{\"line\":1,\"character\":10}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "DiskVersion") == null);
}

test "lsp stdio foldingRange returns top-level declaration blocks" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function greet() {
            \\  return "hi";
            \\}
            \\class Box {
            \\  value = 1;
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const folding_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/foldingRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ folding_request.len, folding_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "{\"startLine\":0,\"endLine\":2,\"kind\":\"region\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "{\"startLine\":3,\"endLine\":5,\"kind\":\"region\"}") != null);
}

test "lsp stdio foldingRange uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"function greet() {\\n  return \\\"hi\\\";\\n}\\n\"}}}";
    const folding = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/foldingRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ folding.len, folding });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "{\"startLine\":0,\"endLine\":2,\"kind\":\"region\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio selectionRange returns nested identifier line and declaration ranges" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {
            \\  return greet();
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const selection_range_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/selectionRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"positions\":[{\"line\":1,\"character\":10}]}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ selection_range_request.len, selection_range_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[{\"range\":{\"start\":{\"line\":1,\"character\":9},\"end\":{\"line\":1,\"character\":14}},\"parent\":{\"range\":{\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":17}},\"parent\":{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":2,\"character\":1}}}}}]") != null);
}

test "lsp stdio selectionRange uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"function renamed() {\\n  return renamed();\\n}\\n\"}}}";
    const selection_range_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/selectionRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"positions\":[{\"line\":1,\"character\":12}]}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ selection_range_request.len, selection_range_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":9},\"end\":{\"line\":1,\"character\":16}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":2,\"character\":1}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio selectionRange returns class member range between line and declaration" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {}
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const selection_range_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/selectionRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"positions\":[{\"line\":1,\"character\":4}]}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ selection_range_request.len, selection_range_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}},\"parent\":{\"range\":{\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":30}},\"parent\":{\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":30}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":2,\"character\":1}}") != null);
}

test "lsp stdio selectionRange returns object type member range between line and declaration" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const selection_range_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/selectionRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"positions\":[{\"line\":1,\"character\":3}]}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ selection_range_request.len, selection_range_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}},\"parent\":{\"range\":{\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":16}},\"parent\":{\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":16}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":2,\"character\":1}}") != null);
}

test "lsp stdio linkedEditingRange returns same-file lexical matches for top-level symbol" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function greet() {}
            \\greet();
            \\const alias = greet;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const linked_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/linkedEditingRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ linked_request.len, linked_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"ranges\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":9},\"end\":{\"line\":0,\"character\":14}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":5}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":14},\"end\":{\"line\":2,\"character\":19}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"wordPattern\":\"[A-Za-z0-9_$]+\"") != null);
}

test "lsp stdio linkedEditingRange uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"function renamed() {}\\nrenamed();\\nconst value = renamed;\\n\"}}}";
    const linked_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/linkedEditingRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ linked_request.len, linked_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":9},\"end\":{\"line\":0,\"character\":16}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":14},\"end\":{\"line\":2,\"character\":21}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio linkedEditingRange returns class member lexical matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {}
            \\  run() { this.greet("Ada"); }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const linked_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/linkedEditingRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ linked_request.len, linked_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"ranges\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":15},\"end\":{\"line\":2,\"character\":20}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"wordPattern\":\"[A-Za-z0-9_$]+\"") != null);
}

test "lsp stdio linkedEditingRange returns object type member lexical matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\  width: string;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const linked_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/linkedEditingRange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ linked_request.len, linked_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"ranges\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":2},\"end\":{\"line\":2,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"wordPattern\":\"[A-Za-z0-9_$]+\"") != null);
}

test "lsp stdio inlayHint returns parameter labels for same-file top-level function calls" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function greet(name: string, age: number) {}
            \\greet("Ada", 42);
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const inlay_hint_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/inlayHint\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":17}}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ inlay_hint_request.len, inlay_hint_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"position\":{\"line\":1,\"character\":6},\"label\":\"name:\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"position\":{\"line\":1,\"character\":13},\"label\":\"age:\"") != null);
}

test "lsp stdio inlayHint uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"function greet(name: string) {}\\ngreet(renamed);\\n\"}}}";
    const inlay_hint_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/inlayHint\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":15}}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ inlay_hint_request.len, inlay_hint_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"position\":{\"line\":1,\"character\":6},\"label\":\"name:\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio documentColor returns lexical hex color literals" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\const primary = "#336699";
            \\const overlay = "#11223344";
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const document_color_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentColor\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ document_color_request.len, document_color_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":17},\"end\":{\"line\":0,\"character\":24}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"red\":0.2,\"green\":0.4,\"blue\":0.6,\"alpha\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":17},\"end\":{\"line\":1,\"character\":26}") != null);
}

test "lsp stdio documentColor uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"const accent = \\\"#FF000080\\\";\\n\"}}}";
    const document_color_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentColor\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ document_color_request.len, document_color_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":25}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"red\":1,\"green\":0,\"blue\":0,\"alpha\":0.5019607843137255") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio colorPresentation returns hexadecimal presentation" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const color = \"#336699\";\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const color_presentation_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/colorPresentation\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"color\":{\"red\":0.2,\"green\":0.4,\"blue\":0.6,\"alpha\":1},\"range\":{\"start\":{\"line\":0,\"character\":15},\"end\":{\"line\":0,\"character\":24}}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ color_presentation_request.len, color_presentation_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[{\"label\":\"#336699\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"#336699\"") != null);
}

test "lsp stdio colorPresentation returns rgba hex when alpha is not opaque" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const color = \"#FF000080\";\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const color_presentation_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/colorPresentation\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"color\":{\"red\":1,\"green\":0,\"blue\":0,\"alpha\":0.5019607843137255},\"range\":{\"start\":{\"line\":0,\"character\":15},\"end\":{\"line\":0,\"character\":24}}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ color_presentation_request.len, color_presentation_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"#FF000080\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"#FF000080\"") != null);
}

test "lsp stdio documentLink returns lexical urls and relative imports" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\import { foo } from "./utils";
            \\const docs = "https://example.com/docs";
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const document_link_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentLink\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ document_link_request.len, document_link_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":14},\"end\":{\"line\":1,\"character\":38}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"target\":\"https://example.com/docs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":21},\"end\":{\"line\":0,\"character\":28}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"target\":\"file://./utils\"") != null);
}

test "lsp stdio documentLink uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"export * from \\\"../shared\\\";\\nconst api = \\\"http://localhost:3000/v1\\\";\\n\"}}}";
    const document_link_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentLink\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ document_link_request.len, document_link_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":15},\"end\":{\"line\":0,\"character\":24}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"target\":\"file://../shared\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":13},\"end\":{\"line\":1,\"character\":37}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"target\":\"http://localhost:3000/v1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio codeLens returns same-file lexical reference counts" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function greet() {}
            \\greet();
            \\greet();
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const code_lens_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/codeLens\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ code_lens_request.len, code_lens_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"title\":\"2 references\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"command\":\"zts.showReferences\"") != null);
}

test "lsp stdio codeLens uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"const renamed = 1;\\nconsole.log(renamed);\\nconsole.log(renamed);\\n\"}}}";
    const code_lens_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/codeLens\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ code_lens_request.len, code_lens_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"title\":\"2 references\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio codeLens returns class member lexical reference counts" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {}
            \\  run() {
            \\    this.greet("Ada");
            \\    this.greet("Lin");
            \\  }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const code_lens_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/codeLens\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ code_lens_request.len, code_lens_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"title\":\"2 references\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"command\":\"zts.showReferences\"") != null);
}

test "lsp stdio codeLens returns object type member lexical reference counts" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\  width: string;
            \\  height: number;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const code_lens_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/codeLens\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ code_lens_request.len, code_lens_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"title\":\"1 references\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":2},\"end\":{\"line\":2,\"character\":7}") != null);
}

test "lsp stdio documentSymbol returns top-level symbols" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet(name: string, age: number) {}
            \\class Box {
            \\  value = 1;
            \\  greet(name: string) {}
            \\}
            \\const value = 1;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const symbols_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ symbols_request.len, symbols_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\",\"kind\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"selectionRange\":{\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":21}},\"children\":[{\"name\":\"name\",\"kind\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"age\",\"kind\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"Box\",\"kind\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"selectionRange\":{\"start\":{\"line\":1,\"character\":6},\"end\":{\"line\":1,\"character\":9}},\"children\":[{\"name\":\"value\",\"kind\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\",\"kind\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\",\"kind\":6,\"range\":{\"start\":{\"line\":3,\"character\":2},\"end\":{\"line\":3,\"character\":24}},\"selectionRange\":{\"start\":{\"line\":3,\"character\":2},\"end\":{\"line\":3,\"character\":7}},\"children\":[{\"name\":\"name\",\"kind\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"value\",\"kind\":13") != null);
}

test "lsp stdio documentSymbol deduplicates duplicate top-level labels" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\const value = 1;
            \\type value = number;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const symbols_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ symbols_request.len, symbols_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"value\",\"kind\":13") != null);
    const first_value = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"value\"") orelse return error.TestUnexpectedResult;
    const second_value = std.mem.indexOfPos(u8, response_bytes.items, first_value + 1, "\"name\":\"value\"");
    try std.testing.expect(second_value == null);
}

test "lsp stdio documentSymbol expands interface and object type members" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Person {
            \\  name: string;
            \\  greet(name: string): void;
            \\}
            \\type Shape = {
            \\  width: number;
            \\  resize(next: number): Shape;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const symbols_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ symbols_request.len, symbols_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"Person\",\"kind\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"Person\",\"kind\":11,\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":3,\"character\":1}},\"selectionRange\":{\"start\":{\"line\":0,\"character\":10},\"end\":{\"line\":0,\"character\":16}},\"children\":[{\"name\":\"name\",\"kind\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\",\"kind\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\",\"kind\":6,\"range\":{\"start\":{\"line\":2,\"character\":2},\"end\":{\"line\":2,\"character\":28}},\"selectionRange\":{\"start\":{\"line\":2,\"character\":2},\"end\":{\"line\":2,\"character\":7}},\"children\":[{\"name\":\"name\",\"kind\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"Shape\",\"kind\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"Shape\",\"kind\":13,\"range\":{\"start\":{\"line\":4,\"character\":0},\"end\":{\"line\":7,\"character\":1}},\"selectionRange\":{\"start\":{\"line\":4,\"character\":5},\"end\":{\"line\":4,\"character\":10}},\"children\":[{\"name\":\"width\",\"kind\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"resize\",\"kind\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"resize\",\"kind\":6,\"range\":{\"start\":{\"line\":6,\"character\":2},\"end\":{\"line\":6,\"character\":30}},\"selectionRange\":{\"start\":{\"line\":6,\"character\":2},\"end\":{\"line\":6,\"character\":8}},\"children\":[{\"name\":\"next\",\"kind\":13") != null);
}

test "lsp stdio documentSymbol deduplicates duplicate member labels" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\  width: string;
            \\  height: number;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const symbols_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentSymbol\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ symbols_request.len, symbols_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"width\",\"kind\":7") != null);
    const first_width = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"width\"") orelse return error.TestUnexpectedResult;
    const second_width = std.mem.indexOfPos(u8, response_bytes.items, first_width + 1, "\"name\":\"width\"");
    try std.testing.expect(second_width == null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"height\",\"kind\":7") != null);
}

test "lsp stdio references returns declaration and same-file uses" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\greet();
            \\const x = greet;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const references_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ references_request.len, references_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":21}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":5}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":10},\"end\":{\"line\":2,\"character\":15}") != null);
}

test "lsp stdio references returns empty array when symbol is missing" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function greet() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const references_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":0}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ references_request.len, references_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[]") != null);
}

test "lsp stdio references returns class member declaration and uses" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {
            \\    greet(name);
            \\    this.greet(name);
            \\  }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const references_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ references_request.len, references_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":4},\"end\":{\"line\":2,\"character\":9}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":3,\"character\":9},\"end\":{\"line\":3,\"character\":14}") != null);
}

test "lsp stdio references returns object type member declaration and uses" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\  area(): number;
            \\  area(value: number): number;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const references_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/references\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ references_request.len, references_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":2},\"end\":{\"line\":2,\"character\":6}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":3,\"character\":2},\"end\":{\"line\":3,\"character\":6}") != null);
}

test "lsp stdio document highlight returns declaration and uses" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\greet();
            \\const x = greet;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const highlight_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentHighlight\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ highlight_request.len, highlight_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":21}},\"kind\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":5}},\"kind\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":10},\"end\":{\"line\":2,\"character\":15}},\"kind\":2") != null);
}

test "lsp stdio document highlight uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function diskVersion() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"export function greet() {}\\ngreet();\\nconst x = greet;\\n\"}}}";
    const highlight_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentHighlight\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ highlight_request.len, highlight_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":21}},\"kind\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":5}},\"kind\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "diskVersion") == null);
}

test "lsp stdio document highlight returns class member declaration and uses" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {
            \\    greet(name);
            \\    this.greet(name);
            \\  }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const highlight_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentHighlight\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ highlight_request.len, highlight_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}},\"kind\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":4},\"end\":{\"line\":2,\"character\":9}},\"kind\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":3,\"character\":9},\"end\":{\"line\":3,\"character\":14}},\"kind\":2") != null);
}

test "lsp stdio document highlight uses unsaved snapshot text for class member" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("class DiskVersion {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"class Greeter {\\n  greet(name: string): void {\\n    this.greet(name);\\n  }\\n}\\n\"}}}";
    const highlight_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentHighlight\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ highlight_request.len, highlight_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}},\"kind\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":9},\"end\":{\"line\":2,\"character\":14}},\"kind\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "DiskVersion") == null);
}

test "lsp stdio document highlight returns object type member declaration and uses" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Shape {
            \\  area(): number;
            \\  area(value: number): number;
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const highlight_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/documentHighlight\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ highlight_request.len, highlight_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":6}},\"kind\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":2},\"end\":{\"line\":2,\"character\":6}},\"kind\":2") != null);
}

test "lsp stdio codeAction returns organize imports edit" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\import z from "./z";
            \\import a from "./a";
            \\const value = 1;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const code_action_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/codeAction\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":2,\"character\":0}},\"context\":{\"only\":[\"source.organizeImports\"],\"diagnostics\":[]}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ code_action_request.len, code_action_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[{\"title\":\"Organize Imports\",\"kind\":\"source.organizeImports\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"import a from \\\"./a\\\";\\nimport z from \\\"./z\\\";\\n\"") != null);
}

test "lsp stdio codeAction uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("import disk from \"./disk\";\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"import z from \\\"./z\\\";\\nimport a from \\\"./a\\\";\\n\"}}}";
    const code_action_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/codeAction\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":0}},\"context\":{\"only\":[\"source.organizeImports\"],\"diagnostics\":[]}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ code_action_request.len, code_action_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"import a from \\\"./a\\\";\\nimport z from \\\"./z\\\";\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio formatting returns normalized text edit" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const value = 1;  \r\nlet name = \"Ada\";\t");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const formatting_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"options\":{\"tabSize\":2,\"insertSpaces\":true}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ formatting_request.len, formatting_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":18}},\"newText\":\"const value = 1;\\nlet name = \\\"Ada\\\";\\n\"}]") != null);
}

test "lsp stdio formatting uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"const value = 1;  \\r\\nlet name = \\\"Ada\\\";\\t\"}}}";
    const formatting_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"options\":{\"tabSize\":2,\"insertSpaces\":true}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ formatting_request.len, formatting_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"const value = 1;\\nlet name = \\\"Ada\\\";\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio rangeFormatting returns normalized text edit" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const value = 1;  \r\nlet name = \"Ada\";\t\nconst done = true;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const range_formatting_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/rangeFormatting\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":18}},\"options\":{\"tabSize\":2,\"insertSpaces\":true}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ range_formatting_request.len, range_formatting_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":18}},\"newText\":\"const value = 1;\\nlet name = \\\"Ada\\\";\"}]") != null);
}

test "lsp stdio rangeFormatting uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"const value = 1;  \\r\\nlet name = \\\"Ada\\\";\\t\\nconst done = true;\\n\"}}}";
    const range_formatting_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/rangeFormatting\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":18}},\"options\":{\"tabSize\":2,\"insertSpaces\":true}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ range_formatting_request.len, range_formatting_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"const value = 1;\\nlet name = \\\"Ada\\\";\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio onTypeFormatting returns normalized previous line edit" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const value = 1;  \n\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const on_type_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/onTypeFormatting\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":0},\"ch\":\"\\n\",\"options\":{\"tabSize\":2,\"insertSpaces\":true}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ on_type_request.len, on_type_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":1,\"character\":0}},\"newText\":\"const value = 1;\\n\"}]") != null);
}

test "lsp stdio onTypeFormatting uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("const disk = 1;\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"const value = 1;  \\n\\n\"}}}";
    const on_type_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/onTypeFormatting\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":0},\"ch\":\"\\n\",\"options\":{\"tabSize\":2,\"insertSpaces\":true}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ on_type_request.len, on_type_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"const value = 1;\\n\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "disk") == null);
}

test "lsp stdio rename returns workspace edit for same-file matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\greet();
            \\const x = greet;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const rename_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/rename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2},\"newName\":\"hello\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ rename_request.len, rename_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"changes\":{\"main.ts\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":0,\"character\":16},\"end\":{\"line\":0,\"character\":21}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":5}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":10},\"end\":{\"line\":2,\"character\":15}") != null);
}

test "lsp stdio rename returns empty workspace edit when symbol is missing" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function greet() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const rename_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/rename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":0},\"newName\":\"hello\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ rename_request.len, rename_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"changes\":{}}") != null);
}

test "lsp stdio rename returns workspace edit for class member matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {
            \\    greet(name);
            \\    this.greet(name);
            \\  }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const rename_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/rename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4},\"newName\":\"salute\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ rename_request.len, rename_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"salute\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":4},\"end\":{\"line\":2,\"character\":9}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":3,\"character\":9},\"end\":{\"line\":3,\"character\":14}") != null);
}

test "lsp stdio rename returns workspace edit for object type member matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Shape {
            \\  area(): number;
            \\  area(value: number): number;
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const rename_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/rename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":3},\"newName\":\"measure\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ rename_request.len, rename_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"newText\":\"measure\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":6}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"start\":{\"line\":2,\"character\":2},\"end\":{\"line\":2,\"character\":6}") != null);
}

test "lsp stdio prepareRename returns range and placeholder" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\greet();
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const prepare_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/prepareRename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ prepare_request.len, prepare_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"range\":{\"start\":{\"line\":1,\"character\":0},\"end\":{\"line\":1,\"character\":5}},\"placeholder\":\"greet\"}") != null);
}

test "lsp stdio prepareRename returns class member range and placeholder" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {
            \\    this.greet(name);
            \\  }
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const prepare_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/prepareRename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ prepare_request.len, prepare_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}},\"placeholder\":\"greet\"}") != null);
}

test "lsp stdio prepareRename returns object type member range and placeholder" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\  height: number;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const prepare_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/prepareRename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ prepare_request.len, prepare_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":7}},\"placeholder\":\"width\"}") != null);
}

test "lsp stdio prepareRename returns null when symbol is missing" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function greet() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const prepare_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/prepareRename\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":0}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ prepare_request.len, prepare_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":null") != null);
}

test "lsp stdio workspace symbol returns matching symbols across files" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\class Greeter {}
            \\
        );
    }
    {
        var source_file = try temp.dir.createFile("src/lib/util.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export const helper = 1;
            \\export function helperTool() {}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"help\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"helper\",\"kind\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"helperTool\",\"kind\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\"") == null);
}

test "lsp stdio workspace symbol falls back to case-insensitive top-level matching" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function helperTool() {}
            \\export const sideValue = 1;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"HELP\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"helperTool\",\"kind\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"sideValue\"") == null);
}

test "lsp stdio workspace symbol prefers case-sensitive matches over fallback matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export const helper = 1;
            \\export function HelpDesk() {}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"help\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const helper_index = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"helper\"") orelse return error.TestUnexpectedResult;
    const help_desk_index = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"HelpDesk\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(helper_index < help_desk_index);
}

test "lsp stdio workspace symbol empty query returns discovered symbols" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\class Greeter {}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\",\"kind\":12") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"Greeter\",\"kind\":5") != null);
}

test "lsp stdio workspace symbol deduplicates duplicate top-level labels within a file" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\const value = 1;
            \\type value = number;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"val\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"value\",\"kind\":13") != null);
    const first_value = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"value\"") orelse return error.TestUnexpectedResult;
    const second_value = std.mem.indexOfPos(u8, response_bytes.items, first_value + 1, "\"name\":\"value\"");
    try std.testing.expect(second_value == null);
}

test "lsp stdio workspace symbol returns matching member symbols across files" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet() {}
            \\}
            \\
        );
    }
    {
        var source_file = try temp.dir.createFile("src/lib/types.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  grow: number;
            \\  greet(next: number): void;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"gre\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"greet\",\"containerName\":\"Greeter\",\"kind\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"grow\"") == null);
}

test "lsp stdio workspace symbol falls back to case-insensitive member matching" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Shape {
            \\  helper(next: number): void;
            \\  sideWidth: number;
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"HELP\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"helper\",\"containerName\":\"Shape\",\"kind\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"sideWidth\"") == null);
}

test "lsp stdio workspace symbol results are sorted by file path" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src/lib");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet() {}
            \\}
            \\
        );
    }
    {
        var source_file = try temp.dir.createFile("src/lib/types.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  greet(next: number): void;
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"gre\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const lib_index = std.mem.indexOf(u8, response_bytes.items, "\"uri\":\"src/lib/types.ts\"") orelse return error.TestUnexpectedResult;
    const main_index = std.mem.indexOf(u8, response_bytes.items, "\"uri\":\"src/main.ts\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(lib_index < main_index);
}

test "lsp stdio workspace symbol results are sorted by name within a file" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\const zebra = 1;
            \\function alpha() {}
            \\class middle {}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const alpha_index = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"alpha\"") orelse return error.TestUnexpectedResult;
    const middle_index = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"middle\"") orelse return error.TestUnexpectedResult;
    const zebra_index = std.mem.indexOf(u8, response_bytes.items, "\"name\":\"zebra\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(alpha_index < middle_index);
    try std.testing.expect(middle_index < zebra_index);
}

test "lsp stdio workspace symbol empty query includes member symbols" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    try temp.dir.makePath("src");
    {
        var source_file = try temp.dir.createFile("src/main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\interface Shape {
            \\  width: number;
            \\  write(next: number): void;
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const workspace_symbol_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"workspace/symbol\",\"params\":{\"query\":\"\"}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ workspace_symbol_request.len, workspace_symbol_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"Shape\",\"kind\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"width\",\"containerName\":\"Shape\",\"kind\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"name\":\"write\",\"containerName\":\"Shape\",\"kind\":6") != null);
}

test "lsp stdio completion returns prefix-matching top-level declarations" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\class Greeter {}
            \\const value = 1;
            \\gre
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"greet\",\"kind\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"value\"") == null);
    const greet_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"greet\"") orelse return error.TestUnexpectedResult;
    const greeter_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"Greeter\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(greet_index < greeter_index);
}

test "lsp stdio completion falls back to case-insensitive top-level prefix matching" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\class valueBox {}
            \\GRE
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"greet\",\"kind\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"valueBox\"") == null);
}

test "lsp stdio completion without prefix returns top-level declarations" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\export function greet() {}
            \\class Greeter {}
            \\const value = 1;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":0}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"greet\",\"kind\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"Greeter\",\"kind\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"value\",\"kind\":6") != null);
}

test "lsp stdio completion prefers case-sensitive prefix matches over fallback matches" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function Greeter() {}
            \\function greet() {}
            \\gre
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const greet_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"greet\"") orelse return error.TestUnexpectedResult;
    const greeter_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"Greeter\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(greet_index < greeter_index);
}

test "lsp stdio top-level completion results are sorted by label" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\const zebra = 1;
            \\function alpha() {}
            \\class middle {}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":0}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const alpha_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"alpha\"") orelse return error.TestUnexpectedResult;
    const middle_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"middle\"") orelse return error.TestUnexpectedResult;
    const zebra_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"zebra\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(alpha_index < middle_index);
    try std.testing.expect(middle_index < zebra_index);
}

test "lsp stdio completion returns class member candidates for in-class prefix" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {
            \\  greet(name: string): void {}
            \\  grow = 1;
            \\  gr
            \\}
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"greet\",\"kind\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"detail\":\"method\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"grow\",\"kind\":10") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"detail\":\"property\"") != null);
}

test "lsp stdio completion returns object type member candidates for in-type prefix" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  width: number;
            \\  write(next: number): void;
            \\  w
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"width\",\"kind\":10") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"write\",\"kind\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"w\"") == null);
}

test "lsp stdio member completion results are sorted by label" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\type Shape = {
            \\  zebra: number;
            \\  alpha(next: number): void;
            \\  
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const alpha_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"alpha\"") orelse return error.TestUnexpectedResult;
    const zebra_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"zebra\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(alpha_index < zebra_index);
}

test "lsp stdio completion sorts member and top-level candidates together" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function apple() {}
            \\type Shape = {
            \\  alpha: number;
            \\  
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const alpha_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"alpha\"") orelse return error.TestUnexpectedResult;
    const apple_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"apple\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"Shape\"") == null);
    try std.testing.expect(alpha_index < apple_index);
}

test "lsp stdio completion prefers member candidate over duplicate top-level label" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\const value = 1;
            \\type Shape = {
            \\  value: number;
            \\  va
            \\};
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":4}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const property_index = std.mem.indexOf(u8, response_bytes.items, "\"label\":\"value\",\"kind\":10") orelse return error.TestUnexpectedResult;
    try std.testing.expect(property_index != std.math.maxInt(usize));
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"value\",\"kind\":6") == null);
}

test "lsp stdio completion deduplicates duplicate top-level labels" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\const value = 1;
            \\type value = number;
            \\va
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":2,\"character\":2}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"value\",\"kind\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"detail\":\"variable\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"detail\":\"type\"") == null);
}

test "lsp stdio completion resolve returns detail and documentation" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const resolve_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"completionItem/resolve\",\"params\":{\"label\":\"greet\",\"kind\":3,\"data\":{\"label\":\"greet\",\"kind\":3,\"detail\":\"function\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ resolve_request.len, resolve_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"label\":\"greet\",\"kind\":3,\"detail\":\"function\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"documentation\":{\"kind\":\"markdown\",\"value\":\"function `greet`\"}") != null);
}

test "lsp stdio semantic tokens returns top-level declaration tokens" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\class Greeter {}
            \\function greet() {}
            \\interface Shape {}
            \\type Name = string;
            \\const value = 1;
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const semantic_tokens_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/semanticTokens/full\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ semantic_tokens_request.len, semantic_tokens_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":[\"class\",\"function\",\"interface\",\"type\",\"variable\"],\"tokenModifiers\":[]},\"full\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"data\":[0,6,7,0,0,1,9,5,1,0,1,10,5,2,0,1,5,4,3,0,1,6,5,4,0]}}") != null);
}

test "lsp stdio signature help returns same-file function signature" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll(
            \\function greet(name: string, times = 1) {}
            \\greet("Ada", 
            \\
        );
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const signature_help_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/signatureHelp\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":12}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ signature_help_request.len, signature_help_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"signatures\":[{\"label\":\"greet(name: string, times = 1)\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"parameters\":[{\"label\":\"name: string\"},{\"label\":\"times = 1\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"activeSignature\":0,\"activeParameter\":1") != null);
}

test "lsp stdio signature help uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("function diskVersion() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"function greet(name: string, times = 1) {}\\ngreet(\\\"Ada\\\", \\n\"}}}";
    const signature_help_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/signatureHelp\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":1,\"character\":12}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ signature_help_request.len, signature_help_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"signatures\":[{\"label\":\"greet(name: string, times = 1)\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "diskVersion") == null);
}

test "lsp stdio hover uses didOpen and didChange snapshots" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function diskVersion() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"export function greet() {}\\n\"}}}";
    const hover_open_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":17}}}";
    const did_change_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"contentChanges\":[{\"text\":\"export function renamed() {}\\n\"}]}}";
    const hover_change_request = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":17}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_open_request.len, hover_open_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_change_notification.len, did_change_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_change_request.len, hover_change_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```typescript\\nfunction greet() {}\\n```\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":3,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```typescript\\nfunction renamed() {}\\n```\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "diskVersion") == null);
}

test "lsp stdio didClose falls back to disk contents" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function diskVersion() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"export function memoryVersion() {}\\n\"}}}";
    const did_close_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"}}}";
    const hover_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":0,\"character\":17}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_close_notification.len, did_close_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ hover_request.len, hover_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"```typescript\\nfunction diskVersion() {}\\n```\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "memoryVersion") == null);
}

test "lsp stdio completion uses unsaved snapshot text" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();

    var previous_cwd = try std.fs.cwd().openDir(".", .{});
    defer previous_cwd.close();
    try temp.dir.setAsCwd();
    defer previous_cwd.setAsCwd() catch {};

    {
        var source_file = try temp.dir.createFile("main.ts", .{});
        defer source_file.close();
        try source_file.writeAll("export function diskVersion() {}\n");
    }

    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}";
    const did_open_notification = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\",\"text\":\"export function greet() {}\\nclass Greeter {}\\nconst value = 1;\\nren\\n\"}}}";
    const completion_request = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file://main.ts\"},\"position\":{\"line\":3,\"character\":3}}}";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ initialize.len, initialize });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ did_open_notification.len, did_open_notification });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ completion_request.len, completion_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"greet\",\"kind\":3") == null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"Greeter\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"label\":\"value\"") == null);
}

test "lsp stdio returns parse error for invalid json frame" {
    var parsed = cli_types.ParsedArgs.init(std.testing.allocator);
    defer parsed.deinit();
    parsed.command = .lsp;
    try parsed.passthrough.append("--stdio");

    const invalid_request = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",";
    const shutdown = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}";
    const exit = "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}";

    var input_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer input_bytes.deinit();
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ invalid_request.len, invalid_request });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ shutdown.len, shutdown });
    try input_bytes.writer().print("Content-Length: {d}\r\n\r\n{s}", .{ exit.len, exit });
    var input = std.io.fixedBufferStream(input_bytes.items);
    var response_bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer response_bytes.deinit();

    const exit_code = try run(&parsed, input.reader(), response_bytes.writer());
    try std.testing.expectEqual(@as(u8, 0), exit_code);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, response_bytes.items, "\"id\":2,\"result\":null") != null);
}
