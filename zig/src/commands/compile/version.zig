const std = @import("std");

/// Version info
pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
    build: ?[]const u8 = null,

    pub fn toString(self: *const Version) []const u8 {
        if (self.build) |b| {
            return std.fmt.comptimePrint("{d}.{d}.{d}-{s}", .{ self.major, self.minor, self.patch, b });
        }
        return std.fmt.comptimePrint("{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }
};

/// Language version
pub const LanguageVersion = enum {
    ES3,
    ES5,
    ES6,
    ES2015,
    ES2016,
    ES2017,
    ES2018,
    ES2019,
    ES2020,
    ES2021,
    ES2022,
    ES2023,
    ES2024,
    ESNext,
    Latest,
};

/// TypeScript version
pub const ts_version = Version{
    .major = 5,
    .minor = 4,
    .patch = 0,
    .build = null,
};

/// Emit for language version
pub const EmitForLanguageVersion = struct {
    emitter: *anyopaque,
    language_version: LanguageVersion,
};

/// Supported language versions
pub const supported_language_versions = [_]LanguageVersion{
    .ES2020,
    .ES2022,
    .ESNext,
};

/// Get version string
pub fn getVersion() []const u8 {
    return ts_version.toString();
}
