const std = @import("std");

/// Call hierarchy types

/// Call item in call hierarchy
pub const CallHierarchyItem = struct {
    name: []const u8,
    kind: SymbolKind,
    uri: []const u8,
    range: Range,
    selection_range: Range,
    data: ?[]u8 = null,
};

/// Call hierarchy incoming call
pub const CallHierarchyIncomingCall = struct {
    from: CallHierarchyItem,
    from_ranges: []Range,
};

/// Call hierarchy outgoing call
pub const CallHierarchyOutgoingCall = struct {
    to: CallHierarchyItem,
    from_ranges: []Range,
};

/// Range
pub const Range = struct {
    start: Position,
    end: Position,
};

/// Position
pub const Position = struct {
    line: u32,
    character: u32,
};

/// Symbol kind (from symbol.zig)
pub const SymbolKind = enum {
    file,
    module,
    namespace,
    package,
    class,
    enum_,
    interface,
    type_parameter,
    string,
    function,
    variable,
    const,
    method,
    get,
    set,
};

/// Semantic tokens types
pub const SemanticTokenTypes = enum {
    comment,
    keyword,
    string,
    number,
    regexp,
    operator,
    namespace,
    type,
    class,
    enum_,
    interface,
    type_parameter,
    function,
    variable,
    parameter,
    property,
    label,
};

/// Semantic token modifiers
pub const SemanticTokenModifiers = enum {
    declaration,
    definition,
    readonly,
    static,
    deprecated,
    abstract,
    async,
    modification,
};

/// Inlay hint
pub const InlayHint = struct {
    position: Position,
    label: []const u8,
    kind: InlayHintKind,
    text_edits: ?[]TextEdit,
};

/// Inlay hint kind
pub const InlayHintKind = enum {
    type,
    parameter,
};

/// Text edit
pub const TextEdit = struct {
    range: Range,
    new_text: []const u8,
};

/// Linked editing ranges
pub const LinkedEditingRanges = struct {
    ranges: []Range,
    word_pattern: ?[]const u8,
};
