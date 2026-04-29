pub const text =
    \\zts - Zig TypeScript compiler prototype
    \\
    \\Usage:
    \\  zts [options]
    \\  zts compile [files...]
    \\  zts lsp
    \\  zts api
    \\
    \\Options:
    \\  -h, --help       Show this help text
    \\  -v, --version    Show version
    \\  --lsp            Alias for `zts lsp`
    \\  --api            Alias for `zts api`
    \\  -b, --build      Compile in build mode
    \\  -w, --watch      Compile in watch mode
    \\
;

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(text);
}
