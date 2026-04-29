const std = @import("std");

/// Refactor kind
pub const RefactorKind = struct {
    name: []const u8,
    description: []const u8,
};

/// Refactor action
pub const RefactorAction = struct {
    name: []const u8,
    description: []const u8,
    kind: []const u8,
};

/// Code fix kind
pub const CodeFixKind = struct {
    code: u32,
    message: []const u8,
};

/// Code action
pub const CodeAction = struct {
    description: []const u8,
    changes: []FileCodeChange,
    command: ?Command = null,
    is_global: bool = false,
};

/// File code change
pub const FileCodeChange = struct {
    file_name: []const u8,
    text_changes: []TextChange,
    is_new_file: bool = false,
};

/// Text change
pub const TextChange = struct {
    span: TextSpan,
    new_text: []const u8,
};

/// Text span
pub const TextSpan = struct {
    start: u32,
    length: u32,
};

/// Command
pub const Command = struct {
    name: []const u8,
    arguments: ?[]u8 = null,
};
