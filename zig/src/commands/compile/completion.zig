const std = @import("std");
const source = @import("source_file.zig");

/// Completion kind
pub const CompletionKind = enum {
    warning,
    object_property,
    property_access,
    member_set,
    string,
    type,
    alert,
    element,
    method,
    keyword,
};

/// Completion trigger kind
pub const CompletionTriggerKind = enum {
    invok
    word,
    trigger_character,
    trigger_for_incompleteCompletions,
};

/// Completion entry
pub const CompletionEntry = struct {
    name: []const u8,
    kind: CompletionKind,
    kind_modifiers: CompletionKindModifiers = .{},
    sort_text: []const u8,
    insert_text: ?[]const u8 = null,
    is_relevant: bool = false,
    has_action: bool = false,
};

/// Completion kind modifiers
pub const CompletionKindModifiers = struct {
    deprecated: bool = false,
    is_color: bool = false,
    optional: bool = false,
    state: bool = false,
    priority: bool = false,
};

/// Completion details (for resolve)
pub const CompletionDetails = struct {
    name: []const u8,
    kind: CompletionKind,
    kind_modifiers: CompletionKindModifiers = .{},
    display_parts: []SymbolDisplayPart,
    documentation: ?[]SymbolDisplayPart,
    tags: []CompletionTag,
};

/// Symbol display part (reused from hover.zig)
pub const SymbolDisplayPart = struct {
    text: []const u8,
    kind: SymbolDisplayPartKind,
};

pub const SymbolDisplayPartKind = enum {
    line_break,
    space,
    text,
    keyword,
    punctuation,
};

/// Completion tag
pub const CompletionTag = enum {
    deprecated,
};

/// Completions for class members
pub const ClassMemberCompletionEntry = struct {
    entry: CompletionEntry,
    is_inherited: bool = false,
    is_spread: bool = false,
    symbol: *anyopaque,
    origin: ClassMemberOrigin,
};

/// Origin of class member completion
pub const ClassMemberOrigin = enum {
    inheritance,
    spreads,
    local_origin,
};

/// Organize imports result
pub const OrganizeImportsResult = struct {
    changes: []FileTextChanges,
};

/// File text changes
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

/// Add completions for imports
pub const AddToScopeResult = struct {
    symbols: []Symbol,
    is_new: bool,
};

/// Symbol
pub const Symbol = struct {
    name: []const u8,
    flags: u32,
};
