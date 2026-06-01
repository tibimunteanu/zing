const std = @import("std");

const Errors = @import("errors.zig");
const platform = @import("platform.zig");

var initialized = false;
var offset: u64 = 0;
var frequency: u64 = std.time.ns_per_s;

pub fn initSystem() !void {
    if (!platform.Time.init()) {
        Errors.report(.platform_error, "failed to initialize platform timer", .{});
        return error.PlatformError;
    }
    frequency = platform.Time.getTimerFrequency();
    if (frequency == 0) {
        Errors.report(.platform_error, "platform timer frequency is zero", .{});
        return error.PlatformError;
    }
    offset = platform.Time.getTimerValue();
    initialized = true;
}

pub fn deinitSystem() void {
    platform.Time.deinit();
    initialized = false;
}

pub fn get() !f64 {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    return @as(f64, @floatFromInt(platform.Time.getTimerValue() -% offset)) / @as(f64, @floatFromInt(frequency));
}

pub fn set(seconds: f64) !void {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    if (std.math.isNan(seconds) or seconds < 0.0 or seconds > 18446744073.0) {
        Errors.report(.invalid_value, "invalid time value: {d}", .{seconds});
        return error.InvalidValue;
    }

    offset = platform.Time.getTimerValue() -% @as(u64, @intFromFloat(seconds * @as(f64, @floatFromInt(frequency))));
}

pub fn getTimerValue() !u64 {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    return platform.Time.getTimerValue();
}

pub fn getTimerFrequency() !u64 {
    if (!initialized) {
        Errors.report(.not_initialized, "time system is not initialized", .{});
        return error.NotInitialized;
    }

    return frequency;
}
