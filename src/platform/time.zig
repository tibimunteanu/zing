const std = @import("std");

const Errors = @import("errors.zig");

var initialized = false;
var start_ns: i96 = 0;
var offset_ns: i128 = 0;

pub fn initSystem() !void {
    start_ns = nowNs();
    offset_ns = 0;
    initialized = true;
}

pub fn deinitSystem() void {
    initialized = false;
}

pub fn get() !f64 {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    const elapsed = @as(i128, @intCast(nowNs() - start_ns)) + offset_ns;
    return @as(f64, @floatFromInt(@max(0, elapsed))) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

pub fn set(seconds: f64) !void {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    const max_seconds = @as(f64, @floatFromInt(std.math.maxInt(u64) / std.time.ns_per_s));
    if (std.math.isNan(seconds) or seconds < 0.0 or seconds > max_seconds) {
        Errors.report(.invalid_value, "invalid time value: {d}", .{seconds});
        return error.InvalidValue;
    }

    const requested_ns: i128 = @intFromFloat(seconds * @as(f64, @floatFromInt(std.time.ns_per_s)));
    offset_ns = requested_ns - @as(i128, @intCast(nowNs() - start_ns));
}

pub fn getTimerValue() !u64 {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    return @intCast(@max(0, nowNs() - start_ns));
}

pub fn getTimerFrequency() !u64 {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    return std.time.ns_per_s;
}

fn nowNs() i96 {
    const io = std.Io.Threaded.global_single_threaded.io();
    return std.Io.Clock.awake.now(io).nanoseconds;
}
