const std = @import("std");
const source = @import("source_file.zig");
const symbols = @import("symbols.zig");
const parser = @import("parser.zig");

/// Binder context for binding declarations
pub const BinderContext = struct {
    allocator: std.mem.Allocator,
    file: *const source.SourceFile,
    program: *anyopaque,
    symbol_table: *symbols.SymbolTable,
    locals: std.StringHashMap(*symbols.Symbol),
    export_cache: ?*anyopaque = null,
    unresolved_imports: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, file: *const source.SourceFile) BinderContext {
        return .{
            .allocator = allocator,
            .file = file,
            .program = undefined,
            .symbol_table = undefined,
            .locals = std.StringHashMap(*symbols.Symbol).init(allocator),
        };
    }

    pub fn deinit(self: *BinderContext) void {
        self.locals.deinit();
    }

    /// Bind a source file
    pub fn bindSourceFile(self: *BinderContext) !void {
        const text = self.file.getText();
        const parsed = try parser.parseTopLevel(self.allocator, text);
        defer parsed.deinit(self.allocator);
        _ = self;
    }

    /// Check if symbol is visible
    pub fn isSymbolVisible(self: *const BinderContext, sym: *const symbols.Symbol) bool {
        _ = self;
        _ = sym;
        return true;
    }
};

/// Resolve name result
pub const ResolveNameResult = struct {
    symbol: ?*symbols.Symbol,
    is_hidden: bool,
};

/// Name resolution options
pub const NameResolutionOptions = struct {
    all_imports: bool = false,
    all_definitions: bool = false,
    exclude_builtins: bool = false,
};

/// Bind symbol flags
pub const BindSymbolFlags = struct {
    ignore_privacy: bool = false,
    ignore_lifetime: bool = false,
    ignore_this: bool = false,
    will_be_visible: bool = false,
};

/// Export container
pub const ExportContainer = struct {
    name: []const u8,
    kind: ExportContainerKind,
};

/// Export container kind
pub const ExportContainerKind = enum {
    unknown,
    module,
    namespace,
    class,
    enum_,
    interface,
};
