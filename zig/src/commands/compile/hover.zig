const std = @import("std");
const source = @import("source_file.zig");

/// Hover information
pub const Hover = struct {
    span: HoverSpan,
    text: HoverText,
};

/// Hover span
pub const HoverSpan = struct {
    start: u32,
    length: u32,
};

/// Hover text
pub const HoverText = struct {
    kind: HoverTextKind,
    text: []const u8,
};

/// Hover text kind
pub const HoverTextKind = enum {
    plain,
    code,
};

/// Quick info (hover at cursor)
pub const QuickInfo = struct {
    kind: SymbolKind,
    kind_modifiers: SymbolKindModifiers = .{},
    span: QuickInfoSpan,
    text: QuickInfoText,
};

/// Quick info span
pub const QuickInfoSpan = struct {
    start: u32,
    length: u32,
};

/// Quick info text
pub const QuickInfoText = struct {
    kind: SymbolDisplayPartKind,
    parts: []SymbolDisplayPart,
};

/// Symbol display part (link, etc.)
pub const SymbolDisplayPart = struct {
    text: []const u8,
    kind: SymbolDisplayPartKind,
};

/// Symbol display part kind
pub const SymbolDisplayPartKind = enum {
    alias_name,
    class_name,
    enum_name,
    field_name,
    interface_name,
    keyword,
    line_break,
    numeric_literal,
    string_literal,
    local_name,
    method_name,
    numeric_literal,
    operator,
    parameter,
    property_name,
    punctuation,
    space,
    text,
    type_parameter_name,
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
    let,
    method,
    get,
    set,
};

/// Symbol kind modifiers
pub const SymbolKindModifiers = struct {
    declaration: bool = false,
    read_only: bool = false,
    optional: bool = false,
    transient: bool = false,
    binary: bool = false,
    readonly: bool = false,
    static: bool = false,
    private: bool = false,
    protected: bool = false,
    public: bool = false,
    export: bool = false,
    local: bool = false,
};

/// Signature information
pub const SignatureInformation = struct {
    documentation: ?[]SymbolDisplayPart,
    parameters: []ParameterInformation,
    separator: u32 = 0,
};

/// Parameter information
pub const ParameterInformation = struct {
    name: []const u8,
    documentation: ?[]SymbolDisplayPart,
    span: QuickInfoSpan,
};

/// Call signature help
pub const CallSignatureHelp = struct {
    kind: SignatureHelpKind,
    selected_signature: i32,
    arguments: []CallSignatureHelpArgument,
};

/// Call signature help kind
pub const SignatureHelpKind = enum {
    current_signature,
};

/// Call signature help argument
pub const CallSignatureHelpArgument = struct {
    kind: SignatureHelpArgumentKind,
    start: u32,
    length: u32,
    resolved: ?Hover = null,
};

/// Call signature help argument kind
pub const SignatureHelpArgumentKind = enum {
    literal,
    identifier,
};
