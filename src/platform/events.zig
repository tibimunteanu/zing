const std = @import("std");

const Errors = @import("errors.zig");
const platform = @import("platform.zig");

pub fn poll() !void {
    platform.Events.poll();
}

pub fn wait() !void {
    platform.Events.wait();
}

pub fn waitTimeout(timeout: f64) !void {
    if (std.math.isNan(timeout) or timeout < 0.0) {
        Errors.report(.invalid_value, "invalid event wait timeout {d}", .{timeout});
        return error.InvalidValue;
    }
    platform.Events.waitTimeout(timeout);
}

pub fn postEmpty() !void {
    platform.Events.postEmpty();
}
