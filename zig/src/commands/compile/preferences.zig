const std = @import("std");

/// Serialized language service state
pub const SerializedLanguageServiceState = struct {
    version: u32,
    files: []FileState,
};

/// File state
pub const FileState = struct {
    name: []const u8,
    text: []const u8,
    version: u32,
    modified: bool,
};

/// Language service options
pub const LanguageServiceOptions = struct {
    disable_size_limit: bool = false,
    no_get_err_on_budget_empty: bool = false,
    get_err_budget: u32 = 300,
    get_err_budget_high: u32 = 1500,
};

/// Format options
pub const FormatOptions = struct {
    tab_size: u32 = 4,
    insert_space_after_comma_delimiter: bool = true,
    insert_space_after_semicolon_in_for_statements: bool = true,
    insert_space_before_and_after_binary_operators: bool = true,
    insert_space_after_keywords_in_control_flow_statements: bool = true,
    insert_space_after_function_keyword_for_anonymous_functions: bool = true,
    insert_space_after_opening_and_closing_parentheses_for_expressions: bool = false,
    place_open_brace_on_new_line_for_control_blocks: bool = false,
    place_open_brace_on_new_line_for_functions: bool = false,
};

/// Format on save options
pub const FormatOnSaveOptions = struct {
    enabled: bool = false,
    format_options: FormatOptions,
};

/// User preferences
pub const UserPreferences = struct {
    disable_size_limit: bool = false,
    disable_tab_stops: bool = false,
    suggest_full_highlight: bool = false,
    include_inlay_function_parameter_type_hints: bool = false,
    include_inlay_parameter_name_hints: ?[]const u8 = null,
    include_inlay_parameter_name_hints_before_arguments: bool = false,
    include_inlay_variable_type_hints: bool = false,
    include_inlay_property_declaration_type_hints: bool = false,
    include_inlay_function_like_return_type_hints: bool = false,
};
