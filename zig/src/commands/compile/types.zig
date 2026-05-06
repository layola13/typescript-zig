const std = @import("std");

pub const DiagnosticSeverity = enum {
    @"error",
    warning,
    information,
    hint
};

pub const Diagnostic = struct {
    severity: DiagnosticSeverity,
    error_code: u32,
    message: []const u8,
    file: ?[]const u8 = null,
    line: u32 = 0,
    column: u32 = 0,
    length: u32 = 0,
};

pub const CompileFlags = struct {
    out_dir: ?[]const u8 = null,
    tsconfig_path: ?[]const u8 = null,
    graph_json: bool = false,
    show_config: bool = false,
    list_files_only: bool = false,
    ignore_config: bool = false,
    help: bool = false,
    version: bool = false,
    init: bool = false,
    all: bool = false,
    verbose: bool = false,
    debug: bool = false,
};

pub const ConfigResolution = enum(u4) {
    none,
    no,
    found,
    fallback,
    explicit_project,
    skipped_by_ignore_config,
    discovered_local_tsconfig
};

pub const Action = enum {
    compile,
    build,
    start_watch,
    print_help,
    print_version,
    init_config,
    show_config,
    failed
};

pub const CompileAction = Action;

pub const Mode = enum(u2) {
    normal = 0,
    build = 1,
    watch = 2
};

pub const CompileRequest = struct {
    project_path: ?[]const u8 = null,
    out_dir: ?[]const u8 = null,
    tsconfig_path: ?[]const u8 = null,
    compile_mode: @import("../../cli/types.zig").CompileMode = .normal,
    mode: Mode = .normal,
    flags: CompileFlags = .{},
    entry_files: std.ArrayList([]const u8),
    passthrough: std.ArrayList([]const u8),
    missing_project_value: bool = false,

    pub fn init(allocator: std.mem.Allocator, compile_mode: @import("../../cli/types.zig").CompileMode) CompileRequest {
        return .{
            .project_path = null,
            .out_dir = null,
            .tsconfig_path = null,
            .compile_mode = compile_mode,
            .mode = .normal,
            .flags = .{},
            .entry_files = std.ArrayList([]const u8).init(allocator),
            .passthrough = std.ArrayList([]const u8).init(allocator),
            .missing_project_value = false,
        };
    }

    pub fn deinit(self: *CompileRequest) void {
        self.entry_files.deinit();
        self.passthrough.deinit();
    }
};

pub const CompileResult = struct {
    exit_code: u8,
    action: Action,
    mode: Mode,
    config_resolution: ConfigResolution,
    list_files_only: bool,
    native_failed: bool,
    diagnostic: ?Diagnostic,
    project_path: ?[]const u8 = null,
    resolved_config_path: ?[]const u8 = null,
    forwarded_arg_count: usize = 0,
    entry_file_count: usize = 0,

    pub fn init(action: Action) CompileResult {
        return .{
            .exit_code = 0,
            .action = action,
            .mode = .normal,
            .config_resolution = .none,
            .list_files_only = false,
            .native_failed = false,
            .diagnostic = null,
            .project_path = null,
            .resolved_config_path = null,
            .forwarded_arg_count = 0,
            .entry_file_count = 0,
        };
    }
};

pub const TypeKind = enum(u8) {
    invalid,
    null,
    undefined,
    void,
    never,
    unknown,
    any,
    number,
    boolean,
    string,
    symbol,
    object,
    array,
    function,
    constructor,
    class,
    enum_type,
    interface,
    namespace,
    module,
    method,
    member,
    variable,
    parameter,
    property,
    alias
};

/// Type checking statistics
pub const TypeStats = struct {
    checked_count: usize = 0,
    errors_count: usize = 0,
    warnings_count: usize = 0,
    source_count: usize = 0,
    function_count: usize = 0,
    class_count: usize = 0,
    interface_count: usize = 0,
};
