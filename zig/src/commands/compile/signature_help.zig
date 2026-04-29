const std = @import("std");

/// Signature help kinds
pub const SignatureHelpKinds = enum {
    current_signature,
};

/// Signature help item
pub const SignatureHelpItem = struct {
    isVariadic: bool,
    prefix_display_parts: []DisplayPart,
    suffix_display_parts: []DisplayPart,
    separator_display_parts: []DisplayPart,
    parameters: []SignatureHelpParameter,
    documentation: ?[]DisplayPart,
};

/// Display part (text with style)
pub const DisplayPart = struct {
    text: []const u8,
    kind: DisplayPartKind,
};

/// Display part kind
pub const DisplayPartKind = enum {
    function_name,
    method_name,
    constructor_name,
    parameter_name,
    punctuation,
    type_string,
    space,
    keyword,
    operator,
    enum_member_name,
    property_name,
    numeric_literal,
    string_literal,
    external_module_name,
    text,
};

/// Signature help parameter
pub const SignatureHelpParameter = struct {
    name: []const u8,
    documentation: ?[]DisplayPart,
    display_parts: []DisplayPart,
    is_optional: bool = false,
};

/// Call signature help for JSX
pub const CallSignatureHelpForJsx = struct {
    attribute: ?[]u8,
    closing_tag: ?[]u8,
};
