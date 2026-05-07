
const std = @import("std");
const emitter = @import("commands/compile/emitter.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const contents = 
\export interface Person {
\    name: string;
\    age: number;
\}
\export type ID = string | number;
\
    ;

    var e = emitter.TypeScriptEmitter.init(allocator, contents);
    e.is_declaration = true;
    const dts = try e.emitDeclarations();
    defer allocator.free(dts);
    
    std.debug.print("=== DTS ===\n{s}\n=== END ===\n", .{dts});
}
