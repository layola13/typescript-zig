const std = @import("std");

/// Tracer event
pub const TracerEvent = struct {
    name: []const u8,
    timestamp: i64,
    duration_ns: i64,
    phase: TracerPhase,
    args: ?[]const u8,
};

/// Tracer phase
pub const TracerPhase = enum {
    Begin,
    End,
    Instant,
};

/// Tracer
pub const Tracer = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(TracerEvent),
    enabled: bool,

    pub fn init(allocator: std.mem.Allocator) Tracer {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(TracerEvent).init(allocator),
            .enabled = true,
        };
    }

    pub fn deinit(self: *Tracer) void {
        self.events.deinit();
    }

    pub fn begin(self: *Tracer, name: []const u8) !void {
        if (!self.enabled) return;
        try self.events.append(.{
            .name = try self.allocator.dupe(u8, name),
            .timestamp = std.time.timestamp(),
            .duration_ns = 0,
            .phase = .Begin,
            .args = null,
        });
    }

    pub fn end(self: *Tracer, name: []const u8) !void {
        if (!self.enabled) return;
        try self.events.append(.{
            .name = try self.allocator.dupe(u8, name),
            .timestamp = std.time.timestamp(),
            .duration_ns = 0,
            .phase = .End,
            .args = null,
        });
    }

    pub fn instant(self: *Tracer, name: []const u8) !void {
        if (!self.enabled) return;
        try self.events.append(.{
            .name = try self.allocator.dupe(u8, name),
            .timestamp = std.time.timestamp(),
            .duration_ns = 0,
            .phase = .Instant,
            .args = null,
        });
    }
};
