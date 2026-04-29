const std = @import("std");

/// Emit helper name
pub const EmitHelperName = enum {
    awaiter,
    classPrivateField,
    decorate,
    decorator,
    extends,
    get,
    identity,
    initializer,
    set,
    setAccessor,
    tsDecorate,
    tsDestroy,
    tsGenerator,
    tsMetadata,
    tsparam,
    tsReadonly,
    rest,
    setModuleName,
    spread,
    spreadArray,
    taggedTemplate,
    tslib,
};

/// Import emit helper
pub const ImportEmitHelper = struct {
    name: EmitHelperName,
    import_name: []const u8,
    module_name: []const u8,
};

/// Emit helpers configuration
pub const EmitHelpers = struct {
    import_helper: ?ImportEmitHelper = null,
    extends_helper: ?ImportEmitHelper = null,
};

/// Default emit helpers
pub const default_emit_helpers = EmitHelpers{};

/// Source map kind
pub const SourceMapKind = enum {
    none,
    inline,
    external,
};

/// New line kind
pub const NewLineKind = enum {
    crlf,
    lf,
};

/// Script target (from tsoptions)
pub const ScriptTarget = enum {
    es3,
    es5,
    es6,
    es2015,
    es2016,
    es2017,
    es2018,
    es2019,
    es2020,
    es2021,
    es2022,
    es2023,
    es2024,
    esnext,
    latest,
    json,
    preserve,
};

/// Module kind (from tsoptions)
pub const ModuleKind = enum {
    none,
    commonjs,
    amd,
    umd,
    system,
    es6,
    es2015,
    es2020,
    es2022,
    esnext,
    node16,
    node18,
    nodenext,
    preserve,
};

/// Import kind
pub const ImportKind = enum {
    other,
    commonjs,
    es2015,
    jsx,
    none,
};

/// Change kind
pub const ChangeKind = enum {
    inserted,
    deleted,
    modified,
};

/// Change range
pub const ChangeRange = struct {
    span: TextSpan,
    new_length: u32,
};

/// Text span
pub const TextSpan = struct {
    start: u32,
    length: u32,
};
