const std = @import("std");
const ast = @import("ast/kind.zig");

/// Source file representation
pub const SourceFile = struct {
    filename: []const u8,
    text: []const u8,
    script_kind: ScriptKind,
    parse_flags: ParseFlags = .{},

    pub fn getText(self: *const SourceFile) []const u8 {
        return self.text;
    }

    pub fn getLineStarts(self: *const SourceFile) []const u32 {
        _ = self;
        return &.{};
    }
};

/// Script kind
pub const ScriptKind = enum(u8) {
    unknown = 0,
    js = 1,
    ts = 2,
    jsx = 3,
    tsx = 4,
    json = 5,
};

/// Parse flags
pub const ParseFlags = struct {
    is_disappeared_comment: bool = false,
    is_prologue_directive: bool = false,
};

/// Source file loader
pub const SourceFileLoader = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap(SourceFile),

    pub fn init(allocator: std.mem.Allocator) SourceFileLoader {
        return .{
            .allocator = allocator,
            .files = std.StringHashMap(SourceFile).init(allocator),
        };
    }

    pub fn deinit(self: *SourceFileLoader) void {
        var it = self.files.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.files.deinit();
    }

    pub fn loadFile(self: *SourceFileLoader, filename: []const u8) !SourceFile {
        const text = try std.fs.cwd().readFileAlloc(self.allocator, filename, 4 * 1024 * 1024);
        const script_kind = getScriptKind(filename);
        const file = SourceFile{
            .filename = try self.allocator.dupe(u8, filename),
            .text = text,
            .script_kind = script_kind,
        };
        try self.files.put(file.filename, file);
        return file;
    }

    pub fn getFile(self: *const SourceFileLoader, filename: []const u8) ?SourceFile {
        return self.files.get(filename);
    }
};

/// Determine script kind from filename
pub fn getScriptKind(filename: []const u8) ScriptKind {
    if (std.mem.endsWith(u8, filename, ".js")) return .js;
    if (std.mem.endsWith(u8, filename, ".jsx")) return .jsx;
    if (std.mem.endsWith(u8, filename, ".ts")) return .ts;
    if (std.mem.endsWith(u8, filename, ".tsx")) return .tsx;
    if (std.mem.endsWith(u8, filename, ".json")) return .json;
    return .unknown;
}
