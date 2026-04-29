const std = @import("std");

/// Utility functions for type checking

/// Check if type is unknown
pub fn isTypeUnknown(type_: *anyopaque) bool {
    _ = type_;
    return false;
}

/// Check if type is any
pub fn isTypeAny(type_: *anyopaque) bool {
    _ = type_;
    return false;
}

/// Check if type is void
pub fn isTypeVoid(type_: *anyopaque) bool {
    _ = type_;
    return false;
}

/// Check if types are equal
pub fn areTypesEqual(a: *anyopaque, b: *anyopaque) bool {
    _ = a;
    _ = b;
    return false;
}

/// Check if type is string literal
pub fn isStringLiteralType(type_: *anyopaque) bool {
    _ = type_;
    return false;
}
