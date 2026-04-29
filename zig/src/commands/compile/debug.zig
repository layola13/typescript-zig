const std = @import("std");

/// Debug information types

/// Memory usage
pub const MemoryUsage = struct {
    total_physical: u64,
    total_virtual: u64,
    physical_used: u64,
    virtual_used: u64,
};

/// Performance metrics
pub const PerformanceMetrics = struct {
    parse_time: u64,
    bind_time: u64,
    check_time: u64,
    emit_time: u64,
    total_time: u64,
};

/// Trace event
pub const TraceEvent = struct {
    name: []const u8,
    timestamp: i64,
    duration: i64,
    args: ?[]const u8,
};

/// Profiler
pub const Profiler = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(TraceEvent),

    pub fn init(allocator: std.mem.Allocator) Profiler {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(TraceEvent).init(allocator),
        };
    }

    pub fn deinit(self: *Profiler) void {
        self.events.deinit();
    }

    pub fn startEvent(self: *Profiler, name: []const u8) !void {
        try self.events.append(.{
            .name = try self.allocator.dupe(u8, name),
            .timestamp = std.time.timestamp(),
            .duration = 0,
            .args = null,
        });
    }
};
