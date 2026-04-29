const std = @import("std");

/// Node flags
pub const NodeFlags = struct {
    has_jsx: bool = false,
    has_parse_error: bool = false,
    is_binder: bool = false,
    is_bindable_property_name: bool = false,
    check_js: bool = false,
    has_extra_react_nav: bool = false,
    disable_jsx: bool = false,
};

/// Syntax kind counts
pub const SyntaxKindCount = enum(u16) {
    unknown = 0,
    end_of_file_token = 1,
    single_line_comment = 2,
    multi_line_comment = 3,
    new_line = 4,
    open_brace = 5,
    close_brace = 6,
    open_paren = 7,
    close_paren = 8,
    open_bracket = 9,
    close_bracket = 10,
    dot_token = 11,
    dot_dot_dot_token = 12,
    semicolon = 13,
    comma = 14,
    lesser_than_token = 15,
    greater_than_token = 16,
    lesser_than_equals_token = 17,
    greater_than_equals_token = 18,
    double_equals_token = 19,
    not_equals_token = 20,
    triple_equals_token = 21,
    not_equals_equals_token = 22,
    equals_token = 23,
    plus_token = 24,
    minus_token = 25,
    asterisk_token = 26,
    slash_token = 27,
    percent_token = 28,
    caret_token = 29,
    pipe_token = 30,
    ampersand_token = 31,
    question_token = 32,
    colon_token = 33,
    at_token = 34,
    identifier = 35,
    keyword = 36,
    punctuation = 37,
    white_space = 38,
    unknown = 39,
};

/// Modifier flags
pub const ModifierFlags = struct {
    export: bool = false,
    ambient: bool = false,
    public: bool = false,
    private: bool = false,
    protected: bool = false,
    static: bool = false,
    readonly: bool = false,
    abstract: bool = false,
    async: bool = false,
    default: bool = false,
    const: bool = false,
    override: bool = false,
    declarator: bool = false,
};

/// Transform flags
pub const TransformFlags = struct {
    ambient: bool = false,
    type: bool = false,
    namespace: bool = false,
    parameter: bool = false,
    decorator: bool = false,
};

/// Node check result
pub const NodeCheck = struct {
    flags: NodeFlags,
    modifier_flags: ModifierFlags,
    transform_flags: TransformFlags,
};

/// Check node
pub fn checkNode(node: *anyopaque) NodeCheck {
    _ = node;
    return NodeCheck{ .flags = .{}, .modifier_flags = .{}, .transform_flags = .{} };
}
