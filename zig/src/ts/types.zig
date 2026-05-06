//! Type definitions for TypeScript type checker

const std = @import("std");

/// Primitive type kinds
pub const PrimitiveKind = enum {
    void,
    number,
    string,
    boolean,
    null,
    undefined,
    unknown,
    any,
    never,
    symbol,
    bigint,
};

/// Object type kinds
pub const ObjectKind = enum {
    object,
    array,
    func,
    class,
    interface,
};

/// Type representation
pub const Type = union(enum) {
    primitive: PrimitiveKind,
    object: ObjectKind,
    reference: []const u8,
    union_types: []const Type,
    intersection: []const Type,

    pub fn eql(a: Type, b: Type) bool {
        switch (a) {
            .primitive => |pa| {
                if (switch (b) {
                    .primitive => |pb| pa == pb,
                    else => false,
                }) return true;
            },
            .object => |oa| {
                if (switch (b) {
                    .object => |ob| oa == ob,
                    else => false,
                }) return true;
            },
            .reference => |ra| {
                if (switch (b) {
                    .reference => |rb| std.mem.eql(u8, ra, rb),
                    else => false,
                }) return true;
            },
            else => {},
        }
        return false;
    }
};

/// Built-in type constants
pub const BuiltinType = struct {
    pub const void = Type{ .primitive = .void };
    pub const number = Type{ .primitive = .number };
    pub const string = Type{ .primitive = .string };
    pub const boolean = Type{ .primitive = .boolean };
    pub const null = Type{ .primitive = .null };
    pub const undefined = Type{ .primitive = .undefined };
    pub const unknown = Type{ .primitive = .unknown };
    pub const any = Type{ .primitive = .any };
    pub const never = Type{ .primitive = .never };
    pub const symbol = Type{ .primitive = .symbol };
    pub const bigint = Type{ .primitive = .bigint };
    pub const obj = Type{ .object = .object };
    pub const arr = Type{ .object = .array };
    pub const func = Type{ .object = .function };
};

/// Check if source type is assignable to target type
pub fn isAssignableTo(source: Type, target: Type) bool {
    // any and unknown accept anything
    if (target == .any) return true;
    if (target == .unknown) return true;

    // never is assignable to everything
    if (source == .never) return true;

    // null/undefined special cases
    if (target == .undefined) return source == .undefined or source == .null;
    if (target == .null) return source == .null;
    if (target == .void) return source == .void or source == .null or source == .undefined;

    // Exact match
    if (Type.eql(source, target)) return true;

    // Primitive assignability
    if (source == .primitive and target == .primitive) {
        return source.primitive == target.primitive;
    }

    // Object kind assignability
    if (source == .object and target == .object) {
        return source.object == target.object;
    }

    return false;
}

/// Get string representation of a type
pub fn typeToString(t: Type) []const u8 {
    switch (t) {
        .primitive => |pk| {
            switch (pk) {
                .void => return "void",
                .number => return "number",
                .string => return "string",
                .boolean => return "boolean",
                .null => return "null",
                .undefined => return "undefined",
                .unknown => return "unknown",
                .any => return "any",
                .never => return "never",
                .symbol => return "symbol",
                .bigint => return "bigint",
            }
        },
        .object => |ok| {
            switch (ok) {
                .object => return "object",
                .array => return "array",
                .func => return "function",
                .class => return "class",
                .interface => return "interface",
            }
        },
        .reference => |name| return name,
        .union_types => return "union",
        .intersection => return "intersection",
    }
}
