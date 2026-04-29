const std = @import("std");

/// Node flags
pub const NodeFlags = packed struct {
    has_jsdoc: bool = false,
    has_parse_error: bool = false,
    check_js: bool = false,
    is_prologue_directive: bool = false,
    is_binder: bool = false,
    disable_jsx: bool = false,
    ambient: bool = false,
    unused: u2 = 0,
};

/// Modifier flags
pub const ModifierFlags = packed struct {
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
    decorator: bool = false,
    unused: u4 = 0,
};

/// Symbol flags
pub const SymbolFlags = packed struct {
    value: bool = false,
    type: bool = false,
    namespace: bool = false,
    enum: bool = false,
    class: bool = false,
    enum_member: bool = false,
    variable: bool = false,
    function: bool = false,
    exported: bool = false,
    ambient: bool = false,
   augmented: bool = false,
    unused: u20 = 0,
};

/// Type flags
pub const TypeFlags = packed struct {
    primitive: bool = false,
    string: bool = false,
    number: bool = false,
    boolean: bool = false,
    void: bool = false,
    undefined: bool = false,
    null: bool = false,
    struct: bool = false,
    instrumented: bool = false,
    modified: bool = false,
    checked: bool = false,
    synthetic: bool = false,
    any: bool = false,
    unknown: bool = false,
    never: bool = false,
    type_parameter: bool = false,
    non_null: bool = false,
    nullable: bool = false,
    synthetic_type: bool = false,
    sibiling: bool = false,
    unused2: u12 = 0,
};
