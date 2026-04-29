const cli_types = @import("../../cli/types.zig");
const types = @import("./types.zig");

pub fn writeResult(writer: anytype, result: types.CompileResult) !void {
    if (result.diagnostic) |diagnostic| {
        try writer.print("zts: compile request rejected: {s}\n", .{diagnostic});
        return;
    }

    try writer.print(
        "zts: compile request accepted (action={s}, mode={s}, args={d}, entries={d}, config={s})\n",
        .{
            actionLabel(result.action),
            modeLabel(result.mode),
            result.forwarded_arg_count,
            result.entry_file_count,
            configLabel(result.config_resolution),
        },
    );

    if (result.project_path) |project_path| {
        try writer.print("zts: project={s}\n", .{project_path});
    }

    if (result.resolved_config_path) |config_path| {
        try writer.print("zts: config-path={s}\n", .{config_path});
    }
}

fn actionLabel(action: types.CompileAction) []const u8 {
    return switch (action) {
        .print_help => "help",
        .print_version => "version",
        .init_config => "init",
        .show_config => "show-config",
        .start_watch => "watch",
        .build => "build",
        .compile => "compile",
        .failed => "failed",
    };
}

fn modeLabel(mode: cli_types.CompileMode) []const u8 {
    return switch (mode) {
        .normal => "normal",
        .build => "build",
        .watch => "watch",
    };
}

fn configLabel(config: types.ConfigResolution) []const u8 {
    return switch (config) {
        .none => "none",
        .explicit_project => "explicit-project",
        .discovered_local_tsconfig => "local-tsconfig",
        .skipped_by_ignore_config => "ignore-config",
    };
}
