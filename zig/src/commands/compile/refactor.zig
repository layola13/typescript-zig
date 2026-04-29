const std = @import("std");

/// Refactoring kinds
pub const RefactorKind = struct {
    kind: []const u8,
};

/// Refactor action
pub const RefactorAction = struct {
    name: []const u8,
    description: []const u8,
    kind: []const u8,
};

/// Applicable refactor
pub const ApplicableRefactor = struct {
    name: []const u8,
    description: []const u8,
    actions: []RefactorAction,
};

/// File specific edits
pub const FileTextChanges = struct {
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

/// Refactor edit info
pub const RefactorEditInfo = struct {
    edits: []FileTextChanges,
    rename_filename: ?[]const u8,
    rename_location: ?TextSpan,
};

/// Code action kind
pub const CodeActionKind = struct {
    kind: []const u8,
};

/// Common code action kinds
pub const CodeActionKinds = struct {
    empty: CodeActionKind,
    quick_fix: CodeActionKind,
    refactor: CodeActionKind,
    refactor_extract: CodeActionKind,
    refactor_inline: CodeActionKind,
    refactor_rewrite: CodeActionKind,
    source: CodeActionKind,
    source_add_missing_imports: CodeActionKind,
    source_fix_all: CodeActionKind,
    source_format: CodeActionKind,
    source_organize_imports: CodeActionKind,
};

pub const default_code_action_kinds = CodeActionKinds{
    .empty = .{ .kind = "" },
    .quick_fix = .{ .kind = "quickfix" },
    .refactor = .{ .kind = "refactor" },
    .refactor_extract = .{ .kind = "refactor.extract" },
    .refactor_inline = .{ .kind = "refactor.inline" },
    .refactor_rewrite = .{ .kind = "refactor.rewrite" },
    .source = .{ .kind = "source" },
    .source_add_missing_imports = .{ .kind = "source.addMissingImports" },
    .source_fix_all = .{ .kind = "source.fixAll" },
    .source_format = .{ .kind = "source.organizeImports" },
    .source_organize_imports = .{ .kind = "source.organizeImports" },
};
