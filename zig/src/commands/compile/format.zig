const std = @import("std");

/// Find references request
pub const FindReferencesRequest = struct {
    file: []const u8,
    position: u32,
};

/// Find references result
pub const FindReferencesResult = struct {
    refs: []ReferencesItem,
};

/// References item
pub const ReferencesItem = struct {
    file: []const u8,
    start: u32,
    length: u32,
    is_definition: bool,
    is_in_string: bool,
};

/// Rename request
pub const RenameRequest = struct {
    file: []const u8,
    position: u32,
    find_in_strings: bool = false,
    find_in_comments: bool = false,
};

/// Rename result
pub const RenameResult = struct {
    info: RenameInfo,
    locations: []RenameTextSpan,
};

/// Rename info
pub const RenameInfo = struct {
    canRename: bool,
    localized_error_message: ?[]const u8 = null,
    display_name: []const u8,
    full_display_name: []const u8,
    kind: SymbolKind,
    kind_modifiers: SymbolKindModifiers = .{},
};

/// Rename text span
pub const RenameTextSpan = struct {
    text_span: TextSpan,
    file: []const u8,
};

/// Text span
pub const TextSpan = struct {
    start: u32,
    length: u32,
};

/// Symbol kind
pub const SymbolKind = enum {
    file,
    module,
    namespace,
    package,
    class,
    enum,
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

/// Symbol kind modifiers
pub const SymbolKindModifiers = struct {
    declaration: bool = false,
    readonly: bool = false,
    static: bool = false,
    private: bool = false,
    protected: bool = false,
    public: bool = false,
};

/// Format document range request
pub const FormatRequest = struct {
    file: []const u8,
    start: u32,
    end: u32,
    options: FormatOptions,
};

/// Format options
pub const FormatOptions = struct {
    tab_size: u32 = 4,
    insert_space: bool = true,
    indent_style: IndentStyle = .spaces,
    new_line_character: []const u8 = "\n",
};

/// Indent style
pub const IndentStyle = enum {
    none,
    block,
    maintained,
    spaces,
    tab,
};

/// Format on key request
pub const FormatOnKeyRequest = struct {
    file: []const u8,
    key: []const u8,
    options: FormatOptions,
};
