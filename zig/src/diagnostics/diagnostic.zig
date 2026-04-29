const std = @import("std");

/// Diagnostic severity
pub const DiagnosticSeverity = enum(u8) {
    error = 1,
    warning = 2,
    information = 3,
    hint = 4,
};

/// Diagnostic related information
pub const DiagnosticRelatedInformation = struct {
    location: Location,
    message: []const u8,
};

/// Diagnostic
pub const Diagnostic = struct {
    range: Range,
    severity: DiagnosticSeverity,
    code: ?[]const u8 = null,
    source: ?[]const u8 = null,
    message: []const u8,
    related_information: ?[]DiagnosticRelatedInformation = null,
};

/// Location
pub const Location = struct {
    uri: []const u8,
    range: Range,
};

/// Range
pub const Range = struct {
    start: Position,
    end: Position,
};

/// Position
pub const Position = struct {
    line: u32,
    character: u32,
};
