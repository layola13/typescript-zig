const std = @import("std");
const source = @import("source_file.zig");

/// Navigable language service for find definition, references, etc.
pub const NavigationHost = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) NavigationHost {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *NavigationHost) void {
        _ = self;
    }
};

/// Navigation item (class, function, etc.)
pub const NavigationItem = struct {
    text: []const u8,
    kind: NavigationKind,
    kind_modifiers: NavigationKindModifiers = .{},
    span: NavigationSpan,
    children: ?[][]const u8 = null,
};

/// Navigation kind
pub const NavigationKind = enum {
    /// Warning: this is namespace for module or overloaded callable namespaces only
    call,
    class,
    enum,
    interface,
    /// Warning: instantiated classes, interfaces, etc
    variable,
    function,
    /// Warning: instantiated modules
    module,
    const,
    local_const,
    parameter,
    let,
    local_let,
    property,
    getter,
    setter,
    constructor,
    index,
    /// Call signatures only
    callSignature,
    constructSignature,
    indexSignature,
    /// Warning: instantiated signatures
    functionSignature,
    method,
    /// Warning: instantiated methods
    methodSignature,
    typeParameter,
    enumMember,
    key,
    spread,
    /// Warning: Instantiated jsx fragment
    jsxTag,
    reference,
    type,
    keyword,
    symbol,
    string,
};

/// Navigation kind modifiers
pub const NavigationKindModifiers = struct {
    declaration: bool = false,
    definition: bool = false,
    readonly: bool = false,
    static: bool = false,
    private: bool = false,
    protected: bool = false,
    public: bool = false,
    export: bool = false,
    local: bool = false,
};

/// Navigation span
pub const NavigationSpan = struct {
    start: u32,
    length: u32,
};

/// Navigation tree (breadcrumbs structure)
pub const NavigationTree = struct {
    text: []const u8,
    kind: NavigationKind,
    kind_modifiers: NavigationKindModifiers,
    span: NavigationSpan,
    child_items: ?[]NavigationItem,
    indent: u32 = 0,
};
