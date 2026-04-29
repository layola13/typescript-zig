const std = @import("std");

/// Language service state
pub const LanguageServiceState = enum {
    closed,
    opening,
    opened,
    error,
};

/// Language service
pub const LanguageService = struct {
    state: LanguageServiceState = .closed,
    host: ?*anyopaque = null,
    cancel_token: ?*anyopaque = null,

    pub fn open(self: *LanguageService) !void {
        self.state = .opened;
    }

    pub fn close(self: *LanguageService) void {
        self.state = .closed;
    }

    pub fn getState(self: *const LanguageService) LanguageServiceState {
        return self.state;
    }
};
