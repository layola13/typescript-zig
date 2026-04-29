const std = @import("std");

/// Grammar check options
pub const GrammarCheckOptions = struct {
    check_grammar: bool = true,
};

/// Grammar error
pub const GrammarError = struct {
    code: u32,
    message: []const u8,
    position: u32,
};

/// Check grammar
pub fn checkGrammar(text: []const u8, options: GrammarCheckOptions) ![]GrammarError {
    _ = text;
    _ = options;
    return &.{};
}

/// Has grammar error
pub fn hasGrammarError(errors: []GrammarError) bool {
    return errors.len > 0;
}
