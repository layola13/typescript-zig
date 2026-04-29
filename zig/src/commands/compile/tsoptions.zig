const std = @import("std");
const root = @import("../../../main.zig");
const types = @import("types.zig");

// ============================================================================
// Types
// ============================================================================

pub const ScriptTarget = enum(i32) {
    es3 = 0,
    es5 = 1,
    es6 = 2, // aka es2015
    es2015 = 2,
    es2016 = 3,
    es2017 = 4,
    es2018 = 5,
    es2019 = 6,
    es2020 = 7,
    es2021 = 8,
    es2022 = 9,
    es2023 = 10,
    es2024 = 11,
    esnext = 12,
    latest = 12,
    json = 13,
    preserve = 14,
};

pub const ModuleKind = enum(i32) {
    none = 0,
    commonjs = 1,
    amd = 2,
    umd = 3,
    system = 4,
    es6 = 5, // aka es2015
    es2015,
    es2020 = 7,
    es2022 = 8,
    esnext = 9,
    node16 = 10,
    node18 = 11,
    node20 = 12,
    nodenext = 13,
    preserve = 14,
};

pub const JsxEmit = enum(i32) {
    none = 0,
    preserve = 1,
    react = 2,
    react_jsx = 3,
    react_jsxdev = 4,
    react_native = 5,
};

pub const NewLineKind = enum(i32) {
    crlf = 0,
    lf = 1,
};

pub const ModuleResolutionKind = enum(i32) {
    classic = 1,
    node = 2, // aka node10
    node10 = 2,
    node16 = 3,
    node20 = 4,
    bundler = 5,
    nodenext = 6,
};

pub const ModuleDetectionKind = enum(i32) {
    auto = 1,
    force = 2,
    force_legacy = 3,
};

pub const LanguageVariant = enum(i32) {
    standard = 0,
    jsx = 1,
};

/// Tristate: .unset = unknown, .yes = true, .no = false
pub const Tristate = enum(i32) {
    unset = -1,
    no = 0,
    yes = 1,
};

/// Compiler options parsed from tsconfig.json or command line
pub const CompilerOptions = struct {
    target: ScriptTarget = .esnext,
    module: ModuleKind = .commonjs,
    jsx: JsxEmit = .none,
    new_line: NewLineKind = .lf,
    module_resolution: ModuleResolutionKind = .node10,

    // File management
    out_dir: ?[]const u8 = null,
    root_dir: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    ts_build_info_file: ?[]const u8 = null,
    out_file: ?[]const u8 = null,

    // Source maps
    source_map: bool = false,
    inline_source_map: bool = false,
    inline_sources: bool = false,
    source_root: ?[]const u8 = null,
    map_root: ?[]const u8 = null,

    // JS/TS support
    allow_js: Tristate = .unset,
    check_js: Tristate = .unset,
    max_node_module_js_depth: ?i32 = null,

    // Module options
    allow_arbitrary_extensions: bool = false,
    allow_importing_ts_extensions: bool = false,
    allow_umd_global_access: bool = false,
    es_module_interop: bool = false,
    force_consistent_casing_in_file_names: bool = false,
    isolated_modules: bool = false,
    preserve_symlinks: bool = false,
    resolve_json_module: bool = false,
    root_dirs: ?[]const []const u8 = null,

    // Emit options
    declaration: bool = false,
    declaration_map: bool = false,
    emit: bool = false,
    emit_bom: bool = false,
    no_resolve_json_module: bool = false,
    out: ?[]const u8 = null,

    // Type checking
    strict: bool = false,
    no_implicit_any: bool = false,
    strict_null_checks: bool = false,
    strict_function_types: bool = false,
    strict_bind_call_apply: bool = false,
    strict_property_initialization: bool = false,
    no_implicit_this: bool = false,
    always_strict: bool = false,

    // Output
    charset: ?[]const u8 = null,
    diagnostics: bool = false,
    no_error_truncation: bool = false,
    preserve_watch_output: bool = false,
    pretty: bool = false,

    // Build mode
    dry: bool = false,
    force: bool = false,
    verbose: bool = false,
    skip_lib_check: bool = false,
    skip_default_lib_check: bool = false,

    // Lib
    lib: ?[]const []const u8 = null,

    // Types
    types: ?[]const []const u8 = null,
    type_roots: ?[]const []const u8 = null,

    // JSX options
    jsx_factory: ?[]const u8 = null,
    jsx_fragment_factory: ?[]const u8 = null,
    jsx_import_source: ?[]const u8 = null,
    no_lib: bool = false,

    // Other
    no_unused_locals: bool = false,
    no_unused_parameters: bool = false,
    no_implicit_returns: bool = false,
    no_fallthrough_cases_in_switch: bool = false,
    trace_resolution: bool = false,
    extended_diagnostics: bool = false,
    generate_cpu_profile: ?[]const u8 = null,
    help: bool = false,
    init: bool = false,
    list_emitted_files: bool = false,
    list_files: bool = false,
    max_workers: ?i32 = null,
    version: bool = false,
    watch: bool = false,
    all: bool = false,
    build: bool = false,
    declaration_dir: ?[]const u8 = null,
};

/// Parsed command line options
pub const ParsedCommandLine = struct {
    options: CompilerOptions,
    file_names: [][]const u8,
    errors: []types.Diagnostic,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ParsedCommandLine {
        return .{
            .allocator = allocator,
            .options = .{
                .target = .esnext,
                .module = .commonjs,
            },
            .file_names = &.{},
            .errors = &.{},
        };
    }

    pub fn deinit(self: *ParsedCommandLine) void {
        for (self.file_names) |name| self.allocator.free(name);
        self.allocator.free(self.file_names);
        for (self.errors) |err| {
            self.allocator.free(err.message);
        }
        self.allocator.free(self.errors);
    }
};

/// Parse command line arguments into ParsedCommandLine
pub fn parseCommandLine(allocator: std.mem.Allocator, args: [][]const u8) !ParsedCommandLine {
    var result = ParsedCommandLine.init(allocator);
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            const name = arg[2..];
            if (std.mem.eql(u8, name, "project") or std.mem.eql(u8, name, "p")) {
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, name, "outDir")) {
                i += 1;
                continue;
            }
            if (std.mem.eql(u8, name, "rootDir")) {
                i += 1;
                continue;
            }
        }
        try result.file_names.append(arg);
    }
    return result;
}
