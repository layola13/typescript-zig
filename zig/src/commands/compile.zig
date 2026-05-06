const std = @import("std");
const cli_types = @import("../cli/types.zig");
const compile_execute = @import("./compile/execute.zig");
const compile_parse = @import("./compile/parse.zig");
const compile_plan = @import("./compile/plan.zig");
const compile_source = @import("./compile/source.zig");
const compile_binder = @import("./compile/binder.zig");
const compile_checker = @import("./compile/checker.zig");
const compile_emitter = @import("./compile/emitter.zig");

pub fn run(request: *const cli_types.ParsedArgs, writer: anytype) !u8 {
    const allocator = std.heap.page_allocator;

    var compile_request = try compile_parse.requestFromParsed(allocator, request);
    defer compile_request.deinit();

    const result = compile_execute.execute(&compile_request);

    var native_plan = try compile_plan.buildPlan(allocator, &compile_request, &result);
    defer native_plan.deinit(allocator);

    try writer.writeAll("zts: compile phase=plan\n");
    try compile_plan.writePlan(writer, &compile_request, &result, &native_plan);

    var source_summary = try compile_source.loadSources(allocator, &native_plan);
    defer source_summary.deinit(allocator);

    try writer.writeAll("zts: compile phase=source\n");
    try compile_source.writeSummary(writer, &native_plan, &source_summary);

    try writer.print("zts: tokenize summary(tokens={d})\n", .{source_summary.token_count});

    try writer.print(
        "zts: parse summary(decls={d}, imports={d}, exports={d}, functions={d}, classes={d})\n",
        .{
            source_summary.declaration_count,
            source_summary.import_count,
            source_summary.export_count,
            source_summary.function_count,
            source_summary.class_count,
        },
    );

    var bind_summary = try compile_binder.bindProgram(allocator, &source_summary);
    defer bind_summary.deinit(allocator);

    try writer.writeAll("zts: compile phase=bind\n");
    try compile_binder.writeSummary(writer, &bind_summary);

    var check_summary = try compile_checker.checkProgram(allocator, &native_plan, &source_summary, &bind_summary);
    defer check_summary.deinit(allocator);

    try writer.writeAll("zts: compile phase=check\n");
    try compile_checker.writeSummary(writer, &check_summary);

    // Emit phase
    try writer.writeAll("zts: compile phase=emit\n");
    const emit_options = compile_emitter.EmitOptions{
        .emit_js = true,
        .emit_declarations = false,
        .out_dir = native_plan.out_dir,
        .root_dir = native_plan.root_dir,
        .config_dir = native_plan.config_dir,
    };
    var emit_result = try compile_emitter.emitProgram(allocator, &source_summary, emit_options);
    defer emit_result.deinit();

    if (emit_result.diagnostics.items.len > 0) {
        for (emit_result.diagnostics.items) |diag| {
            try writer.print("zts: emit error: {s}: {s}\n", .{ diag.path, diag.message });
        }
    }

    // Write JS output
    if (emit_result.js_output.items.len > 0) {
        try writer.writeAll(emit_result.js_output.items);
    }

    const has_errors = check_summary.diagnostics.items.len > 0 or 
                       source_summary.diagnostics.items.len > 0 or
                       emit_result.diagnostics.items.len > 0;
    try writer.print("zts: compile complete status={s} files={d}\n", .{
        if (has_errors) "errors" else "ok",
        source_summary.loaded_count,
    });

    if (has_errors) {
        try writer.writeAll("zts: compile failed\n");
        return 1;
    }

    return 0;
}
