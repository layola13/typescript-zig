const std = @import("std");

/// Language Server Protocol message types

/// Request message
pub const RequestMessage = struct {
    id: ?RequestId,
    method: []const u8,
    params: ?[]u8 = null,
};

/// Response message
pub const ResponseMessage = struct {
    id: RequestId,
    result: ?[]u8 = null,
    error: ?ResponseError = null,
};

/// Response error
pub const ResponseError = struct {
    code: i32,
    message: []const u8,
    data: ?[]u8 = null,
};

/// Notification message
pub const NotificationMessage = struct {
    method: []const u8,
    params: ?[]u8 = null,
};

/// Request ID
pub const RequestId = union(enum) {
    number: i32,
    string: []const u8,
};

/// Initialize request params
pub const InitializeParams = struct {
    process_id: ?i32,
    root_uri: ?[]const u8,
    initialization_options: ?[]u8,
    capabilities: ClientCapabilities,
    trace: []const u8,
    workspace_folders: ?[]WorkspaceFolder,
};

/// Client capabilities
pub const ClientCapabilities = struct {
    workspace: ?WorkspaceClientCapabilities,
    text_document: ?TextDocumentClientCapabilities,
    window: ?WindowClientCapabilities,
};

/// Workspace client capabilities
pub const WorkspaceClientCapabilities = struct {
    apply_edit: bool = false,
    workspace_edit: bool = false,
    diagnostics: bool = false,
};

/// Text document client capabilities
pub const TextDocumentClientCapabilities = struct {
    synchronization: ?TextDocumentSyncClientCapabilities,
    hover: ?HoverClientCapabilities,
    completion: ?CompletionClientCapabilities,
};

/// Hover client capabilities
pub const HoverClientCapabilities = struct {
    dynamic_registration: bool = false,
};

/// Completion client capabilities
pub const CompletionClientCapabilities = struct {
    dynamic_registration: bool = false,
    completion_item: ?CompletionItemCapabilities,
};

/// Completion item capabilities
pub const CompletionItemCapabilities = struct {
    snippet_support: bool = false,
    commit_characters_support: bool = false,
};

/// Text document sync options
pub const TextDocumentSyncClientCapabilities = struct {
    dynamic_registration: bool = false,
};

/// Window client capabilities
pub const WindowClientCapabilities = struct {
    work_done_progress: bool = false,
};

/// Workspace folder
pub const WorkspaceFolder = struct {
    uri: []const u8,
    name: []const u8,
};
