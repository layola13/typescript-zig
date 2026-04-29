const std = @import("std");
const cli_types = @import("../../cli/types.zig");

pub const CompileFlags = struct {
    help: bool = false,
    version: bool = false,
    init: bool = false,
    show_config: bool = false,
    graph_json: bool = false,
    list_files_only: bool = false,
    ignore_config: bool = false,
    all: bool = false,
    out_dir: ?[]const u8 = null,
    tsconfig_path: ?[]const u8 = null,
};

pub const CompileRequest = struct {
    mode: cli_types.CompileMode,
    flags: CompileFlags = .{},
    passthrough: std.ArrayList([]const u8),
    entry_files: std.ArrayList([]const u8),
    project_path: ?[]const u8 = null,
    missing_project_value: bool = false,

    pub fn init(allocator: std.mem.Allocator, mode: cli_types.CompileMode) CompileRequest {
        return .{
            .mode = mode,
            .flags = .{},
            .passthrough = std.ArrayList([]const u8).init(allocator),
            .entry_files = std.ArrayList([]const u8).init(allocator),
            .project_path = null,
            .missing_project_value = false,
        };
    }

    pub fn deinit(self: *CompileRequest) void {
        self.passthrough.deinit();
        self.entry_files.deinit();
    }
};

pub const CompileAction = enum {
    print_help,
    print_version,
    init_config,
    show_config,
    start_watch,
    build,
    compile,
    failed,
};

pub const ConfigResolution = enum {
    none,
    explicit_project,
    discovered_local_tsconfig,
    skipped_by_ignore_config,
};

pub const CompileResult = struct {
    exit_code: u8,
    action: CompileAction,
    mode: cli_types.CompileMode,
    list_files_only: bool = false,
    native_failed: bool = false,
    config_resolution: ConfigResolution = .none,
    forwarded_arg_count: usize,
    entry_file_count: usize,
    project_path: ?[]const u8 = null,
    resolved_config_path: ?[]const u8 = null,
    diagnostic: ?[]const u8 = null,
};


/// Extended type kinds
pub const ExtendedTypeKind = enum {
    unknown,
    undef,
    null,
    number,
    string,
    boolean,
    symbol,
    void,
    object,
    reference,
    union_type,
    intersection,
    anonymous,
    enum_,
    enum_member,
    const_enum_member,
    value_element,
};

/// Type flags
pub const TypeFlags = struct {
    primitive: bool = false,
    string: bool = false,
    number: bool = false,
    boolean: bool = false,
    enum_: bool = false,
    struct_: bool = false,
    number_literal: bool = false,
    string_literal: bool = false,
    template_literal: bool = false,
    bigint: bool = false,
    bigint_literal: bool = false,
    import_type: bool = false,
};
